@testitem "End-to-end workflow" begin
    
    tmpdir = mktempdir()
    
    # Create test data file
    data_file = joinpath(tmpdir, "survey.csv")
    open(data_file, "w") do io
        println(io, "respondent_id,first_name,age,city")
        println(io, "1,John,30,NYC")
        println(io, "2,Jane,25,LA")
    end
    
    # Create test code file
    code_file = joinpath(tmpdir, "analysis.R")
    open(code_file, "w") do io
        println(io, "data <- read.csv('survey.csv')")
        println(io, "model <- lm(age ~ first_name)")
    end
    
    # Run full workflow
    data_results = redirect_stdout(devnull) do
        PIIScanner.scan_data_files([data_file])
    end
    
    code_results = redirect_stdout(devnull) do
        PIIScanner.scan_code_files([code_file])
    end
    
    @test !isempty(data_results)
    @test !isempty(code_results)
    
    # Generate reports
    output_dir = joinpath(tmpdir, "output")
    mkpath(output_dir)
    
    redirect_stdout(devnull) do
        PIIScanner.write_pii_report(data_results, code_results, output_dir)
    end
    
    @test isfile(joinpath(output_dir, "report-pii.md"))
    @test isfile(joinpath(output_dir, "report-pii-appendix.md"))
end

@testitem "Workflow with custom PII terms" begin
    
    tmpdir = mktempdir()
    
    # Create test data file with custom PII
    data_file = joinpath(tmpdir, "medical.csv")
    open(data_file, "w") do io
        println(io, "patient_id,diagnosis,treatment_plan")
        println(io, "P001,flu,rest")
    end
    
    # Scan with custom terms
    data_results = redirect_stdout(devnull) do
        PIIScanner.scan_data_files([data_file], custom_terms=["patient_id", "diagnosis", "treatment_plan"])
    end
    
    @test !isempty(data_results)
    @test any(m -> "patient_id" in m.matched_terms, data_results)
    @test any(m -> "diagnosis" in m.matched_terms, data_results)
end

@testitem "Workflow with strict matching" begin
    
    tmpdir = mktempdir()
    
    data_file = joinpath(tmpdir, "data.csv")
    open(data_file, "w") do io
        println(io, "filename,name")  # 'filename' contains 'name'
        println(io, "data.csv,John")
    end
    
    # Non-strict should flag both
    matches_nonstrict = redirect_stdout(devnull) do
        PIIScanner.scan_data_files([data_file], strict=false)
    end
    @test any(m -> m.variable_name == "filename", matches_nonstrict)
    
    # Strict should only flag 'name'
    matches_strict = redirect_stdout(devnull) do
        PIIScanner.scan_data_files([data_file], strict=true)
    end
    @test !any(m -> m.variable_name == "filename", matches_strict)
    @test any(m -> m.variable_name == "name", matches_strict)
end
