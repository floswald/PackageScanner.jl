module PackageScanner

# Core dependencies
using RCall
using Dates
using Infiltrator
using CSV
using DataFrames
using MAT
using Pickle
using ZipFile

# Additional dependencies from JPEtools
using Glob
using PDFIO
using Printf
using SHA
using TestItems
using TOML

# PII Scanning modules
include("constants.jl")
include("data-loading.jl")
include("detection.jl")
include("CodeQualityScanner.jl")
include("reporting.jl")

# Package Analysis modules
include("file_classification.jl")
include("path_analysis.jl")
include("file_metadata.jl")
include("readme_parser.jl")
include("precheck.jl")
include("zip.jl")

end # module
