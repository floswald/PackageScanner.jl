module PIIScanner

using RCall
using Dates

# Export main types
export PIIMatch, PIIDetectionResults

# Export main functions
export scan_data_file, scan_code_file
export scan_data_files, scan_code_files
export write_pii_report, write_pii_report_simple
export generate_summary_table, generate_detailed_appendix

# Export constants
export DEFAULT_PII_TERMS

# Include submodules
include("constants.jl")
include("data-loading.jl")
include("detection.jl")
include("reporting.jl")

end # module
