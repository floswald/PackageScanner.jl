# PIIScanner.jl

[![Build Status](https://github.com/floswald/PIIScanner.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/floswald/PIIScanner.jl/actions/workflows/CI.yml?query=branch%3Amain)

A Julia package for detecting **Personally Identifiable Information (PII)** in data files and code.

Based on the methodology from [J-PAL's PII-Scan](https://github.com/J-PAL/PII-Scan), this package scans variable names, labels, and code for common PII indicators to help researchers comply with privacy regulations like GDPR.

## Features

The package scans both data and code files for suspicious terms. Code is scanned entirely, because it's relatively cheap (simply text), data files are only scanned partially in order to generate metadata (column names, samples of supicious columns, stata variable labels). The package tries to be smart about false positives (e.g. `names(x)` is legal `R` code, whereas `first_name` is a potentially suspicious column name).

- **Fast Stata and CSV readers**: The package reads only the first 1000 rows of either a `.dta` (via R `haven`) or a `.csv` (via `CSV.jl`) data file. This is important to avoid long waits (and failures) when trying to attempt to read very large data files. 
- **Multi-format data support**: Uses R's `rio` package to read SPSS, SAS, Excel, CSV, and [many other formats](https://gesistsa.github.io/rio/#supported-file-formats)
- **Smart detection**: Scans variable names, labels, and code for PII terms, trying to minimize false positives
- **Customizable**: Add your own PII search terms, adjust strictness
- **Report generation**: Creates markdown reports for inclusion in research documentation

## Installation
```julia
using Pkg
Pkg.add(url="https://github.com/floswald/PIIScanner.jl")
```

**Requirements:**
- Julia 1.10+
- R with the `rio` and `haven` packages installed
```r
# In R:
install.packages(c("rio", "haven"))
```

## Quick Start
```julia
using PIIScanner

# Define your files
data_files = ["data/survey.dta", "data/admin.csv"]
code_files = ["src/clean.R", "src/analysis.py"]

# Scan for PII
data_results = PIIScanner.scan_data_files(data_files)
code_results = PIIScanner.scan_code_files(code_files)

# Generate report
PIIScanner.write_pii_report(data_results, code_results, "output/")
```

## Usage

### Scanning Data Files
```julia
# Scan a single data file
matches = PIIScanner.scan_data_file("data/survey.dta")

# Scan with strict matching (word boundaries only)
matches = PIIScanner.scan_data_file("data/survey.dta", strict=true)

# Add custom PII terms
matches = PIIScanner.scan_data_file("data/survey.dta", custom_terms=["patient_id", "taxpayer"])

# Batch scan
matches = PIIScanner.scan_data_files(data_files)
```

### Scanning Code Files
```julia
# Scan code for PII references
matches = PIIScanner.scan_code_file("src/analysis.R")

# Batch scan
matches = PIIScanner.scan_code_files(code_files)
```

### Generating Reports
```julia
# Two-file report (summary + detailed appendix)
PIIScanner.write_pii_report(data_results, code_results, "output/")

# Single simple report
PIIScanner.write_pii_report_simple(data_results, code_results, "output/")

# Trim file paths in report
PIIScanner.write_pii_report(data_results, code_results, "output/", splitat="/project/")
```

## Default PII Terms

The package searches for these terms by default (based on [J-PAL PII-Scan](https://github.com/J-PAL/PII-Scan)):

address, bday, beneficiary, birth, birthday, city, dob, email, 
first_name, fname, last_name, lname, name, phone, ssn, and more...

See `PIIScanner.DEFAULT_PII_TERMS` for the complete list.

## Example Output

**Main Report (report-pii.md):**
```markdown
## Potential Personal Identifiable Information (PII)

⚠️ We found the following instances...

**Summary:**
- Data files with PII indicators: 2
- Variables flagged in data: 8

### Summary of Flagged Files

| File Type | File | Variables/References | PII Categories |
|-----------|------|----------------------|----------------|
| Data | `survey.dta` | 5 | name, phone, email |
| Data | `admin.csv` | 3 | birth, address |
```

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see LICENSE file

## Acknowledgments

- Based on [J-PAL PII-Scan](https://github.com/J-PAL/PII-Scan)
- Uses R's `rio` package for multi-format data support



## What does GDPR Mean for Researchers?

*There may be other legal provisions for publishing your research data beyond GDPR*

Here are three main things to keep in mind:

1. Right to be Forgotten (Article 17): Researchers must be able to identify and delete an individual's data upon request. PII in datasets makes this possible - without proper tracking of identifiable information, you cannot comply with deletion requests. Conversely, inadvertently retaining PII when it should have been anonymized creates compliance risk.
2. Data Minimization Principle (Article 5): You should only collect and retain personal data that is adequate, relevant, and limited to what's necessary for your research purpose. A PII scanner helps identify when you're holding more identifiable information than needed - for instance, keeping full names and addresses when only age ranges and region codes would suffice for analysis.
3. Breach Notification Requirements (Article 33-34): If you suffer a data breach involving personal data, you must notify authorities within 72 hours and inform affected individuals. A PII scanner helps you quickly assess what was exposed in a breach - whether it's anonymized research data (lower risk) or datasets containing names, SSNs, or other direct identifiers (high risk requiring immediate notification).

Background:

* [Full Legal Text - EU GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/oj)




# All Docstrings

```@autodocs
Modules = [PIIScanner]
```
