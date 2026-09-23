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

"""
    SECRET_PATTERNS

Shared list of `(secret_type, pattern)` pairs for common API-key/credential
formats. Single source of truth for both `redact_secrets` (strips a live
credential out of text before it reaches a written report) and
`scan_secrets` (flags that a credential is present, without ever capturing
the matched text).
"""
const SECRET_PATTERNS = [
    ("OpenAI project key", r"sk-proj-[A-Za-z0-9_-]{20,}"),
    ("OpenAI legacy key", r"sk-[A-Za-z0-9]{20,}"),
    ("AWS access key ID", r"AKIA[0-9A-Z]{16}"),
    ("GitHub token", r"gh[oprsu]_[A-Za-z0-9]{36,}"),
    ("Slack token", r"xox[baprs]-[A-Za-z0-9-]{10,}"),
    ("Google API key", r"AIza[0-9A-Za-z_-]{35}"),
    ("PEM private key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
]