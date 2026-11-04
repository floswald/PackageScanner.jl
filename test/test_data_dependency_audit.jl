@testitem "token_occurs - whole-word matches only" begin
    using PackageScanner
    @test PackageScanner.token_occurs("survey.dta", "data = read_dta(\"survey.dta\")")
    @test PackageScanner.token_occurs("survey", "x <- haven::read_dta(\"data/survey.dta\")")
    # must not match "survey" inside "mysurvey2.dta"
    @test !PackageScanner.token_occurs("survey", "read.csv(\"mysurvey2.dta\")")
    # must not match when absent entirely
    @test !PackageScanner.token_occurs("survey.dta", "import pandas as pd")
end

@testitem "data_file_tokens - short stems dropped, basename always kept" begin
    using PackageScanner
    @test PackageScanner.data_file_tokens("path/to/survey.dta") == ["survey.dta", "survey"]
    # stem "ab" has length 2 < default min_stem_length=3, so only basename kept
    @test PackageScanner.data_file_tokens("path/to/ab.csv") == ["ab.csv"]
    @test PackageScanner.data_file_tokens("path/to/ab.csv"; min_stem_length = 2) == ["ab.csv", "ab"]
end

@testitem "data_dependency_audit - matches, orphan, and report content" begin
    using PackageScanner

    mktempdir() do root
        pkg = joinpath(root, "replication-package")
        mkpath(pkg)

        data1 = joinpath(pkg, "survey.dta")
        data2 = joinpath(pkg, "orphan_dataset.csv")
        write(data1, "fake stata bytes")
        write(data2, "a,b\n1,2\n")

        code1 = joinpath(pkg, "analysis.R")
        write(code1, "df <- haven::read_dta(\"survey.dta\")\n")
        code2 = joinpath(pkg, "helper.py")
        write(code2, "print('no data loading here')\n")

        out = joinpath(root, "generated")
        mkpath(out)

        refs = PackageScanner.data_dependency_audit([data1, data2], [code1, code2], out)

        @test refs[data1] == [code1]
        @test refs[data2] == []

        report = read(joinpath(out, "report-data-dependencies.md"), String)
        @test occursin("| 2 | 1 | 1 |", report)
        @test occursin("ORPHAN", report)
        @test occursin("analysis.R", report)
    end
end

@testitem "data_dependency_audit - errors if output dir missing" begin
    using PackageScanner
    @test_throws ErrorException PackageScanner.data_dependency_audit(String[], String[], "/no/such/dir")
end
