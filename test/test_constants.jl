@testitem "Default PII terms exist" begin
    @test !isempty(PIIScanner.DEFAULT_PII_TERMS)
    @test "name" in PIIScanner.DEFAULT_PII_TERMS
    @test "email" in PIIScanner.DEFAULT_PII_TERMS
    @test "phone" in PIIScanner.DEFAULT_PII_TERMS
    @test "address" in PIIScanner.DEFAULT_PII_TERMS
end

@testitem "Default PII terms are lowercase" begin
    @test all(term -> term == lowercase(term), PIIScanner.DEFAULT_PII_TERMS)
end

@testitem "False positive patterns exist" begin
    @test !isempty(PIIScanner.FALSE_POSITIVE_PATTERNS)
    # Test that at least one pattern matches the import statement
    @test any(pattern -> match(pattern, "import pandas") !== nothing, PIIScanner.FALSE_POSITIVE_PATTERNS)
end
