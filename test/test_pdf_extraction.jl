@testitem "extract_pdf_text: returns extract_latex_text-compatible shape" begin
    using PackageScanner
    fixture = joinpath(@__DIR__, "data", "sample_readme.pdf")

    result = PackageScanner.extract_pdf_text(fixture)

    @test result.roots == [fixture]
    @test result.ambiguous == false
    @test isempty(result.unresolved)
    @test occursin("confidential survey data", result.text)
end

@testitem "extract_pdf_text: errors on missing file" begin
    using PackageScanner
    @test_throws ErrorException PackageScanner.extract_pdf_text(joinpath(@__DIR__, "data", "does_not_exist.pdf"))
end
