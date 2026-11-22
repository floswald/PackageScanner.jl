@testitem "get_pdf_text extracts readable text from a PDF" begin
    using PackageScanner
    fixture = joinpath(@__DIR__, "data", "sample_readme.pdf")
    text = PackageScanner.get_pdf_text(fixture)

    @test occursin("Sample Replication Package README", text)
    @test occursin("confidential survey data", text)
    @test occursin("Random seed used: 12345", text)
end

@testitem "get_pdf_text errors on missing file" begin
    using PackageScanner
    @test_throws ErrorException PackageScanner.get_pdf_text(joinpath(@__DIR__, "data", "does_not_exist.pdf"))
end

@testitem "read_README finds keywords in a PDF README" begin
    using PackageScanner

    mktempdir() do pkg_dir
        fixture = joinpath(@__DIR__, "data", "sample_readme.pdf")
        readme_path = joinpath(pkg_dir, "README.pdf")
        cp(fixture, readme_path)

        fp = mktempdir()
        doclist = joinpath(fp, "documentation-files.txt")
        write(doclist, readme_path * "\n")

        PackageScanner.read_README(pkg_dir, fp)

        report = read(joinpath(fp, "report-readme.md"), String)
        @test occursin("confidential", report)
        @test occursin("seed", report)
    end
end
