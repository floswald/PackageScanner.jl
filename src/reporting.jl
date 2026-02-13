"""
    generate_summary_table(data_results::Vector{PIIMatch}, code_results::Vector{PIIMatch})

Generate a markdown summary table of PII detections.

# Arguments
- `data_results::Vector{PIIMatch}`: Data file PII matches
- `code_results::Vector{PIIMatch}`: Code file PII matches

# Returns
- `String`: Markdown formatted table
"""
function generate_summary_table(data_results::Vector{PIIMatch}, 
                               code_results::Vector{PIIMatch})
    # Group by file
    data_by_file = Dict{String, Vector{PIIMatch}}()
    for match in data_results
        if !haskey(data_by_file, match.filepath)
            data_by_file[match.filepath] = PIIMatch[]
        end
        push!(data_by_file[match.filepath], match)
    end
    
    code_by_file = Dict{String, Vector{PIIMatch}}()
    for match in code_results
        if !haskey(code_by_file, match.filepath)
            code_by_file[match.filepath] = PIIMatch[]
        end
        push!(code_by_file[match.filepath], match)
    end
    
    lines = String[]
    
    push!(lines, "| File Type | File | Variables/References | PII Categories |")
    push!(lines, "|-----------|------|----------------------|----------------|")
    
    # Data files
    for (filepath, matches) in sort(collect(data_by_file), by=x->basename(x[1]))
        fname = basename(filepath)
        n_vars = length(matches)
        
        # Get unique PII categories
        all_terms = String[]
        for m in matches
            append!(all_terms, m.matched_terms)
        end
        categories = join(unique(all_terms), ", ")
        
        push!(lines, "| Data | `$fname` | $n_vars | $categories |")
    end
    
    # Code files
    for (filepath, matches) in sort(collect(code_by_file), by=x->basename(x[1]))
        fname = basename(filepath)
        n_refs = length(matches)
        
        all_terms = String[]
        for m in matches
            append!(all_terms, m.matched_terms)
        end
        categories = join(unique(all_terms), ", ")
        
        push!(lines, "| Code | `$fname` | $n_refs | $categories |")
    end
    
    return join(lines, "\n")
end

"""
    generate_detailed_appendix(data_results::Vector{PIIMatch}, code_results::Vector{PIIMatch}; splitat=nothing)

Generate detailed markdown listing of all PII detections.

# Arguments
- `data_results::Vector{PIIMatch}`: Data file PII matches
- `code_results::Vector{PIIMatch}`: Code file PII matches
- `splitat::Union{String,Nothing}=nothing`: Optional string to split paths at

# Returns
- `String`: Markdown formatted detailed listing
"""
function generate_detailed_appendix(data_results::Vector{PIIMatch}, 
                                   code_results::Vector{PIIMatch};
                                   splitat::Union{String,Nothing}=nothing)
    lines = String[]
    
    # Helper function to split paths if needed
    path_splitter(path, splitat) = if !isnothing(splitat)
        parts = split(path, splitat)
        length(parts) > 1 ? join(parts[2:end], splitat) : path
    else
        path
    end
    
    # Data files section
    if !isempty(data_results)
        push!(lines, "### Data Files\n")
        
        data_by_file = Dict{String, Vector{PIIMatch}}()
        for match in data_results
            if !haskey(data_by_file, match.filepath)
                data_by_file[match.filepath] = PIIMatch[]
            end
            push!(data_by_file[match.filepath], match)
        end
        
        for (filepath, matches) in sort(collect(data_by_file), by=x->x[1])
            display_path = path_splitter(filepath, splitat)
            push!(lines, "**$display_path**\n")
            
            for match in sort(matches, by=x->x.variable_name)
                terms = join(match.matched_terms, ", ")
                label_info = if !isnothing(match.variable_label)
                    " (label: *$(match.variable_label)*)"
                else
                    ""
                end
                
                push!(lines, "- Variable: `$(match.variable_name)`$label_info")
                push!(lines, "  - Matched terms: $terms")
                
                if !isempty(match.sample_values)
                    samples = join(match.sample_values[1:min(3, length(match.sample_values))], ", ")
                    push!(lines, "  - Sample values: $samples")
                end
            end
            push!(lines, "")
        end
    end
    
    # Code files section
    if !isempty(code_results)
        push!(lines, "### Code Files\n")
        
        code_by_file = Dict{String, Vector{PIIMatch}}()
        for match in code_results
            if !haskey(code_by_file, match.filepath)
                code_by_file[match.filepath] = PIIMatch[]
            end
            push!(code_by_file[match.filepath], match)
        end
        
        for (filepath, matches) in sort(collect(code_by_file), by=x->x[1])
            display_path = path_splitter(filepath, splitat)
            push!(lines, "**$display_path**\n")
            
            for match in matches
                terms = join(match.matched_terms, ", ")
                context = match.sample_values[1]
                
                push!(lines, "- $(match.variable_name): $terms")
                push!(lines, "  ```")
                push!(lines, "  $context")
                push!(lines, "  ```")
            end
            push!(lines, "")
        end
    end
    
    return join(lines, "\n")
end

"""
    write_pii_report(data_results, code_results, output_dir; kwargs...)

Write PII detection reports (main summary and detailed appendix).

# Arguments
- `data_results::Vector{PIIMatch}`: Data file PII matches
- `code_results::Vector{PIIMatch}`: Code file PII matches
- `output_dir::String`: Directory to write reports to

# Keyword Arguments
- `splitat::Union{String,Nothing}=nothing`: String to split file paths at
- `main_file::String="report-pii.md"`: Name of main report file
- `appendix_file::String="report-pii-appendix.md"`: Name of appendix file

# Examples
```julia
write_pii_report(data_results, code_results, "/output", splitat="/project/")
```
"""
function write_pii_report(data_results::Vector{PIIMatch}, 
                         code_results::Vector{PIIMatch},
                         output_dir::String;
                         splitat::Union{String,Nothing}=nothing,
                         main_file::String="report-pii.md",
                         appendix_file::String="report-pii-appendix.md")
    
    has_pii = !isempty(data_results) || !isempty(code_results)
    
    # Write main report with summary
    open(joinpath(output_dir, main_file), "w") do io
        println(io, "## Potential Personal Identifiable Information (PII)\n")
        
        if !has_pii
            println(io, "✅ No PII found.")
        else
            println(io, "⚠️ We found the following instances of potentially personally identifying information. This may be completely legitimate but might be worth checking. *As a reminder, privacy legislation in many countries (e.g. GDPR in EU) prohibits the dissemination of personal identifiable information without prior (and documented) consent of individuals.* If indeed you want to publish such information with your replication package, you should probably have obtained IRB approval for this - please check!\n")
            
            # Summary statistics
            n_data_files = length(unique(m.filepath for m in data_results))
            n_code_files = length(unique(m.filepath for m in code_results))
            n_data_vars = length(data_results)
            n_code_refs = length(code_results)
            
            println(io, "**Summary:**")
            println(io, "- Data files with PII indicators: $n_data_files")
            println(io, "- Variables flagged in data: $n_data_vars")
            println(io, "- Code files with PII references: $n_code_files")
            println(io, "- PII references in code: $n_code_refs\n")
            
            # Summary table
            println(io, "### Summary of Flagged Files\n")
            table = generate_summary_table(data_results, code_results)
            println(io, table)
            println(io, "\n*See [Appendix]($appendix_file) for detailed listing of all flagged instances.*")
        end
    end
    
    # Write detailed appendix
    if has_pii
        open(joinpath(output_dir, appendix_file), "w") do io
            println(io, "## Appendix: Detailed PII Detection Results\n")
            println(io, "*Generated on $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))*\n")
            println(io, "This appendix lists all detected instances of potential personally identifiable information (PII) in the project files. Each entry shows the matched PII terms and, for data files, sample values to help verify whether the flagged content is indeed sensitive.\n")
            
            appendix = generate_detailed_appendix(data_results, code_results; splitat=splitat)
            println(io, appendix)
        end
        
        println("✓ PII reports written:")
        println("  Main report: $(joinpath(output_dir, main_file))")
        println("  Detailed appendix: $(joinpath(output_dir, appendix_file))")
    else
        println("✓ PII report written: $(joinpath(output_dir, main_file))")
        println("  No appendix generated (no PII found)")
    end
end

"""
    write_pii_report_simple(data_results, code_results, fp; splitat=nothing)

Write single PII report in simple bullet-list format.

# Arguments
- `data_results::Vector{PIIMatch}`: Data file PII matches
- `code_results::Vector{PIIMatch}`: Code file PII matches  
- `fp::String`: Directory to write report to
- `splitat::Union{String,Nothing}=nothing`: String to split file paths at

# Examples
```julia
write_pii_report_simple(data_results, code_results, "/output")
```
"""
function write_pii_report_simple(data_results::Vector{PIIMatch}, 
                                code_results::Vector{PIIMatch},
                                fp::String;
                                splitat::Union{String,Nothing}=nothing)
    
    # Combine all matches into a dict
    piis = Dict{String, Vector{String}}()
    
    # Data files
    for match in data_results
        if !haskey(piis, match.filepath)
            piis[match.filepath] = String[]
        end
        
        terms = join(match.matched_terms, ", ")
        label_info = isnothing(match.variable_label) ? "" : " ($(match.variable_label))"
        samples = isempty(match.sample_values) ? "" : " | samples: $(join(match.sample_values[1:min(3, length(match.sample_values))], ", "))"
        
        push!(piis[match.filepath], "Variable `$(match.variable_name)`$label_info - terms: $terms$samples")
    end
    
    # Code files
    for match in code_results
        if !haskey(piis, match.filepath)
            piis[match.filepath] = String[]
        end
        
        terms = join(match.matched_terms, ", ")
        context = match.sample_values[1][1:min(80, length(match.sample_values[1]))]
        
        push!(piis[match.filepath], "$(match.variable_name): $terms → `$context`")
    end
    
    # Helper function
    path_splitter(path, splitat) = if !isnothing(splitat)
        parts = split(path, splitat)
        length(parts) > 1 ? join(parts[2:end], splitat) : path
    else
        path
    end
    
    # Write report
    open(joinpath(fp, "report-pii.md"), "w") do io
        println(io, "## Potential Personal Identifiable Information (PII)\n")
        
        if isempty(piis)
            println(io, "✅ No PII found.")
        else
            println(io, "⚠️ We found the following instances of potentially personally identifying information. This may be completely legitimate but might be worth checking. *As a reminder, privacy legislation in many countries (e.g. GDPR in EU) prohibits the dissemination of personal identifiable information without prior (and documented) consent of individuals.* If indeed you want to publish such information with your replication package, you should probably have obtained IRB approval for this - please check!\n")
            
            for (file, lines) in sort(collect(piis), by=x->x[1])
                println(io, "**$(path_splitter(file, splitat))**\n")
                for l in lines
                    println(io, "- ", l)
                end
                println(io)
            end
        end
    end
    
    println("✓ PII report written: $(joinpath(fp, "report-pii.md"))")
end

function full_example()
    tmpdir = mktempdir()
    
    # Create test data file
    data_file = joinpath(tmpdir, "survey.csv")
    open(data_file, "w") do io
        println(io, "respondent_id,first_name,age,city")
        println(io, "1,John,30,NYC")
        println(io, "2,Jane,25,LA")
    end
    
    # Create test code file
    code_file = joinpath(tmpdir, "analysis.R")
    open(code_file, "w") do io
        println(io, "data <- read.csv('survey.csv')")
        println(io, "model <- lm(age ~ first_name)")
    end
    return data_file
    # Run full workflow
    data_results = redirect_stdout(devnull) do
        PackageScanner.scan_data_files([data_file])
    end

    data_results
end