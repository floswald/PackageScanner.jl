module PIIScanner

using RCall
using Dates
using Infiltrator
using CSV
using DataFrames
using MAT
using Pickle

# Include submodules
include("constants.jl")
include("data-loading.jl")
include("detection.jl")
include("reporting.jl")

end # module
