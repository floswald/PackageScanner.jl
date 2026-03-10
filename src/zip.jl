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

"bug workaround until https://github.com/JuliaLang/julia/pull/59662"
function mycp(src::AbstractString, dst::AbstractString; recursive::Bool = false, force::Bool=false)
    cmd = Sys.iswindows() ? `cmd /c copy` : `cp`
    force_option = Sys.iswindows() ? (force ? `/y` : `/-y`) : (force ? `-f` : `-n`)
    recursive_option = Sys.iswindows() ? (recursive ? `/r` : ``) : (recursive ? `-r` : ``)
    cmd = `$cmd $force_option`
    cmd = `$cmd $recursive_option`
    run(`$cmd $src $dst`)
end


"""
    create_manifest_from_zip(zip_path::String; size_threshold_gb=nothing, interactive=true)

Create a complete manifest of all files in a zip archive and extract only files below size threshold.

# Arguments
- `zip_path::String`: Path to zip file
- `size_threshold_gb::Union{Nothing,Float64}`: Size threshold in GB (default: prompt user or 2.0)
- `interactive::Bool`: Whether to prompt user for threshold (default: true)

# Returns
- `Tuple{DataFrame, String}`: (manifest, extraction_directory)
"""
function create_manifest_from_zip(zip_path::String; 
                                  size_threshold_gb::Union{Nothing,Number}=nothing,
                                  interactive::Bool=true)
    
    @info "Reading zip file metadata: $zip_path"
    reader = ZipFile.Reader(zip_path)
    
    # Calculate total size
    total_size_gb = sum(f.uncompressedsize for f in reader.files if !endswith(f.name, "/")) / 1e9
    
    # Interactive prompt (if enabled)
    if interactive
        println("\n" * "="^60)
        println("LARGE PACKAGE DETECTED")
        println("="^60)
        println("Full size of zip: $(round(total_size_gb, digits=2)) GB")
        
        if isnothing(size_threshold_gb)
            println("\nDefault: extract all files smaller than 2.0 GB")
            print("OK? (y/n): ")
            flush(stdout)
            response = readline()
            
            if lowercase(strip(response)) == "n"
                print("Enter size threshold in GB: ")
                flush(stdout)
                size_threshold_gb = parse(Float64, readline())
                println("Using threshold: $(size_threshold_gb) GB")
            else
                size_threshold_gb = 2.0
                println("Using default threshold: 2.0 GB")
            end
        else
            println("Using threshold: $(size_threshold_gb) GB")
        end
        println("="^60 * "\n")
    else
        size_threshold_gb = isnothing(size_threshold_gb) ? 2.0 : size_threshold_gb
        @info "Using size threshold: $(size_threshold_gb) GB"
    end
    
    size_threshold_bytes = size_threshold_gb * 1e9
    
    # Create full manifest DataFrame
    manifest = DataFrame(
        filepath = String[],
        size_bytes = Int64[],
        size_gb = Float64[],
        compressed_size = Int64[],
        crc32 = String[],
        extracted = Bool[],
        checked = Bool[],
        is_valid_file = Union{Bool, Missing}[]
    )
    
    # Track files to extract
    to_extract_names = String[]
    n_extracted = 0
    n_skipped = 0
    
    # Process each file in zip
    for zf in reader.files
        # Skip directories
        if endswith(zf.name, "/")
            continue
        end
        
        size_gb = zf.uncompressedsize / 1e9
        should_extract = zf.uncompressedsize <= size_threshold_bytes
        
        push!(manifest, (
            filepath = zf.name,
            size_bytes = zf.uncompressedsize,
            size_gb = size_gb,
            compressed_size = zf.compressedsize,
            crc32 = string(zf.crc32, base=16, pad=8),
            extracted = should_extract,
            checked = false,  # Will be updated during precheck
            is_valid_file = missing  # Will be validated after extraction
        ))
        
        if should_extract
            push!(to_extract_names, zf.name)
            n_extracted += 1
        else
            n_skipped += 1
        end
    end
    
    close(reader)
    
    @info "Manifest created: $(nrow(manifest)) files total"
    @info "  - Will extract: $n_extracted files"
    @info "  - Will skip: $n_skipped files (too large)"
    
    # Extract selected files
    extract_dir = joinpath(dirname(zip_path), "replication-package")
    
    if !isempty(to_extract_names)
        println("\nExtracting $(length(to_extract_names)) files...")
        
        # Use ZipFile.jl for programmatic extraction (more reliable than shell commands)
        reader = ZipFile.Reader(zip_path)
        try
            for fname in to_extract_names
                # Find file in zip
                zf_idx = findfirst(f -> f.name == fname, reader.files)
                if !isnothing(zf_idx)
                    file_in_zip = reader.files[zf_idx]
                    output_path = joinpath(extract_dir, fname)
                    
                    # Create parent directories
                    mkpath(dirname(output_path))
                    
                    # Extract file content
                    open(output_path, "w") do outfile
                        write(outfile, read(file_in_zip))
                    end
                end
            end
            @info "Extraction complete"
        catch e
            @error "Extraction failed: $e"
            rethrow(e)
        finally
            close(reader)
        end
        
        # Remove any .git directories
        if isdir(extract_dir)
            rm_git(extract_dir)
        end
        
        # Validate extracted files
        for i in 1:nrow(manifest)
            if manifest[i, :extracted]
                full_path = joinpath(extract_dir, manifest[i, :filepath])
                manifest[i, :is_valid_file] = isfile(full_path)
            else
                manifest[i, :is_valid_file] = missing  # Not extracted, unknown validity
            end
        end
    else
        @warn "No files to extract (all files exceed size threshold)"
        # Mark all as not extracted and unknown validity
        manifest[!, :is_valid_file] .= missing
    end
    
    return (manifest, extract_dir)
end

"""
    create_manifest_from_directory(dir_path::String; size_threshold_gb=nothing, interactive=true)

Create a complete manifest of all files in a directory and mark which should be checked based on size.

# Arguments
- `dir_path::String`: Path to directory
- `size_threshold_gb::Union{Nothing,Float64}`: Size threshold in GB (default: prompt user or 2.0)
- `interactive::Bool`: Whether to prompt user for threshold (default: true)

# Returns
- `DataFrame`: Manifest with all files and check status
"""
function create_manifest_from_directory(dir_path::String;
                                       size_threshold_gb::Union{Nothing,Number}=nothing,
                                       interactive::Bool=true)
    
    @info "Scanning directory: $dir_path"
    
    # Build initial manifest
    manifest = DataFrame(
        filepath = String[],
        size_bytes = Int64[],
        size_gb = Float64[],
        checksum = String[],
        extracted = Bool[],
        checked = Bool[],
        is_valid_file = Bool[]
    )
    
    total_size_gb = 0.0
    file_count = 0
    
    for (root, dirs, files) in walkdir(dir_path)
        for file in files
            full_path = joinpath(root, file)
            
            # Check if it's a valid regular file (not a broken symlink or special file)
            is_valid = isfile(full_path)
            
            if is_valid
                size = filesize(full_path)
                size_gb = size / 1e9
                total_size_gb += size_gb
                
                # Calculate checksum for valid files
                checksum = open(full_path, "r") do fio
                    bytes2hex(sha1(fio))
                end
            else
                # Invalid file - record but with placeholder values
                size = 0
                size_gb = 0.0
                checksum = "INVALID_FILE"
            end
            
            file_count += 1
            
            push!(manifest, (
                filepath = relpath(full_path, dir_path),
                size_bytes = size,
                size_gb = size_gb,
                checksum = checksum,
                extracted = true,  # Already extracted (it's a directory)
                checked = false,   # Will be set after applying filter
                is_valid_file = is_valid
            ))
        end
    end
    
    @info "Found $file_count files totaling $(round(total_size_gb, digits=2)) GB"
    
    # Interactive prompt for filtering
    if interactive
        println("\n" * "="^60)
        println("LARGE PACKAGE DETECTED")
        println("="^60)
        println("Package size: $(round(total_size_gb, digits=2)) GB")
        println("($(file_count) files)")
        
        if isnothing(size_threshold_gb)
            println("\nDefault: check only files smaller than 2.0 GB")
            println("(Larger files will be catalogued but not scanned)")
            print("OK? (y/n): ")
            flush(stdout)
            response = readline()
            
            if lowercase(strip(response)) == "n"
                print("Enter size threshold in GB: ")
                flush(stdout)
                size_threshold_gb = parse(Float64, readline())
                println("Using threshold: $(size_threshold_gb) GB")
            else
                size_threshold_gb = 2.0
                println("Using default threshold: 2.0 GB")
            end
        else
            println("Using threshold: $(size_threshold_gb) GB")
        end
        println("="^60 * "\n")
    else
        size_threshold_gb = isnothing(size_threshold_gb) ? 2.0 : size_threshold_gb
        @info "Using size threshold: $(size_threshold_gb) GB"
    end
    
    # Apply size filter
    size_threshold_bytes = size_threshold_gb * 1e9
    manifest.checked = manifest.size_bytes .<= size_threshold_bytes
    
    n_to_check = sum(manifest.checked)
    n_skip = file_count - n_to_check
    
    @info "Filtering applied:"
    @info "  - Will check: $n_to_check files"
    @info "  - Will skip: $n_skip files (too large)"
    
    return manifest
end

"""
    prepare_package_for_precheck(input_path::String; kwargs...)

Unified function that handles both zip files and directories.
Creates manifest and applies size filtering in both cases.

# Arguments
- `input_path::String`: Path to zip file or directory
- `size_threshold_gb::Union{Nothing,Float64}`: Size threshold in GB (default: prompt or 2.0)
- `interactive::Bool`: Whether to prompt user (default: true)

# Returns
- `Tuple{String, DataFrame}`: (package_directory, manifest)

# Examples
```julia
# Zip file with interactive prompt
pkg_dir, manifest = prepare_package_for_precheck("large.zip")

# Directory with fixed threshold
pkg_dir, manifest = prepare_package_for_precheck("/path/to/pkg", 
                                                  size_threshold_gb=1.5, 
                                                  interactive=false)
```
"""
function prepare_package_for_precheck(input_path::String; 
                                     size_threshold_gb::Union{Nothing,Number}=nothing,
                                     interactive::Bool=true)
    
    if isfile(input_path) && endswith(lowercase(input_path), ".zip")
        @info "Input is a zip file"
        manifest, extract_dir = create_manifest_from_zip(
            input_path, 
            size_threshold_gb=size_threshold_gb,
            interactive=interactive
        )
        return (extract_dir, manifest)
        
    elseif isdir(input_path)
        @info "Input is a directory"
        manifest = create_manifest_from_directory(
            input_path,
            size_threshold_gb=size_threshold_gb,
            interactive=interactive
        )
        return (input_path, manifest)
        
    else
        error("Input must be a .zip file or existing directory: $input_path")
    end
end
