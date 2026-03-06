@testitem "selective extraction - zip file" begin
    using ZipFile
    using DataFrames
    using CSV
    
    # Helper function to create test package with controlled file sizes
    function make_test_package_with_sizes(pkg_root)
        pkg_loc = joinpath(pkg_root, "replication-package")
        pkg_data = joinpath(pkg_loc, "data")
        pkg_code = joinpath(pkg_loc, "code")
        mkpath(pkg_data)
        mkpath(pkg_code)
        
        # Create README
        open(joinpath(pkg_loc, "README.md"), "w") do io
            println(io, "# Test Package for Selective Extraction")
            println(io, "This tests large file handling.")
        end
        
        # Create SMALL data file (~0.5 MB with PII)
        small_data = DataFrame(
            id = 1:5000,
            name = repeat(["Alice", "Bob", "Charlie"], outer=2000)[1:5000],
            email = ["user$i@example.com" for i in 1:5000],
            value = rand(5000)
        )
        CSV.write(joinpath(pkg_data, "small_data.csv"), small_data)
        
        # Create LARGE data file (~3 MB - just random data, no PII needed)
        large_data = DataFrame(
            x = rand(30000),
            y = rand(30000),
            z = rand(30000),
            w = rand(30000)
        )
        CSV.write(joinpath(pkg_data, "large_data.csv"), large_data)
        
        # Create some code file with PII references
        open(joinpath(pkg_code, "analysis.R"), "w") do io
            println(io, "# Load data")
            println(io, "data <- read.csv('small_data.csv')")
            println(io, "# Process names")
            println(io, "data\$first_name <- clean(data\$name)")
        end
        
        return pkg_loc
    end
    
    # Create test package
    tmpdir = mktempdir()
    pkg_loc = make_test_package_with_sizes(tmpdir)
    
    # Verify both files exist before zipping
    small_file = joinpath(pkg_loc, "data", "small_data.csv")
    large_file = joinpath(pkg_loc, "data", "large_data.csv")
    @test isfile(small_file)
    @test isfile(large_file)
    
    small_size_mb = filesize(small_file) / 1024^2
    large_size_mb = filesize(large_file) / 1024^2
    @test small_size_mb < 1.0  # Should be < 1 MB
    @test large_size_mb > 2.0  # Should be > 2 MB
    
    # Create zip file
    zip_path = joinpath(tmpdir, "test_package.zip")
    cd(tmpdir) do
        run(`zip -r $zip_path $(basename(pkg_loc))`)
    end
    @test isfile(zip_path)
    
    # Clean up extracted directory for fresh test
    rm(pkg_loc, recursive=true, force=true)
    @test !isdir(pkg_loc)
    
    # Test selective extraction with threshold = 1.5 MB
    # (should extract small file, skip large file)
    pkg_dir, manifest = PackageScanner.prepare_package_for_precheck(
        zip_path,
        size_threshold_gb=1.5/1024,  # ~1.5 MB converted to GB
        interactive=false
    )
    
    # Verify manifest structure
    @test !isnothing(manifest)
    @test isa(manifest, DataFrame)
    @test "filepath" in names(manifest)
    @test "size_bytes" in names(manifest)
    @test "extracted" in names(manifest)
    @test "checked" in names(manifest)
    
    # Verify manifest contains both files
    @test any(occursin("small_data.csv", row.filepath) for row in eachrow(manifest))
    @test any(occursin("large_data.csv", row.filepath) for row in eachrow(manifest))
    
    # Verify extraction status
    small_row = findfirst(row -> occursin("small_data.csv", row.filepath), eachrow(manifest))
    large_row = findfirst(row -> occursin("large_data.csv", row.filepath), eachrow(manifest))
    
    @test !isnothing(small_row)
    @test !isnothing(large_row)
    @test manifest[small_row, :extracted] == true   # Small file extracted
    @test manifest[large_row, :extracted] == false  # Large file NOT extracted
    
    # Verify physical extraction
    extracted_small = joinpath(pkg_dir, manifest[small_row, :filepath])
    extracted_large = joinpath(pkg_dir, manifest[large_row, :filepath])
    @test isfile(extracted_small)   # Should exist on disk
    @test !isfile(extracted_large)  # Should NOT exist on disk
    
    # Run precheck with manifest
    out_dir = joinpath(dirname(pkg_dir), "generated")
    redirect_stdout(devnull) do
        PackageScanner.precheck_package(pkg_dir, pre_manifest=manifest)
    end
    
    # Verify extraction summary report exists
    summary_report = joinpath(out_dir, "report-extraction-summary.md")
    @test isfile(summary_report)
    
    # Verify summary report content
    summary_content = read(summary_report, String)
    @test occursin("selective extraction", lowercase(summary_content))
    @test occursin("Files extracted and checked:", summary_content)
    @test occursin("Files catalogued but not checked:", summary_content)
    @test occursin("large_data.csv", summary_content)
    
    # Verify classification files exist (clean paths)
    data_files_report = joinpath(out_dir, "data-files.md")
    @test isfile(data_files_report)
    
    # Check text file has clean path for extracted file
    data_content = read(data_files_report, String)
    @test occursin("small_data.csv", data_content)
    
    # Verify manifest CSV shows extraction status
    data_manifest_file = joinpath(out_dir, "data-files-manifest.csv")
    @test isfile(data_manifest_file)
    
    data_manifest = CSV.read(data_manifest_file, DataFrame)
    @test nrow(data_manifest) == 2  # Both files listed
    
    # Check both files are in manifest
    @test any(occursin("small_data.csv", row.filepath) for row in eachrow(data_manifest))
    @test any(occursin("large_data.csv", row.filepath) for row in eachrow(data_manifest))
    
    # Verify extraction/check status in manifest
    small_manifest_row = findfirst(row -> occursin("small_data.csv", row.filepath), eachrow(data_manifest))
    large_manifest_row = findfirst(row -> occursin("large_data.csv", row.filepath), eachrow(data_manifest))
    
    @test data_manifest[small_manifest_row, :extracted] == true
    @test data_manifest[small_manifest_row, :checked] == true
    @test data_manifest[large_manifest_row, :extracted] == false
    @test data_manifest[large_manifest_row, :checked] == false
    
    # Verify PII scanning only ran on extracted files
    pii_report = joinpath(out_dir, "report-pii.md")
    @test isfile(pii_report)
end

@testitem "selective extraction - directory" begin
    using DataFrames
    
    # Create test package directory with two data files
    function make_test_package_with_sizes(pkg_root)
        pkg_loc = joinpath(pkg_root, "replication-package")
        pkg_data = joinpath(pkg_loc, "data")
        mkpath(pkg_data)
        
        # Small file
        write(joinpath(pkg_data, "small.txt"), rand(UInt8, 500_000))  # 0.5 MB
        
        # Large file
        write(joinpath(pkg_data, "large.bin"), rand(UInt8, 3_000_000))  # 3 MB
        
        return pkg_loc
    end
    
    tmpdir = mktempdir()
    pkg_loc = make_test_package_with_sizes(tmpdir)
    
    # Both files should exist before filtering
    @test isfile(joinpath(pkg_loc, "data", "small.txt"))
    @test isfile(joinpath(pkg_loc, "data", "large.bin"))
    
    # Apply filtering to existing directory
    pkg_dir, manifest = PackageScanner.prepare_package_for_precheck(
        pkg_loc,
        size_threshold_gb=1.5/1024,  # ~1.5 MB
        interactive=false
    )
    
    # Should return same directory
    @test pkg_dir == pkg_loc
    
    # Manifest should have both files
    @test nrow(manifest) == 2
    
    # Both files still exist on disk (directory mode doesn't delete)
    @test isfile(joinpath(pkg_loc, "data", "small.txt"))
    @test isfile(joinpath(pkg_loc, "data", "large.bin"))
    
    # But checked status should differ
    small_row = findfirst(row -> occursin("small.txt", row.filepath), eachrow(manifest))
    large_row = findfirst(row -> occursin("large.bin", row.filepath), eachrow(manifest))
    
    @test manifest[small_row, :checked] == true
    @test manifest[large_row, :checked] == false
end

@testitem "manifest structure validation" begin
    using DataFrames
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "replication-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create test file
    write(joinpath(pkg_loc, "data", "test.csv"), "x,y\n1,2\n")
    
    # Create zip
    zip_path = joinpath(tmpdir, "test.zip")
    cd(tmpdir) do
        run(`zip -r $zip_path $(basename(pkg_loc))`)
    end
    
    # Get manifest
    pkg_dir, manifest = PackageScanner.prepare_package_for_precheck(
        zip_path,
        size_threshold_gb=10.0,  # Large threshold - extract everything
        interactive=false
    )
    
    # Verify required columns
    required_cols = ["filepath", "size_bytes", "size_gb", "extracted", "checked"]
    for col in required_cols
        @test col in names(manifest)
    end
    
    # Verify data types
    @test eltype(manifest.filepath) == String
    @test eltype(manifest.size_bytes) <: Integer
    @test eltype(manifest.size_gb) <: Real
    @test eltype(manifest.extracted) == Bool
    @test eltype(manifest.checked) == Bool
end

@testitem "threshold behavior - extract all" begin
    using DataFrames
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "replication-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create small files
    write(joinpath(pkg_loc, "data", "file1.txt"), "test1")
    write(joinpath(pkg_loc, "data", "file2.txt"), "test2")
    
    zip_path = joinpath(tmpdir, "test.zip")
    cd(tmpdir) do
        run(`zip -r $zip_path $(basename(pkg_loc))`)
    end
    rm(pkg_loc, recursive=true)
    
    # Very high threshold - should extract everything
    pkg_dir, manifest = PackageScanner.prepare_package_for_precheck(
        zip_path,
        size_threshold_gb=100.0,
        interactive=false
    )
    
    # All files should be extracted
    @test all(manifest.extracted)
    @test isfile(joinpath(pkg_dir, manifest[1, :filepath]))
    @test isfile(joinpath(pkg_dir, manifest[2, :filepath]))
end

@testitem "threshold behavior - extract none" begin
    using DataFrames
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "replication-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    write(joinpath(pkg_loc, "data", "file.txt"), "test")
    
    zip_path = joinpath(tmpdir, "test.zip")
    cd(tmpdir) do
        run(`zip -r $zip_path $(basename(pkg_loc))`)
    end
    rm(pkg_loc, recursive=true)
    
    # Very low threshold - should extract nothing
    pkg_dir, manifest = PackageScanner.prepare_package_for_precheck(
        zip_path,
        size_threshold_gb=0.0,
        interactive=false
    )
    
    # No files should be extracted
    @test all(.!manifest.extracted)
end

@testitem "create_manifest_from_zip - basic functionality" begin
    using DataFrames
    using ZipFile
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "replication-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create test files with known sizes
    write(joinpath(pkg_loc, "data", "small.txt"), "a" ^ 100)     # 100 bytes
    write(joinpath(pkg_loc, "data", "medium.txt"), "b" ^ 10000)  # 10 KB
    
    zip_path = joinpath(tmpdir, "test.zip")
    cd(tmpdir) do
        run(`zip -r $zip_path $(basename(pkg_loc))`)
    end
    
    # Extract with threshold between small and medium
    manifest, extract_dir = PackageScanner.create_manifest_from_zip(
        zip_path,
        size_threshold_gb=5/1024/1024,  # 5 KB in GB
        interactive=false
    )
    
    @test isa(manifest, DataFrame)
    @test nrow(manifest) == 2
    @test any(occursin("small.txt", row.filepath) for row in eachrow(manifest))
    @test any(occursin("medium.txt", row.filepath) for row in eachrow(manifest))
    
    # Small file should be extracted, medium should not
    small_row = findfirst(row -> occursin("small.txt", row.filepath), eachrow(manifest))
    medium_row = findfirst(row -> occursin("medium.txt", row.filepath), eachrow(manifest))
    
    @test manifest[small_row, :extracted] == true
    @test manifest[medium_row, :extracted] == false
end

@testitem "create_manifest_from_directory - basic functionality" begin
    using DataFrames
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "test_package")
    mkpath(joinpath(pkg_loc, "files"))
    
    # Create files
    write(joinpath(pkg_loc, "files", "tiny.txt"), "x" ^ 50)      # 50 bytes
    write(joinpath(pkg_loc, "files", "big.txt"), "y" ^ 100000)   # 100 KB
    
    manifest = PackageScanner.create_manifest_from_directory(
        pkg_loc,
        size_threshold_gb=50/1024/1024,  # 50 KB in GB
        interactive=false
    )
    
    @test isa(manifest, DataFrame)
    @test nrow(manifest) == 2
    
    # All files should be marked as extracted (they're already on disk)
    @test all(manifest.extracted)
    
    # But checked status should differ based on size
    tiny_row = findfirst(row -> occursin("tiny.txt", row.filepath), eachrow(manifest))
    big_row = findfirst(row -> occursin("big.txt", row.filepath), eachrow(manifest))
    
    @test manifest[tiny_row, :checked] == true
    @test manifest[big_row, :checked] == false
end
