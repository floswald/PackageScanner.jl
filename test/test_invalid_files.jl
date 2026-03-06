@testitem "invalid files - broken symlink detection in directory" begin
    using DataFrames
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "test-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create a valid file
    valid_file = joinpath(pkg_loc, "data", "valid.csv")
    write(valid_file, "x,y\n1,2\n")
    @test isfile(valid_file)
    
    # Create a broken symlink (only works on Unix systems)
    if !Sys.iswindows()
        broken_link = joinpath(pkg_loc, "data", "broken_link.csv")
        nonexistent = joinpath(tmpdir, "nonexistent.csv")
        symlink(nonexistent, broken_link)
        @test !isfile(broken_link)  # symlink exists but points to nothing
        
        # Create manifest from directory
        manifest = PackageScanner.create_manifest_from_directory(
            pkg_loc,
            size_threshold_gb=10.0,
            interactive=false
        )
        
        # Verify is_valid_file column exists
        @test "is_valid_file" in names(manifest)
        
        # Verify broken link is marked as invalid
        broken_row = findfirst(row -> occursin("broken_link", row.filepath), eachrow(manifest))
        valid_row = findfirst(row -> occursin("valid.csv", row.filepath), eachrow(manifest))
        
        @test !isnothing(broken_row)
        @test !isnothing(valid_row)
        
        @test manifest[broken_row, :is_valid_file] == false
        @test manifest[valid_row, :is_valid_file] == true
    else
        @test_skip "Symlink test skipped on Windows"
    end
end

@testitem "invalid files - report generation" begin
    using DataFrames
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "test-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create valid file
    write(joinpath(pkg_loc, "data", "good.csv"), "data")
    
    # Create broken symlink (Unix only)
    if !Sys.iswindows()
        symlink(joinpath(tmpdir, "missing.csv"), joinpath(pkg_loc, "data", "bad_link.csv"))
        
        # Generate manifest
        manifest = PackageScanner.create_manifest_from_directory(
            pkg_loc,
            size_threshold_gb=10.0,
            interactive=false
        )
        
        # Generate report
        out_dir = joinpath(tmpdir, "reports")
        mkpath(out_dir)
        PackageScanner.write_illegal_files_report(manifest, out_dir)
        
        # Verify report exists
        report_path = joinpath(out_dir, "report-illegal-files.md")
        @test isfile(report_path)
        
        # Verify report content
        content = read(report_path, String)
        @test occursin("Invalid/Illegal Files Report", content)
        @test occursin("bad_link.csv", content)
        @test occursin("broken", lowercase(content)) || occursin("invalid", lowercase(content))
    else
        @test_skip "Symlink test skipped on Windows"
    end
end

@testitem "invalid files - scan_code_file graceful handling" begin
    using DataFrames
    
    tmpdir = mktempdir()
    
    # Create valid code file
    valid_code = joinpath(tmpdir, "analysis.R")
    write(valid_code, "data <- read.csv('file.csv')\nname_column <- data\$first_name")
    
    # Scan valid file - should work
    matches_valid = PackageScanner.scan_code_file(valid_code)
    @test !isempty(matches_valid)  # Should find "first_name"
    
    # Test with broken symlink (Unix only)
    if !Sys.iswindows()
        broken_code = joinpath(tmpdir, "broken.R")
        symlink(joinpath(tmpdir, "nonexistent.R"), broken_code)
        
        # Scan broken link - should return empty without crashing
        matches_broken = PackageScanner.scan_code_file(broken_code)
        @test isempty(matches_broken)
        @test length(matches_broken) == 0
    else
        @test_skip "Symlink test skipped on Windows"
    end
end

@testitem "invalid files - check_file_paths graceful handling" begin
    
    tmpdir = mktempdir()
    
    # Create valid file with paths
    valid_file = joinpath(tmpdir, "script.sh")
    write(valid_file, "#!/bin/bash\ncp /path/to/source /path/to/dest\n")
    
    # Check valid file
    lines_valid, classification, has_drive, hardcodes = PackageScanner.check_file_paths(valid_file)
    @test classification == "unix"
    @test !isempty(lines_valid)
    
    # Test with broken symlink (Unix only)
    if !Sys.iswindows()
        broken_file = joinpath(tmpdir, "broken_script.sh")
        symlink(joinpath(tmpdir, "missing.sh"), broken_file)
        
        # Check broken link
        lines_broken, classification, has_drive, hardcodes = PackageScanner.check_file_paths(broken_file)
        @test any(occursin("not accessible", line) || occursin("broken symlink", line) for line in lines_broken)
    else
        @test_skip "Symlink test skipped on Windows"
    end
end

@testitem "invalid files - full precheck integration" begin
    using DataFrames
    using CSV
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "replication-package")
    mkpath(joinpath(pkg_loc, "data"))
    mkpath(joinpath(pkg_loc, "code"))
    
    # Create valid files
    write(joinpath(pkg_loc, "README.md"), "# Test Package")
    write(joinpath(pkg_loc, "data", "valid.csv"), "id,name\n1,Alice\n")
    write(joinpath(pkg_loc, "code", "analysis.R"), "data <- read.csv('valid.csv')")
    
    # Create broken symlinks (Unix only)
    if !Sys.iswindows()
        symlink(joinpath(tmpdir, "missing1.csv"), joinpath(pkg_loc, "data", "broken1.csv"))
        symlink(joinpath(tmpdir, "missing2.R"), joinpath(pkg_loc, "code", "broken2.R"))
        
        # Generate manifest
        manifest = PackageScanner.create_manifest_from_directory(
            pkg_loc,
            size_threshold_gb=10.0,
            interactive=false
        )
        
        # Verify invalid files are marked
        @test any(row -> occursin("broken1.csv", row.filepath) && row.is_valid_file == false, eachrow(manifest))
        @test any(row -> occursin("broken2.R", row.filepath) && row.is_valid_file == false, eachrow(manifest))
        
        # Run full precheck
        out_dir = joinpath(dirname(pkg_loc), "generated")
        redirect_stdout(devnull) do
            PackageScanner.precheck_package(pkg_loc, pre_manifest=manifest)
        end
        
        # Verify illegal files report was generated
        illegal_report = joinpath(out_dir, "report-illegal-files.md")
        @test isfile(illegal_report)
        
        # Verify it lists both broken symlinks
        content = read(illegal_report, String)
        @test occursin("broken1.csv", content)
        @test occursin("broken2.R", content)
        @test occursin("invalid", lowercase(content)) || occursin("broken", lowercase(content))
        
        # Verify other reports still generated correctly
        @test isfile(joinpath(out_dir, "report-file-sizes.md"))
        @test isfile(joinpath(out_dir, "report-readme.md"))
    else
        @test_skip "Symlink test skipped on Windows"
    end
end

@testitem "invalid files - zip extraction validates files" begin
    using DataFrames
    using ZipFile
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "replication-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create valid file
    write(joinpath(pkg_loc, "data", "test.csv"), "x,y\n1,2\n")
    
    # Create zip
    zip_path = joinpath(tmpdir, "test.zip")
    cd(tmpdir) do
        run(`zip -r $zip_path $(basename(pkg_loc))`)
    end
    
    # Extract with manifest
    manifest, extract_dir = PackageScanner.create_manifest_from_zip(
        zip_path,
        size_threshold_gb=10.0,
        interactive=false
    )
    
    # Verify is_valid_file column exists
    @test "is_valid_file" in names(manifest)
    
    # All extracted files should be valid (normal zip extraction)
    extracted_files = manifest[manifest.extracted, :]
    for row in eachrow(extracted_files)
        # Should be true, not missing
        @test row.is_valid_file === true
    end
end

@testitem "invalid files - report with all valid files" begin
    using DataFrames
    
    tmpdir = mktempdir()
    pkg_loc = joinpath(tmpdir, "test-package")
    mkpath(joinpath(pkg_loc, "data"))
    
    # Create only valid files
    write(joinpath(pkg_loc, "data", "file1.csv"), "test")
    write(joinpath(pkg_loc, "data", "file2.csv"), "test")
    
    # Generate manifest
    manifest = PackageScanner.create_manifest_from_directory(
        pkg_loc,
        size_threshold_gb=10.0,
        interactive=false
    )
    
    # All should be valid
    @test all(manifest.is_valid_file)
    
    # Generate report
    out_dir = joinpath(tmpdir, "reports")
    mkpath(out_dir)
    PackageScanner.write_illegal_files_report(manifest, out_dir)
    
    # Verify report shows no issues
    report_path = joinpath(out_dir, "report-illegal-files.md")
    @test isfile(report_path)
    
    content = read(report_path, String)
    @test occursin("✅", content) || occursin("All files are valid", content)
    @test occursin("No broken symlinks", content)
end

@testitem "invalid files - manifest without is_valid_file column" begin
    using DataFrames
    
    # Create manifest without is_valid_file column (backward compatibility)
    manifest = DataFrame(
        filepath = ["file1.csv", "file2.csv"],
        size_bytes = [100, 200],
        extracted = [true, true]
    )
    
    tmpdir = mktempdir()
    
    # Should handle gracefully
    PackageScanner.write_illegal_files_report(manifest, tmpdir)
    
    # Report should not be created (or contain warning)
    # This tests backward compatibility
    @test true  # Should not error
end
