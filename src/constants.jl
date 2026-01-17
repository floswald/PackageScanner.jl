"""
    DEFAULT_PII_TERMS

Default list of PII search terms based on J-PAL PII-Scan.
These terms are commonly found in variable names that contain
personally identifiable information.
"""
const DEFAULT_PII_TERMS = [
    "address", "bday", "beneficiary", "birth", "birthday", "block",
    "census", "child", "city", "community", "compound", "coord",
    "country", "daughter", "degree", "district", "dob", "email",
    "father", "fax", "first_name", "fname", "gender", "gps", "house",
    "husband", "last_name", "lat", "lname", "loc", "location", "lon",
    "minute", "mother", "municipality", "name", "network", "panchayat",
    "parish", "phone", "precinct", "school", "second", "sex", "social",
    "spouse", "son", "street", "subcountry", "territory", "url",
    "village", "wife", "zip"
]

const FALSE_POSITIVE_PATTERNS = [
    r"\b(import|from|require|include|library|using)\b",
    r"\b(function|def|sub|class|struct|type)\s+\w+",
    r"#include",
    r"@\w+",
]