@testitem "scan_code_file - basic detection" begin
    # Create a temporary code file with PII references
    test_file = joinpath(mktempdir(), "test_script.R")
    open(test_file, "w") do io
        println(io, "# Analysis script")
        println(io, "data <- read.csv('file.csv')")
        println(io, "df\$first_name <- clean_text(df\$name)")
        println(io, "model <- lm(y ~ age + email + income)")
        println(io, "summary(model)")
    end
    
    matches = PIIScanner.scan_code_file(test_file)
    
    @test !isempty(matches)
    @test any(m -> "name" in m.matched_terms, matches)
    @test any(m -> "email" in m.matched_terms, matches)
end

@testitem "scan_code_file - filters false positives" begin
    test_file = joinpath(mktempdir(), "test_imports.py")
    open(test_file, "w") do io
        println(io, "import pandas as pd")
        println(io, "from collections import defaultdict")
        println(io, "def process_name(x):")
        println(io, "    return x.strip()")
        println(io, "# This should be detected")
        println(io, "df['user_email'] = clean(df['email'])")
    end
    
    matches = PIIScanner.scan_code_file(test_file)
    
    # Should not flag imports and function definitions
    @test !any(m -> occursin("import", m.sample_values[1]), matches)
    @test !any(m -> occursin("def process_name", m.sample_values[1]), matches)
    
    # Should flag the real reference
    @test any(m -> "email" in m.matched_terms, matches)
end

@testitem "scan_code_file - strict vs non-strict" begin
    test_file = joinpath(mktempdir(), "test_strict.R")
    open(test_file, "w") do io
        println(io, "filename <- 'data.csv'")  # Contains 'name' but not as whole word
        println(io, "first_name <- 'John'")     # Contains 'name' as whole word
    end
    
    # Non-strict: should match both
    matches_nonstrict = PIIScanner.scan_code_file(test_file, strict=false)
    @test length(matches_nonstrict) >= 2
    
    # Strict: should only match second line
    matches_strict = PIIScanner.scan_code_file(test_file, strict=true)
    @test length(matches_strict) >= 1
    @test any(m -> occursin("first_name", m.sample_values[1]), matches_strict)
end

@testitem "scan_code_file - custom terms" begin
    test_file = joinpath(mktempdir(), "test_custom.jl")
    open(test_file, "w") do io
        println(io, "df.patient_id = 12345")
        println(io, "df.study_id = 'ABC'")
    end
    
    matches = PIIScanner.scan_code_file(test_file, custom_terms=["patient_id", "study_id"])
    
    @test !isempty(matches)
    @test any(m -> "patient_id" in m.matched_terms, matches)
    @test any(m -> "study_id" in m.matched_terms, matches)
end

@testitem "scan_code_file - empty file" begin
    test_file = joinpath(mktempdir(), "empty.R")
    touch(test_file)
    
    matches = PIIScanner.scan_code_file(test_file)
    @test isempty(matches)
end

@testitem "scan_code_file - nonexistent file" begin
    # Should warn and return empty, not error
    matches = PIIScanner.scan_code_file("/nonexistent/file.R")
    @test isempty(matches)
end

@testitem "scan_code_files - batch processing" begin
    tmpdir = mktempdir()
    
    # Create multiple test files
    file1 = joinpath(tmpdir, "script1.R")
    open(file1, "w") do io
        println(io, "df\$name <- 'test'")
    end
    
    file2 = joinpath(tmpdir, "script2.py")
    open(file2, "w") do io
        println(io, "email = get_email()")
    end
    
    file3 = joinpath(tmpdir, "clean.jl")
    open(file3, "w") do io
        println(io, "x = 5")  # No PII
    end
    
    # Redirect stdout to suppress progress output
    matches = redirect_stdout(devnull) do
        PIIScanner.scan_code_files([file1, file2, file3])
    end
    
    @test !isempty(matches)
    @test any(m -> m.filepath == file1, matches)
    @test any(m -> m.filepath == file2, matches)
    @test !any(m -> m.filepath == file3, matches)
end
