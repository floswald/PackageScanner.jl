"""
    PIIMatch

A structure representing a detected PII match.

# Fields
- `filepath::String`: Path to the file containing the match
- `variable_name::String`: Name of the variable or line identifier
- `variable_label::Union{String, Nothing}`: Variable label (if available)
- `matched_terms::Vector{String}`: PII terms that matched
- `sample_values::Vector{String}`: Sample values from the data
"""
struct PIIMatch
    filepath::String
    variable_name::String
    variable_label::Union{String, Nothing}
    matched_terms::Vector{String}
    sample_values::Vector{String}
end

"""
    find_pii_terms(text::String, search_terms::Vector{String}; strict::Bool=false)

Search for PII terms in text string.

# Arguments
- `text::String`: Text to search
- `search_terms::Vector{String}`: List of PII terms to search for
- `strict::Bool=false`: If true, use word boundary matching

# Returns
- `Vector{String}`: List of matched terms
"""
function find_pii_terms(text::String, search_terms::Vector{String}; strict::Bool=false)::Vector{String}
    matched = String[]
    
    for term in search_terms
        if strict
            # Special cases for variable naming in code: treat underscores as word boundaries
            # Handle both "name" and "first_name" as separate words in code context
            words = split(text, "_")
            
            # Check if the term matches any word exactly (case insensitive)
            if any(lowercase(word) == lowercase(term) for word in words) ||
               # Also check with standard word boundaries for regular text
               occursin(Regex("\\b$(term)\\b", "i"), text)
                push!(matched, term)
            end
        else
            # Non-strict mode: match substrings anywhere
            if occursin(Regex(term, "i"), text)
                push!(matched, term)
            end
        end
    end
    
    return matched
end

"""
    is_false_positive_context(line::String)

Check if a line of code represents a false positive context.

# Arguments
- `line::String`: Line of code to check

# Returns
- `Bool`: true if line is likely a false positive
"""
function is_false_positive_context(line::String)::Bool
    return any(occursin(pat, line) for pat in FALSE_POSITIVE_PATTERNS)
end

"""
    scan_data_file(filepath::String; strict::Bool=false, custom_terms::Vector{String}=String[])

Scan a data file for PII indicators in variable names and labels.

# Arguments
- `filepath::String`: Path to data file
- `strict::Bool=false`: Use strict word boundary matching
- `custom_terms::Vector{String}=String[]`: Additional PII terms to search for

# Returns
- `Vector{PIIMatch}`: List of detected PII matches

# Examples
```julia
matches = scan_data_file("data/survey.dta")
matches = scan_data_file("data/survey.dta", strict=true)
matches = scan_data_file("data/survey.dta", custom_terms=["patient_id"])
```
"""
function scan_data_file(filepath::String; 
                       strict::Bool=false,
                       custom_terms::Vector{String}=String[])::Vector{PIIMatch}
    matches = PIIMatch[]
    
    # Use R+rio to load the file metadata
    data = load_data_metadata(filepath)
    
    if isnothing(data)
        return matches
    end
    
    var_names = data["var_names"]
    var_labels = data["var_labels"]
    samples = data["samples"]
    
    # All PII search in Julia
    search_terms = isempty(custom_terms) ? DEFAULT_PII_TERMS : [DEFAULT_PII_TERMS..., custom_terms...]
    
    for i in 1:length(var_names)
        var_name = var_names[i]
        var_label = ismissing(var_labels[i]) ? nothing : var_labels[i]
        var_samples = samples[i]
        
        matched_terms = String[]
        
        # Check variable name
        append!(matched_terms, find_pii_terms(var_name, search_terms, strict=strict))
        
        # Check variable label if it exists
        if !isnothing(var_label) && !ismissing(var_label)
            append!(matched_terms, find_pii_terms(var_label, search_terms, strict=strict))
        end
        
        # If we found matches, record them
        if !isempty(matched_terms)
            push!(matches, PIIMatch(
                filepath,
                var_name,
                var_label,
                unique(matched_terms),
                var_samples
            ))
        end
    end
    
    return matches
end

"""
    scan_code_file(filepath::String; strict::Bool=false, custom_terms::Vector{String}=String[])

Scan a code file for PII term references.

# Arguments
- `filepath::String`: Path to code file
- `strict::Bool=false`: Use strict word boundary matching
- `custom_terms::Vector{String}=String[]`: Additional PII terms to search for

# Returns
- `Vector{PIIMatch}`: List of detected PII references

# Examples
```julia
matches = scan_code_file("src/analysis.R")
matches = scan_code_file("src/analysis.R", strict=true)
```
"""
function scan_code_file(filepath::String; 
                       strict::Bool=false,
                       custom_terms::Vector{String}=String[])::Vector{PIIMatch}
    matches = PIIMatch[]
    search_terms = isempty(custom_terms) ? DEFAULT_PII_TERMS : [DEFAULT_PII_TERMS..., custom_terms...]
    
    try
        open(filepath, "r") do io
            for (i, line) in enumerate(eachline(io))
                isempty(strip(line)) && continue
                
                # Skip obvious false positives
                if is_false_positive_context(line)
                    continue
                end
                
                matched_in_line = find_pii_terms(line, search_terms, strict=strict)
                
                if !isempty(matched_in_line)
                    push!(matches, PIIMatch(
                        filepath,
                        "Line $i",
                        nothing,
                        matched_in_line,
                        [strip(line)[1:min(100, length(strip(line)))]]
                    ))
                end
            end
        end
    catch e
        @warn "Error reading code file $filepath: $e"
    end
    
    return matches
end

"""
    scan_data_files(data_files::Vector{String}; strict::Bool=false, custom_terms::Vector{String}=String[])

Scan multiple data files for PII indicators.

# Arguments
- `data_files::Vector{String}`: Vector of data file paths
- `strict::Bool=false`: Use strict word boundary matching
- `custom_terms::Vector{String}=String[]`: Additional PII terms

# Returns
- `Vector{PIIMatch}`: All detected PII matches across files

# Examples
```julia
data_files = ["data/survey.dta", "data/admin.csv"]
matches = scan_data_files(data_files)
```
"""
function scan_data_files(data_files::Vector{String}; 
                        strict::Bool=false,
                        custom_terms::Vector{String}=String[])
    all_matches = PIIMatch[]
    
    println("Scanning $(length(data_files)) data files...")
    for (idx, filepath) in enumerate(data_files)
        print("  [$idx/$(length(data_files))] $filepath ... ")
        
        matches = scan_data_file(filepath; strict=strict, custom_terms=custom_terms)
        
        if isempty(matches)
            println("✓ clean")
        else
            println("⚠ $(length(matches)) variables flagged")
        end
        
        append!(all_matches, matches)
    end
    
    return all_matches
end

"""
    scan_code_files(code_files::Vector{String}; strict::Bool=false, custom_terms::Vector{String}=String[])

Scan multiple code files for PII references.

# Arguments
- `code_files::Vector{String}`: Vector of code file paths
- `strict::Bool=false`: Use strict word boundary matching
- `custom_terms::Vector{String}=String[]`: Additional PII terms

# Returns
- `Vector{PIIMatch}`: All detected PII references across files

# Examples
```julia
code_files = ["src/clean.R", "src/analysis.py"]
matches = scan_code_files(code_files)
```
"""
function scan_code_files(code_files::Vector{String}; 
                        strict::Bool=false,
                        custom_terms::Vector{String}=String[])
    all_matches = PIIMatch[]
    
    println("Scanning $(length(code_files)) code files...")
    for (idx, filepath) in enumerate(code_files)
        print("  [$idx/$(length(code_files))] $filepath ... ")
        
        matches = scan_code_file(filepath; strict=strict, custom_terms=custom_terms)
        
        if isempty(matches)
            println("✓ clean")
        else
            println("⚠ $(length(matches)) references")
        end
        
        append!(all_matches, matches)
    end
    
    return all_matches
end
