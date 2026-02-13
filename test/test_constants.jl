@testitem "Default PII terms exist" begin
    @test !isempty(PackageScanner.DEFAULT_PII_TERMS)
    @test "name" in PackageScanner.DEFAULT_PII_TERMS
    @test "email" in PackageScanner.DEFAULT_PII_TERMS
    @test "phone" in PackageScanner.DEFAULT_PII_TERMS
    @test "address" in PackageScanner.DEFAULT_PII_TERMS
end

@testitem "Default PII terms are lowercase" begin
    @test all(term -> term == lowercase(term), PackageScanner.DEFAULT_PII_TERMS)
end

@testitem "False positive patterns exist" begin
    @test !isempty(PackageScanner.FALSE_POSITIVE_PATTERNS)
    # Test that at least one pattern matches the import statement
    @test any(pattern -> match(pattern, "import pandas") !== nothing, PackageScanner.FALSE_POSITIVE_PATTERNS)
end
