@testitem "generate_summary_table - empty results" begin
    table = PIIScanner.generate_summary_table(PIIScanner.PIIMatch[], PIIScanner.PIIMatch[])
    
    @test occursin("| File Type | File | Variables/References | PII Categories |", table)
    @test occursin("|-----------|------|", table)
end

@testitem "generate_summary_table - with data results" begin
    matches = [
        PIIScanner.PIIMatch("data/file1.dta", "name", nothing, ["name"], ["John"]),
        PIIScanner.PIIMatch("data/file1.dta", "email", nothing, ["email"], ["john@example.com"]),
        PIIScanner.PIIMatch("data/file2.csv", "phone", nothing, ["phone"], ["555-1234"]),
    ]
    
    table = PIIScanner.generate_summary_table(matches, PIIScanner.PIIMatch[])
    
    @test occursin("| Data |", table)
    @test occursin("file1.dta", table)
    @test occursin("file2.csv", table)
    @test occursin("name, email", table) || occursin("email, name", table)
end

@testitem "generate_summary_table - with code results" begin
    code_matches = [
        PIIScanner.PIIMatch("src/script.R", "Line 5", nothing, ["name", "email"], ["df\$name <- x"]),
    ]
    
    table = PIIScanner.generate_summary_table(PIIScanner.PIIMatch[], code_matches)
    
    @test occursin("| Code |", table)
    @test occursin("script.R", table)
end

@testitem "generate_detailed_appendix - empty results" begin
    appendix = PIIScanner.generate_detailed_appendix(PIIScanner.PIIMatch[], PIIScanner.PIIMatch[])
    
    @test appendix == ""
end

@testitem "generate_detailed_appendix - with data" begin
    matches = [
        PIIScanner.PIIMatch(
            "data/survey.dta",
            "first_name",
            "First Name",
            ["name", "first_name"],
            ["John", "Jane"]
        ),
    ]
    
    appendix = PIIScanner.generate_detailed_appendix(matches, PIIScanner.PIIMatch[])
    
    @test occursin("### Data Files", appendix)
    @test occursin("survey.dta", appendix)
    @test occursin("first_name", appendix)
    @test occursin("First Name", appendix)
    @test occursin("name, first_name", appendix) || occursin("first_name, name", appendix)
    @test occursin("John", appendix)
end

@testitem "generate_detailed_appendix - path splitting" begin
    matches = [
        PIIScanner.PIIMatch(
            "/home/user/project/data/survey.dta",
            "name",
            nothing,
            ["name"],
            ["John"]
        ),
    ]
    
    appendix = PIIScanner.generate_detailed_appendix(matches, PIIScanner.PIIMatch[], splitat="/project/")
    
    @test occursin("data/survey.dta", appendix)
    @test !occursin("/home/user/project/", appendix)
end

@testitem "write_pii_report - no PII found" begin
    tmpdir = mktempdir()
    
    redirect_stdout(devnull) do
        PIIScanner.write_pii_report(
            PIIScanner.PIIMatch[],
            PIIScanner.PIIMatch[],
            tmpdir
        )
    end
    
    report_path = joinpath(tmpdir, "report-pii.md")
    @test isfile(report_path)
    
    content = read(report_path, String)
    @test occursin("✅ No PII found", content)
    @test !isfile(joinpath(tmpdir, "report-pii-appendix.md"))
end

@testitem "write_pii_report - with PII detected" begin
    tmpdir = mktempdir()
    
    data_matches = [
        PIIScanner.PIIMatch("data/file.dta", "name", nothing, ["name"], ["John"]),
    ]
    
    code_matches = [
        PIIScanner.PIIMatch("src/script.R", "Line 1", nothing, ["email"], ["df\$email"]),
    ]
    
    redirect_stdout(devnull) do
        PIIScanner.write_pii_report(data_matches, code_matches, tmpdir)
    end
    
    # Check main report
    report_path = joinpath(tmpdir, "report-pii.md")
    @test isfile(report_path)
    
    content = read(report_path, String)
    @test occursin("⚠️", content)
    @test occursin("GDPR", content)
    @test occursin("Summary:", content)
    @test occursin("Data files with PII indicators: 1", content)
    
    # Check appendix
    appendix_path = joinpath(tmpdir, "report-pii-appendix.md")
    @test isfile(appendix_path)
    
    appendix_content = read(appendix_path, String)
    @test occursin("Appendix: Detailed PII Detection Results", appendix_content)
end

@testitem "write_pii_report_simple - format matches original" begin
    tmpdir = mktempdir()
    
    matches = [
        PIIScanner.PIIMatch(
            "/home/user/project/data/survey.dta",
            "first_name",
            "First Name",
            ["name"],
            ["John", "Jane"]
        ),
    ]
    
    redirect_stdout(devnull) do
        PIIScanner.write_pii_report_simple(matches, PIIScanner.PIIMatch[], tmpdir, splitat="/project/")
    end
    
    report_path = joinpath(tmpdir, "report-pii.md")
    @test isfile(report_path)
    
    content = read(report_path, String)
    @test occursin("**data/survey.dta**", content)
    @test occursin("- Variable `first_name`", content)
    @test occursin("samples: John, Jane", content)
end
