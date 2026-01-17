# PIIScanner.jl

[![Build Status](https://github.com/floswald/PIIScanner.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/floswald/PIIScanner.jl/actions/workflows/CI.yml?query=branch%3Amain)

A Julia package for detecting Personally Identifiable Information (PII) in data files and code.

Based on the methodology from [J-PAL's PII-Scan](https://github.com/J-PAL/PII-Scan), this package scans variable names, labels, and code for common PII indicators to help researchers comply with privacy regulations like GDPR.

## Features

- **Multi-format data support**: Uses R's `rio` package to read Stata, SPSS, SAS, Excel, CSV, and many other formats
- **Smart detection**: Scans variable names, labels, and code for PII terms
- **Customizable**: Add your own PII search terms, adjust strictness
- **Report generation**: Creates markdown reports for inclusion in research documentation

## Installation
```julia
using Pkg
Pkg.add(url="https://github.com/floswald/PIIScanner.jl")
```

**Requirements:**
- Julia 1.10+
- R with the `rio` package installed
```r
# In R:
install.packages("rio")
```

## Quick Start
```julia
using PIIScanner

# Define your files
data_files = ["data/survey.dta", "data/admin.csv"]
code_files = ["src/clean.R", "src/analysis.py"]

# Scan for PII
data_results = scan_data_files(data_files)
code_results = scan_code_files(code_files)

# Generate report
write_pii_report(data_results, code_results, "output/")
```

## Usage

### Scanning Data Files
```julia
# Scan a single data file
matches = scan_data_file("data/survey.dta")

# Scan with strict matching (word boundaries only)
matches = scan_data_file("data/survey.dta", strict=true)

# Add custom PII terms
matches = scan_data_file("data/survey.dta", custom_terms=["patient_id", "taxpayer"])

# Batch scan
matches = scan_data_files(data_files)
```

### Scanning Code Files
```julia
# Scan code for PII references
matches = scan_code_file("src/analysis.R")

# Batch scan
matches = scan_code_files(code_files)
```

### Generating Reports
```julia
# Two-file report (summary + detailed appendix)
write_pii_report(data_results, code_results, "output/")

# Single simple report
write_pii_report_simple(data_results, code_results, "output/")

# Trim file paths in report
write_pii_report(data_results, code_results, "output/", splitat="/project/")
```

## Default PII Terms

The package searches for these terms by default (based on J-PAL PII-Scan):

address, bday, beneficiary, birth, birthday, city, dob, email, 
first_name, fname, last_name, lname, name, phone, ssn, and more...

See `DEFAULT_PII_TERMS` for the complete list.

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
