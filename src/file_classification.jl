# File Classification Module
# Functions for classifying files by type (code, data, documentation)

"""
    rdir(dir::AbstractString, pat::Glob.FilenameMatch)

Recursively search a directory tree for files matching the pattern.
"""
function rdir(dir::AbstractString, pat::Glob.FilenameMatch)
    result = String[]
    for (root, dirs, files) in walkdir(dir)
        append!(result, filter!(f -> occursin(pat, f), joinpath.(root, files)))     
    end
    return result
end

rdir(dir::AbstractString, pat::AbstractString) = rdir(dir, Glob.FilenameMatch(pat,"i"))

"""
    findfile(directory, file; casesensitive = true)

Find one specific file in the tree.
"""
function findfile(directory, file; casesensitive = true) 
    if casesensitive
        [joinpath(root, file) for (root, dirs, files) in walkdir(directory) if file in files]
    else
        [joinpath(root, file) for (root, dirs, files) in walkdir(directory) if file in lowercase.(files)]
    end
end

"""
    classify_files(pkg_path::String, kind::String, fp::String; relpath = false, pre_manifest=nothing)

Count how many files belong to each of code, data, documentation according to their file ending.

# Arguments
- `pkg_path`: path to (extracted) replication package
- `kind`: what kind of classification is desired: `code`, `data`, `docs`
- `fp`: output folder path
- `pre_manifest`: optional manifest with complete file list and extraction status

Outputs `txt` files into folder `fp` which will be created if needed.
"""
function classify_files(pkg_path::String, kind::String, fp::String; 
                       relpath = false, 
                       pre_manifest::Union{Nothing,DataFrame}=nothing)

     # write to `generated`
     mkpath(fp)

    sensitivenames = String[]
    nonsensitivenames = String[]
    files = String[]

    if kind == "code"
        extensions = ["ado","do","r","rmd","qmd","ox","m","py","nb","ipynb","sas","jl","f","f90","c","c++","sh","toml","yaml","yml","fs","fsx","tex","typst","sql", "jmd"]
        
        outfile = joinpath(fp,"program-files.txt")
        manifest_file = joinpath(fp,"program-files-manifest.csv")

        sensitivenames = ["Makefile"]

    elseif kind == "data"
        extensions = ["gpkg","dat","dta","rda","rds","rdata","ods","xls","xlsx","mat","csv","","txt","shp","xml","prj","dbf","sav","pkl","jld","jld2","gz","sas7bdat","rar","zip","7z","tar","tgz","bz2","xz","parquet", "json", "jsonl", "pickle"]

        outfile = joinpath(fp,"data-files.md")
        manifest_file = joinpath(fp,"data-files-manifest.csv")

    elseif kind == "docs"

        extensions = ["pdf","md","docx","doc","pages"]

        outfile = joinpath(fp,"documentation-files.txt")
        manifest_file = joinpath(fp,"docs-files-manifest.csv")

    else 
        error("kind not found: choose `code`, `data`, `docs`")
    end

    # Helper to check if file matches this kind
    function matches_extension(filepath::String, exts::Vector{String})
        for e in exts
            if e == ""
                # Empty extension means no extension
                if !occursin(".", basename(filepath))
                    return true
                end
            elseif endswith(lowercase(filepath), ".$e")
                return true
            end
        end
        return false
    end
    
    function matches_sensitive_name(filepath::String, names::Vector{String})
        return basename(filepath) in names
    end

    # Build manifest DataFrame if needed
    files_manifest = if !isnothing(pre_manifest)
        DataFrame(
            filepath = String[],
            extracted = Bool[],
            checked = Bool[],
            size_gb = Float64[]
        )
    else
        nothing
    end

    # Write clean paths to text file
    open(outfile, "w") do io
        # Scan extracted files (actual files on disk)
        for e in extensions
            s = rdir(pkg_path,"*.$e")
            if length(s) > 0
                for ss in s
                    println(io, ss)  # CLEAN PATH ONLY
                    push!(files, ss)
                    
                    # Add to manifest
                    if !isnothing(files_manifest)
                        push!(files_manifest, (
                            filepath = ss,
                            extracted = true,
                            checked = true,
                            size_gb = filesize(ss) / 1e9
                        ))
                    end
                end
            end
        end
        
        for fu in sensitivenames
            s = findfile(pkg_path, fu)
            if length(s) > 0
                for ss in s
                    println(io, ss)  # CLEAN PATH ONLY
                    push!(files, ss)
                    
                    if !isnothing(files_manifest)
                        push!(files_manifest, (
                            filepath = ss,
                            extracted = true,
                            checked = true,
                            size_gb = filesize(ss) / 1e9
                        ))
                    end
                end
            end
        end
        
        for fu in nonsensitivenames
            s = findfile(pkg_path, lowercase(fu), casesensitive = false)
            if length(s) > 0
                for ss in s
                    println(io, ss)  # CLEAN PATH ONLY
                    push!(files, ss)
                    
                    if !isnothing(files_manifest)
                        push!(files_manifest, (
                            filepath = ss,
                            extracted = true,
                            checked = true,
                            size_gb = filesize(ss) / 1e9
                        ))
                    end
                end
            end
        end
    end
    
    # Add non-extracted files to manifest and write CSV
    if !isnothing(pre_manifest)
        not_extracted = pre_manifest[.!pre_manifest.extracted, :]
        
        for row in eachrow(not_extracted)
            filepath = row.filepath
            
            # Check if this file matches the current kind
            is_match = false
            
            if matches_extension(filepath, extensions)
                is_match = true
            elseif matches_sensitive_name(filepath, sensitivenames)
                is_match = true
            end
            
            if is_match
                push!(files_manifest, (
                    filepath = filepath,
                    extracted = false,
                    checked = false,
                    size_gb = row.size_gb
                ))
            end
        end
        
        # Write manifest CSV
        CSV.write(manifest_file, files_manifest)
        @info "Classification manifest written: $manifest_file"
    end
    
    return files
end
