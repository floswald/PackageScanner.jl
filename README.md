# PackageScanner.jl

[![Build Status](https://github.com/floswald/PackageScanner.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/floswald/PackageScanner.jl/actions/workflows/CI.yml?query=branch%3Amain)

A comprehensive Julia package for **scanning and analyzing research replication packages**. PackageScanner combines PII detection, file path analysis, metadata extraction, and package validation in one tool.

This package is part of the [JPE Data Editor's](https://github.com/organizations/JPE-Reproducibility/) toolkit. Included functionality has been greatly inspired by the [AEA Data Editor's](https://github.com/AEADataEditor/replication-template-development) replication template setup.

## Features

### PII Detection

Based on the methodology from [J-PAL's PII-Scan](https://github.com/J-PAL/PII-Scan), scans variable names, labels, and code for personally identifiable information (PII) to help researchers comply with privacy regulations like GDPR. See [below](#what-does-gdpr-mean-for-researchers) for legal implications.

- **Fast Stata and CSV readers**: Reads only the first 1000 rows to avoid performance issues
- **Multi-format data support**: Uses R's `rio` package to read SPSS, SAS, Excel, CSV, and [many other formats](https://gesistsa.github.io/rio/#supported-file-formats)
- **Smart detection**: Minimizes false positives (e.g., `names(x)` vs `first_name`)
- **Customizable**: Add your own PII search terms

### Package Analysis
Comprehensive tools for analyzing research replication packages:

- **File classification**: Automatically categorizes files as code, data, or documentation
- **Path detection**: Identifies Windows/Unix file paths and hardcoded values in code
- **File metadata**: Analyzes sizes, checksums, and detects duplicates
- **README analysis**: Parses README files (MD/PDF) for key information
- **Code statistics**: Integration with `cloc` for line counting
- **Report generation**: Creates markdown reports for all analyses

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/floswald/PackageScanner.jl")
```

**Requirements:**
- Julia 1.10+
- R with the `rio` and `haven` packages installed
```r
# In R:
install.packages(c("rio", "haven"))
```
- Optional: `cloc` for code statistics (`brew install cloc` on macOS)

## Quick Start

### Full Package Analysis

```julia
using PackageScanner

# Run comprehensive analysis on a replication package
PackageScanner.precheck_package("/path/to/replication-package")
```

This single command performs:
1. File classification (code/data/docs)
2. File metadata analysis (sizes, checksums, duplicates)
3. Code line counting (via cloc if available)
4. File path detection in code
5. PII detection in data and code
6. README analysis

All reports are written to `generated/` folder at the package root.

### PII Scanning Only

```julia
using PackageScanner

# Define your files
data_files = ["data/survey.dta", "data/admin.csv"]
code_files = ["src/clean.R", "src/analysis.py"]

# Scan for PII
data_results = PackageScanner.scan_data_files(data_files)
code_results = PackageScanner.scan_code_files(code_files)

# Generate report
PackageScanner.write_pii_report(data_results, code_results, "output/")
```

## Detailed Usage

### PII Detection

```julia
# Scan a single data file
matches = PackageScanner.scan_data_file("data/survey.dta")

# Scan with strict matching (word boundaries only)
matches = PackageScanner.scan_data_file("data/survey.dta", strict=true)

# Add custom PII terms
matches = PackageScanner.scan_data_file("data/survey.dta", custom_terms=["patient_id", "taxpayer"])

# Scan code for PII references
code_matches = PackageScanner.scan_code_file("src/analysis.R")
```

### File Classification

```julia
# Classify files by type
code_files = PackageScanner.classify_files("/path/to/package", "code", "output/")
data_files = PackageScanner.classify_files("/path/to/package", "data", "output/")
docs_files = PackageScanner.classify_files("/path/to/package", "docs", "output/")
```

### File Metadata Analysis

```julia
# Analyze file sizes and detect duplicates
metadata = PackageScanner.generate_file_sizes_md5("/path/to/package", "output/")
```

### Path Detection

```julia
# Check code files for problematic file paths
PackageScanner.file_paths(code_files, "output/")
```

## Default PII Terms

The package searches for these terms by default (based on [J-PAL PII-Scan](https://github.com/J-PAL/PII-Scan)):

address, bday, beneficiary, birth, birthday, city, dob, email, 
first_name, fname, last_name, lname, name, phone, ssn, and more...

See `PackageScanner.DEFAULT_PII_TERMS` for the complete list.


## Example Reports

PackageScanner generates multiple markdown reports:

- `report-pii.md` - PII detection summary
- `report-file-paths.md` - File path analysis
- `report-file-sizes.md` - File metadata
- `report-duplicates.md` - Duplicate files
- `report-readme.md` - README analysis
- `report-cloc.md` - Code statistics
- And more...

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see LICENSE file

## Acknowledgments

- PII detection based on [J-PAL PII-Scan](https://github.com/J-PAL/PII-Scan)
- Uses R's `rio` package for multi-format data support
- Integrates JPEtools.jl functionality for comprehensive package analysis

## What does GDPR Mean for Researchers?

*There may be other legal provisions for publishing your research data beyond GDPR*

Here are three main things to keep in mind:

1. **Right to be Forgotten (Article 17)**: Researchers must be able to identify and delete an individual's data upon request. PII in datasets makes this possible - without proper tracking of identifiable information, you cannot comply with deletion requests. Conversely, inadvertently retaining PII when it should have been anonymized creates compliance risk.

2. **Data Minimization Principle (Article 5)**: You should only collect and retain personal data that is adequate, relevant, and limited to what's necessary for your research purpose. A PII scanner helps identify when you're holding more identifiable information than needed - for instance, keeping full names and addresses when only age ranges and region codes would suffice for analysis.

3. **Breach Notification Requirements (Article 33-34)**: If you suffer a data breach involving personal data, you must notify authorities within 72 hours and inform affected individuals. A PII scanner helps you quickly assess what was exposed in a breach - whether it's anonymized research data (lower risk) or datasets containing names, SSNs, or other direct identifiers (high risk requiring immediate notification).

**Background:**
* [Full Legal Text - EU GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
