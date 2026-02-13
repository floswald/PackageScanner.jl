module PackageScanner

# Core dependencies
using RCall
using Dates
using Infiltrator
using CSV
using DataFrames
using MAT
using Pickle

# Additional dependencies from JPEtools
using Glob
using PDFIO
using Printf
using SHA
using TestItems

# PII Scanning modules (original PIIScanner functionality)
include("constants.jl")
include("data-loading.jl")
include("detection.jl")
include("reporting.jl")

# Package Analysis modules (from JPEtools)
include("file_classification.jl")
include("path_analysis.jl")
include("file_metadata.jl")
include("readme_parser.jl")
include("precheck.jl")

end # module
