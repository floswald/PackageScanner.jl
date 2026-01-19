module PIIScanner

using RCall
using Dates

# Include submodules
include("constants.jl")
include("data-loading.jl")
include("detection.jl")
include("reporting.jl")

end # module
