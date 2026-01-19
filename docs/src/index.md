# PIIScanner

This package searches code and data for traces of *Personally Identifiable Information (PII)*. This is helpful for replication packages for scientific projects. We rely on a set of default search terms.

Main functionality:

1. You can scan *code* files for default terms that might represent PII.
2. You can scan *data* files for the same. This works by loading the relevant data file via `R` package `rio`, and extracting relevant metadata - i.e. variable names - and comparing those to the search terms. 

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



# All Docstrings

```@autodocs
Modules = [PIIScanner]
```
