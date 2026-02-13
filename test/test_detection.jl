@testitem "find_pii_terms - basic matching" begin
    # Should match
    @test "name" in PackageScanner.find_pii_terms("first_name", PackageScanner.DEFAULT_PII_TERMS)
    @test "email" in PackageScanner.find_pii_terms("user_email", PackageScanner.DEFAULT_PII_TERMS)
    @test "phone" in PackageScanner.find_pii_terms("contact_phone", PackageScanner.DEFAULT_PII_TERMS)
    
    # Should not match
    @test isempty(PackageScanner.find_pii_terms("randomvar", PackageScanner.DEFAULT_PII_TERMS))
    @test isempty(PackageScanner.find_pii_terms("count", PackageScanner.DEFAULT_PII_TERMS))
    @test isempty(PackageScanner.find_pii_terms("x123", PackageScanner.DEFAULT_PII_TERMS))
end

@testitem "find_pii_terms - case insensitive" begin
    @test "name" in PackageScanner.find_pii_terms("FIRST_NAME", PackageScanner.DEFAULT_PII_TERMS)
    @test "email" in PackageScanner.find_pii_terms("Email_Address", PackageScanner.DEFAULT_PII_TERMS)
    @test "phone" in PackageScanner.find_pii_terms("PhoneNumber", PackageScanner.DEFAULT_PII_TERMS)
end

@testitem "find_pii_terms - strict mode word boundaries" begin
    # Strict mode: should match whole words only
    @test "name" in PackageScanner.find_pii_terms("name", PackageScanner.DEFAULT_PII_TERMS, strict=true)
    @test "name" in PackageScanner.find_pii_terms("first_name", PackageScanner.DEFAULT_PII_TERMS, strict=true)
    
    # Strict mode: should NOT match partial words
    @test isempty(PackageScanner.find_pii_terms("filename", PackageScanner.DEFAULT_PII_TERMS, strict=true))
    @test isempty(PackageScanner.find_pii_terms("rename", PackageScanner.DEFAULT_PII_TERMS, strict=true))
    @test isempty(PackageScanner.find_pii_terms("latitude", PackageScanner.DEFAULT_PII_TERMS, strict=true))
end

@testitem "find_pii_terms - non-strict mode" begin
    # Non-strict: should match substrings
    @test "name" in PackageScanner.find_pii_terms("filename", PackageScanner.DEFAULT_PII_TERMS, strict=false)
    @test "lat" in PackageScanner.find_pii_terms("latitude", PackageScanner.DEFAULT_PII_TERMS, strict=false)
end

@testitem "find_pii_terms - multiple matches" begin
    matches = PackageScanner.find_pii_terms("person_name_email_address", PackageScanner.DEFAULT_PII_TERMS)
    @test "name" in matches
    @test "email" in matches
    @test "address" in matches
    @test length(matches) >= 3
end

@testitem "is_false_positive_context - imports" begin
    @test PackageScanner.is_false_positive_context("import pandas as pd")
    @test PackageScanner.is_false_positive_context("from datetime import datetime")
    @test PackageScanner.is_false_positive_context("require(dplyr)")
    @test PackageScanner.is_false_positive_context("library(tidyverse)")
    @test PackageScanner.is_false_positive_context("using DataFrames")
    @test PackageScanner.is_false_positive_context("#include <stdio.h>")
end

@testitem "is_false_positive_context - function definitions" begin
    @test PackageScanner.is_false_positive_context("function process_name(x)")
    @test PackageScanner.is_false_positive_context("def get_email():")
    @test PackageScanner.is_false_positive_context("sub check_phone {")
    @test PackageScanner.is_false_positive_context("class Person {")
    @test PackageScanner.is_false_positive_context("struct UserData {")
end

@testitem "is_false_positive_context - decorators" begin
    @test PackageScanner.is_false_positive_context("@property")
    @test PackageScanner.is_false_positive_context("@staticmethod")
    @test PackageScanner.is_false_positive_context("@test")
end

@testitem "is_false_positive_context - real code should pass" begin
    @test !PackageScanner.is_false_positive_context("df['first_name'] = 'John'")
    @test !PackageScanner.is_false_positive_context("x = data\$email")
    @test !PackageScanner.is_false_positive_context("SELECT name, phone FROM users")
    @test !PackageScanner.is_false_positive_context("gen birth_year = 2024 - age")
end

@testitem "PIIMatch structure" begin
    match = PackageScanner.PIIMatch(
        "data/test.dta",
        "first_name",
        "First Name of Respondent",
        ["name", "first_name"],
        ["John", "Jane", "Bob"]
    )
    
    @test match.filepath == "data/test.dta"
    @test match.variable_name == "first_name"
    @test match.variable_label == "First Name of Respondent"
    @test "name" in match.matched_terms
    @test length(match.sample_values) == 3
end

@testitem "PIIMatch with nothing label" begin
    match = PackageScanner.PIIMatch(
        "data/test.csv",
        "col1",
        nothing,
        ["email"],
        []
    )
    
    @test isnothing(match.variable_label)
    @test isempty(match.sample_values)
end


@testitem "read meta of pickle data" begin
    dta = joinpath(@__DIR__, "data", "ragged_data.pkl")
    out = PackageScanner.scan_data_file(dta)

    @test isempty(out)
end