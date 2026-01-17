"""
    load_data_metadata(filepath::String)

Load metadata from a data file using R's rio package.
Returns a dictionary with variable names, labels, and sample values,
or `nothing` if the file cannot be loaded.

# Arguments
- `filepath::String`: Path to the data file

# Returns
- `Dict` with keys: `var_names`, `var_labels`, `samples`
- `nothing` if file cannot be loaded

# Examples
```julia
metadata = load_data_metadata("data/survey.dta")
println(metadata["var_names"])
```
"""
function load_data_metadata(filepath::String)
    try
        R"""
        library(rio)
        
        data <- tryCatch(
            rio::import($filepath),
            error = function(e) {
                message("Could not read file: ", $filepath)
                return(NULL)
            }
        )
        
        if (!is.null(data)) {
            # Get variable names
            var_names <- names(data)
            
            # Get variable labels if they exist
            var_labels <- sapply(data, function(x) {
                label <- attr(x, "label")
                if (is.null(label)) NA else as.character(label)
            })
            
            # Get sample values for each variable (up to 5 unique non-missing)
            samples <- lapply(data, function(col) {
                non_missing <- col[!is.na(col)]
                unique_vals <- unique(non_missing)
                n_samples <- min(5, length(unique_vals))
                if (n_samples > 0) {
                    as.character(head(unique_vals, n_samples))
                } else {
                    character(0)
                }
            })
            
            # Return as list
            list(
                var_names = var_names,
                var_labels = var_labels,
                samples = samples
            )
        } else {
            NULL
        }
        """
        
        @rget data
        return data
        
    catch e
        @warn "Error loading $filepath: $e"
        return nothing
    end
end