@testitem "load_data_metadata - CSV file" tags=[:skipci] begin
    # Ensure rio is installed
    
    tmpdir = mktempdir()
    csv_file = joinpath(tmpdir, "test.csv")
    
    # Create a test CSV
    open(csv_file, "w") do io
        println(io, "name,age,email")
        println(io, "John,30,john@example.com")
        println(io, "Jane,25,jane@example.com")
    end
    
    metadata = PIIScanner.load_data_metadata(csv_file)
    
    @test !isnothing(metadata)
    @test "name" in metadata["var_names"]
    @test "age" in metadata["var_names"]
    @test "email" in metadata["var_names"]
    @test !isempty(metadata["samples"])
end

@testitem "load_data_metadata - nonexistent file" tags=[:skipci] begin
    metadata = PIIScanner.load_data_metadata("/nonexistent/file.csv")
    @test isnothing(metadata)
end

@testitem "scan_data_file - CSV with PII variables" tags=[:skipci] begin
    
    tmpdir = mktempdir()
    csv_file = joinpath(tmpdir, "survey.csv")
    
    open(csv_file, "w") do io
        println(io, "respondent_id,first_name,last_name,birth_date,email_address")
        println(io, "1,John,Doe,1990-01-01,john@example.com")
        println(io, "2,Jane,Smith,1985-05-15,jane@example.com")
    end
    
    matches = PIIScanner.scan_data_file(csv_file)
    
    @test !isempty(matches)
    @test any(m -> m.variable_name == "first_name", matches)
    @test any(m -> m.variable_name == "last_name", matches)
    @test any(m -> "email" in m.matched_terms, matches)
    @test any(m -> "birth" in m.matched_terms, matches)
end

@testitem "scan_data_file - strict mode" tags=[:skipci] begin
    
    tmpdir = mktempdir()
    csv_file = joinpath(tmpdir, "data.csv")
    
    open(csv_file, "w") do io
        println(io, "filename,name,latitude")  # 'filename' has 'name', 'latitude' has 'lat'
        println(io, "data.csv,John,45.5")
    end
    
    # Non-strict: should match 'filename' and 'latitude'
    matches_nonstrict = PIIScanner.scan_data_file(csv_file, strict=false)
    @test any(m -> m.variable_name == "filename", matches_nonstrict)
    
    # Strict: should NOT match 'filename' or 'latitude'
    matches_strict = PIIScanner.scan_data_file(csv_file, strict=true)
    @test !any(m -> m.variable_name == "filename", matches_strict)
    @test any(m -> m.variable_name == "name", matches_strict)
end

@testitem "scan_data_file - custom terms" tags=[:skipci] begin
    
    tmpdir = mktempdir()
    csv_file = joinpath(tmpdir, "medical.csv")
    
    open(csv_file, "w") do io
        println(io, "patient_id,diagnosis,treatment")
        println(io, "P001,flu,rest")
    end
    
    matches = PIIScanner.scan_data_file(csv_file, custom_terms=["patient_id", "diagnosis"])
    
    @test any(m -> "patient_id" in m.matched_terms, matches)
    @test any(m -> "diagnosis" in m.matched_terms, matches)
end

@testitem "scan_data_file - sample values extracted" tags=[:skipci] begin
    
    tmpdir = mktempdir()
    csv_file = joinpath(tmpdir, "data.csv")
    
    open(csv_file, "w") do io
        println(io, "name,value")
        println(io, "Alice,100")
        println(io, "Bob,200")
        println(io, "Charlie,300")
    end
    
    matches = PIIScanner.scan_data_file(csv_file)
    
    name_match = findfirst(m -> m.variable_name == "name", matches)
    @test !isnothing(name_match)
    @test !isempty(matches[name_match].sample_values)
    @test "Alice" in matches[name_match].sample_values || "Bob" in matches[name_match].sample_values
end

@testitem "scan_data_files - batch processing" tags=[:skipci] begin
    
    tmpdir = mktempdir()
    
    # File with PII
    file1 = joinpath(tmpdir, "survey.csv")
    open(file1, "w") do io
        println(io, "name,age")
        println(io, "John,30")
    end
    
    # File without PII
    file2 = joinpath(tmpdir, "counts.csv")
    open(file2, "w") do io
        println(io, "category,count")
        println(io, "A,10")
    end
    
    matches = redirect_stdout(devnull) do
        PIIScanner.scan_data_files([file1, file2])
    end
    
    @test !isempty(matches)
    @test any(m -> m.filepath == file1, matches)
    @test !any(m -> m.filepath == file2, matches)
end


@testitem "load data with rio" begin
    tmpdir = mktempdir()
    csv_file = joinpath(tmpdir, "data.csv")
    
    open(csv_file, "w") do io
        println(io, "name,value")
        println(io, "Alice,100")
        println(io, "Bob,200")
        println(io, "Charlie,300")
    end
    
end