@testitem "readme_section_checklist - all sections present" begin
    using PackageScanner
    text = """
    # My Package

    ## Data Availability
    Data comes from the Census.

    ## Software Requirements
    Requires R 4.3 and the haven package.

    ## Instructions to Reproduce
    Run main.R.

    ## Computational requirements
    Runs in under 1 hour on a laptop.

    ## License
    MIT.
    """
    checklist = PackageScanner.readme_section_checklist(text)
    @test length(checklist) == 5
    @test all(!isnothing(line) for (_, line) in checklist)
end

@testitem "readme_section_checklist - all sections missing" begin
    using PackageScanner
    text = "# My Package\n\nJust some code, nothing else.\n"
    checklist = PackageScanner.readme_section_checklist(text)
    @test all(isnothing(line) for (_, line) in checklist)
end

@testitem "readme_data_citations - mentioned with full citation" begin
    using PackageScanner
    text = """
    # README

    We use survey.dta, obtained from https://example.org/survey, accessed 2023-04-01.
    """
    citations = PackageScanner.readme_data_citations(text, ["path/survey.dta"])
    @test length(citations) == 1
    c = citations[1]
    @test c.mentioned
    @test c.has_url_or_doi
    @test c.has_access_date
end

@testitem "readme_data_citations - mentioned but missing citation metadata" begin
    using PackageScanner
    text = "# README\n\nWe use survey.dta in our analysis.\n"
    citations = PackageScanner.readme_data_citations(text, ["path/survey.dta"])
    c = citations[1]
    @test c.mentioned
    @test !c.has_url_or_doi
    @test !c.has_access_date
end

@testitem "readme_data_citations - not mentioned at all" begin
    using PackageScanner
    text = "# README\n\nNothing about data here.\n"
    citations = PackageScanner.readme_data_citations(text, ["path/orphan_dataset.csv"])
    c = citations[1]
    @test !c.mentioned
    @test !c.has_url_or_doi
    @test !c.has_access_date
end

@testitem "readme_structure_audit - end to end" begin
    using PackageScanner

    mktempdir() do root
        pkg = joinpath(root, "replication-package")
        mkpath(pkg)

        readme = joinpath(pkg, "README.md")
        write(readme, """
        # My Package

        ## Data Availability
        Data from survey.dta, see https://example.org, accessed 2023.

        ## License
        MIT.
        """)

        datafile1 = joinpath(pkg, "survey.dta")
        datafile2 = joinpath(pkg, "orphan_dataset.csv")
        write(datafile1, "x")
        write(datafile2, "x")

        out = joinpath(root, "generated")
        mkpath(out)
        write(joinpath(out, "documentation-files.txt"), readme * "\n")

        PackageScanner.readme_structure_audit(pkg, [datafile1, datafile2], out)

        report = read(joinpath(out, "report-readme-structure.md"), String)
        @test occursin("✅ Data availability", report)
        @test occursin("❌ Software requirements", report)
        @test occursin("survey.dta", report)
        @test occursin("orphan_dataset.csv", report)
        @test occursin("not mentioned in README", report)
    end
end

@testitem "readme_structure_audit - no markdown README found" begin
    using PackageScanner

    mktempdir() do root
        out = joinpath(root, "generated")
        mkpath(out)
        write(joinpath(out, "documentation-files.txt"), joinpath(root, "README.pdf") * "\n")

        PackageScanner.readme_structure_audit(root, String[], out)

        report = read(joinpath(out, "report-readme-structure.md"), String)
        @test occursin("No markdown `README` found", report)
    end
end
