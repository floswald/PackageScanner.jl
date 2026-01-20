module PIIScanner

using RCall
using Dates
using Infiltrator
using CSV
using DataFrames

# Include submodules
include("constants.jl")
include("data-loading.jl")
include("detection.jl")
include("reporting.jl")

end # module
