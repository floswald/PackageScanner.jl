"""
    load_data_metadata(filepath::String, max_rows = 1000)

Load metadata from a data file.
For CSV files, uses Julia's CSV package.
For other file types, uses R's rio package.
Returns a dictionary with variable names, labels, and sample values,
or `nothing` if the file cannot be loaded.

# Arguments
- `filepath::String`: Path to the data file
- `max_rows::Int`: Maximum number of rows to read (default: 1000)

# Returns
- `Dict` with keys: `var_names`, `var_labels`, `samples`
- `nothing` if file cannot be loaded

# Examples
```julia
metadata = load_data_metadata("data/survey.dta")
println(metadata["var_names"])
```
"""
function load_data_metadata(filepath::String, max_rows = 1000)
    
    fname, ext = Base.Filesystem.splitext(filepath)

    if ext == ".csv"
        # Read CSV with Julia's CSV package
        data = try
            CSV.read(filepath, limit = max_rows, DataFrame) 
        catch
            @warn "file $filepath does not exist"
            return nothing
        end
        
        # Extract metadata using Julia function
        return extract_metadata(data)
    else
        # Use R only to read the data (no metadata extraction in R)
        R"""
        is_dta <- tools::file_ext($filepath) == "dta"

        # we only read the first 1000 rows of a stata file
        if (is_dta) {
            data = haven::read_dta($filepath, n_max = $max_rows)
        } else {
            data <- tryCatch(
                rio::import($filepath),
                error = function(e) {
                    message("Could not read file: ", $filepath)
                    return(NULL)
                }
            )
        }
        # extract labels
        labs <- lapply(data, function(x){attr(x, "label")})
        """
            
        # Get the data from R
        @rget data
        @rget labs
        
        # Extract metadata using the same Julia function
        return extract_metadata(data, labels = labs)
    end
end

"""
    extract_metadata(data)

Extract metadata from a dataset, including variable names, labels, and sample values.
Works with both CSV.File objects and R dataframes.

# Arguments
- `data`: A dataset (CSV.File or dataframe)

# Returns
- `Dict` with keys: `var_names`, `var_labels`, `samples`
"""
function extract_metadata(data; labels = nothing)
    if isnothing(data)
        return nothing
    end
    
    # Get variable names
    var_names = names(data)
    
    # Get sample values for each variable (up to 5 unique non-missing)
    samples = Dict{String, Vector{String}}()
    for name in var_names
        col = data[!, name]
        # Filter out missing values
        non_missing = filter(!ismissing, col)
        # Get unique values
        unique_vals = unique(non_missing)
        # Take up to 5 samples
        n_samples = min(5, length(unique_vals))
        if n_samples > 0
            # Convert to strings
            samples[String(name)] = map(x -> string(x), unique_vals[1:n_samples])
        else
            samples[String(name)] = String[]
        end
    end
    
    # Return as dictionary
    return Dict(
        "var_names" => map(String, var_names),
        "var_labels" => labels,
        "samples" => samples
    )
end
