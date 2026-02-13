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
    classify_files(pkg_path::String, kind::String, fp::String; relpath = false)

Count how many files belong to each of code, data, documentation according to their file ending.

# Arguments
- `pkg_path`: path to (extracted) replication package
- `kind`: what kind of classification is desired: `code`, `data`, `docs`
- `fp`: output folder path

Outputs `txt` files into folder `fp` which will be created if needed.
"""
function classify_files(pkg_path::String, kind::String, fp::String; relpath = false)

     # write to `generated`
     mkpath(fp)

    sensitivenames = String[]
    nonsensitivenames = String[]
    files = String[]

    if kind == "code"
        extensions = ["ado","do","r","rmd","qmd","ox","m","py","nb","ipynb","sas","jl","f","f90","c","c++","sh","toml","yaml","yml","fs","fsx","tex","typst","sql", "jmd"]
        
        outfile = joinpath(fp,"program-files.txt")

        sensitivenames = ["Makefile"]

    elseif kind == "data"
        extensions = ["gpkg","dat","dta","rda","rds","rdata","ods","xls","xlsx","mat","csv","","txt","shp","xml","prj","dbf","sav","pkl","jld","jld2","gz","sas7bdat","rar","zip","7z","tar","tgz","bz2","xz","parquet", "json", "jsonl", "pickle"]

        outfile = joinpath(fp,"data-files.md")

    elseif kind == "docs"

        extensions = ["pdf","md","docx","doc","pages"]

        outfile = joinpath(fp,"documentation-files.txt")

    else 
        error("kind not found: choose `code`, `data`, `docs`")
    end

    open(outfile, "w") do io

        for e in extensions
            s = rdir(pkg_path,"*.$e")
            if length(s) > 0
                for ss in s
                    println(io, ss)
                    push!(files,ss)
                end
            end
        end
        for fu in sensitivenames
            s = findfile(pkg_path,fu)
            if length(s) > 0
                for ss in s
                    println(io, ss)
                    push!(files,ss)
                end
            end
        end
        for fu in nonsensitivenames
            s = findfile(pkg_path,lowercase(fu),casesensitive = false)
            if length(s) > 0
                for ss in s
                    println(io, ss)
                    push!(files,ss)
                end
            end
        end
    end
    return files
end
