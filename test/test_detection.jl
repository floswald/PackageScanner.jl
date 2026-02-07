@testitem "find_pii_terms - basic matching" begin
    # Should match
    @test "name" in PIIScanner.find_pii_terms("first_name", PIIScanner.DEFAULT_PII_TERMS)
    @test "email" in PIIScanner.find_pii_terms("user_email", PIIScanner.DEFAULT_PII_TERMS)
    @test "phone" in PIIScanner.find_pii_terms("contact_phone", PIIScanner.DEFAULT_PII_TERMS)
    
    # Should not match
    @test isempty(PIIScanner.find_pii_terms("randomvar", PIIScanner.DEFAULT_PII_TERMS))
    @test isempty(PIIScanner.find_pii_terms("count", PIIScanner.DEFAULT_PII_TERMS))
    @test isempty(PIIScanner.find_pii_terms("x123", PIIScanner.DEFAULT_PII_TERMS))
end

@testitem "find_pii_terms - case insensitive" begin
    @test "name" in PIIScanner.find_pii_terms("FIRST_NAME", PIIScanner.DEFAULT_PII_TERMS)
    @test "email" in PIIScanner.find_pii_terms("Email_Address", PIIScanner.DEFAULT_PII_TERMS)
    @test "phone" in PIIScanner.find_pii_terms("PhoneNumber", PIIScanner.DEFAULT_PII_TERMS)
end

@testitem "find_pii_terms - strict mode word boundaries" begin
    # Strict mode: should match whole words only
    @test "name" in PIIScanner.find_pii_terms("name", PIIScanner.DEFAULT_PII_TERMS, strict=true)
    @test "name" in PIIScanner.find_pii_terms("first_name", PIIScanner.DEFAULT_PII_TERMS, strict=true)
    
    # Strict mode: should NOT match partial words
    @test isempty(PIIScanner.find_pii_terms("filename", PIIScanner.DEFAULT_PII_TERMS, strict=true))
    @test isempty(PIIScanner.find_pii_terms("rename", PIIScanner.DEFAULT_PII_TERMS, strict=true))
    @test isempty(PIIScanner.find_pii_terms("latitude", PIIScanner.DEFAULT_PII_TERMS, strict=true))
end

@testitem "find_pii_terms - non-strict mode" begin
    # Non-strict: should match substrings
    @test "name" in PIIScanner.find_pii_terms("filename", PIIScanner.DEFAULT_PII_TERMS, strict=false)
    @test "lat" in PIIScanner.find_pii_terms("latitude", PIIScanner.DEFAULT_PII_TERMS, strict=false)
end

@testitem "find_pii_terms - multiple matches" begin
    matches = PIIScanner.find_pii_terms("person_name_email_address", PIIScanner.DEFAULT_PII_TERMS)
    @test "name" in matches
    @test "email" in matches
    @test "address" in matches
    @test length(matches) >= 3
end

@testitem "is_false_positive_context - imports" begin
    @test PIIScanner.is_false_positive_context("import pandas as pd")
    @test PIIScanner.is_false_positive_context("from datetime import datetime")
    @test PIIScanner.is_false_positive_context("require(dplyr)")
    @test PIIScanner.is_false_positive_context("library(tidyverse)")
    @test PIIScanner.is_false_positive_context("using DataFrames")
    @test PIIScanner.is_false_positive_context("#include <stdio.h>")
end

@testitem "is_false_positive_context - function definitions" begin
    @test PIIScanner.is_false_positive_context("function process_name(x)")
    @test PIIScanner.is_false_positive_context("def get_email():")
    @test PIIScanner.is_false_positive_context("sub check_phone {")
    @test PIIScanner.is_false_positive_context("class Person {")
    @test PIIScanner.is_false_positive_context("struct UserData {")
end

@testitem "is_false_positive_context - decorators" begin
    @test PIIScanner.is_false_positive_context("@property")
    @test PIIScanner.is_false_positive_context("@staticmethod")
    @test PIIScanner.is_false_positive_context("@test")
end

@testitem "is_false_positive_context - real code should pass" begin
    @test !PIIScanner.is_false_positive_context("df['first_name'] = 'John'")
    @test !PIIScanner.is_false_positive_context("x = data\$email")
    @test !PIIScanner.is_false_positive_context("SELECT name, phone FROM users")
    @test !PIIScanner.is_false_positive_context("gen birth_year = 2024 - age")
end

@testitem "PIIMatch structure" begin
    match = PIIScanner.PIIMatch(
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
    match = PIIScanner.PIIMatch(
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
    out = PIIScanner.scan_data_file(dta)

    @test isempty(out)
end