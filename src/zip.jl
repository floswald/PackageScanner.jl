"""
    read_and_unzip_directory(dir_path::String)

Read contents of a directory and unzip any .zip files using system unzip command.
Extracts zip files to the same directory where they reside.

# Arguments
- `dir_path::String`: Path to the directory to read

# Returns
- `Vector{String}`: All file paths in the directory (after unzipping)
"""
function read_and_unzip_directory(dir_path::String; rm_zip = true)
    # Check if directory exists
    if !isdir(dir_path)
        throw(ArgumentError("Directory does not exist: $dir_path"))
    end
    
    # Get all files in directory
    files = filter(isfile, readdir(dir_path, join=true))
    
    # Find zip files
    zip_files = filter(f -> endswith(lowercase(f), ".zip"), files)

    if length(zip_files) == 0
        @warn "There are no zip files in this location. Probably file request has not downloaded yet to local machine. Check dropbox sync and wait a few minutes."
        println("seeing this right now in this location:")
        println(files)
    end
    
    # Unzip each zip file
    for zip_file in zip_files
        println("Unzipping: $(basename(zip_file))")
        
        # Run system unzip command
        # -o: overwrite files without prompting
        # -d: extract to directory (same as zip file location)
        extract_dir = joinpath(dirname(dirname(zip_file)), "replication-package")
        run(pipeline(`unzip -oq $zip_file -d $extract_dir`, devnull))
        
        # Remove any .git directories from extracted contents
        if isdir(extract_dir)
            rm_git(extract_dir)
        end
    end

    if rm_zip
        rm.(zip_files, force = true)
    end


    
    # Return all files in directory after unzipping
    return filter(isfile, readdir(dir_path, join=true))
end

function rm_git(extract_dir)
    for (root, dirs, files) in walkdir(extract_dir)
        if ".git" in dirs
            git_path = joinpath(root, ".git")
            @info "Removing git repository: $git_path"
            rm(git_path, recursive=true, force=true)
            # Remove from dirs to prevent walkdir from trying to enter it
            filter!(d -> d != ".git", dirs)
            # stop immediately after deleting the .git
            return 0
        end
    end
end