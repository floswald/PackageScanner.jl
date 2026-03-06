# File Metadata Module
# Functions for analyzing file sizes, checksums, and duplicates

"""
    generate_file_sizes_md5(folder_path::String, output_path::String; large_size = 100, pre_manifest=nothing)

Read entire package content and tabulate file sizes with file hash to check for duplicates.

# Arguments
- `folder_path`: Path to scan
- `output_path`: Where to write reports
- `large_size`: Threshold in MB for "large" files (default: 100)
- `pre_manifest`: Optional pre-generated manifest from zip inspection (includes non-extracted files)

Returns a DataFrame with file metadata.
"""
function generate_file_sizes_md5(folder_path::String, output_path::String; 
                                 large_size = 100, 
                                 pre_manifest::Union{Nothing,DataFrame}=nothing)

    table = DataFrame(name = [], name_slug = [], size = [], sizeMB = [], checksum = [], extracted = [], checked = [])

    # If pre_manifest provided, use it as base and add extracted files
    if !isnothing(pre_manifest)
        # Start with pre_manifest
        for row in eachrow(pre_manifest)
            push!(table, (
                name_slug = basename(row.filepath),
                name = row.filepath,
                size = row.size_bytes,
                sizeMB = row.size_gb * 1024,  # Convert GB to MB
                checksum = get(row, :checksum, get(row, :crc32, "")),
                extracted = row.extracted,
                checked = row.checked
            ))
        end
        
        # Update checksums for extracted files
        for i in 1:nrow(table)
            if table[i, :extracted]
                file_path = joinpath(folder_path, table[i, :name])
                if isfile(file_path)
                    table[i, :checksum] = isfile(file_path) && open(file_path, "r") do fio
                        bytes2hex(sha1(fio))
                    end
                end
            end
        end
    else
        # Original behavior: scan directory
        for (root, _, files) in walkdir(folder_path)
            for file in files
                name = file
                file_path = joinpath(root, file)
                short_path = path_splitter(file_path, basename(folder_path))
                file_size = filesize(file_path)
                size_mb = file_size / 1024^2  # Convert bytes to megabytes
                md5_checksum = isfile(file_path) && open(file_path, "r") do fio
                    bytes2hex(sha1(fio))
                end
                push!(table, (
                    name_slug = name, 
                    name = short_path, 
                    size = file_size, 
                    sizeMB = size_mb, 
                    checksum = md5_checksum,
                    extracted = true,
                    checked = false
                ))
            end
        end
    end
    
    sort!(table, [:size])

    duplicates = nrow(table) - length(unique(table.checksum))
    zeross = sum(table.size .== 0)
    largefs = sum(table.sizeMB .>= large_size)
    
    # Main file sizes report
    open(joinpath(output_path, "report-file-sizes.md"), "w") do io

        println(io, """
        ## File Size and Identity Report

        **Summary:**

        The package contains:

        * $(nrow(table)) files
        """)

        println(io, duplicates > 0 ? "* $(duplicates) Duplicate files" : "* $(duplicates) Duplicate files")
        println(io, largefs > 0 ? "* $(largefs) Files larger than $(large_size)MB" : "* No files larger than $(large_size)MB")
        println(io, zeross > 0 ? "* $(zeross) files of size 0Kb" : "* No zero sized (0Kb) files")

        # Write Markdown table header
        println(io, "\n")
        write(io, "| Filename | Size (MB) | Checksum (MD5) |\n")
        write(io, "|:---------|----------:|:--------------|\n")

        for ir in eachrow(table)
            write(io, "| $(ir.name) | $(round(ir.sizeMB, digits=2)) | $(ir.checksum) |\n")
        end
    end
    
    # Duplicates report
    open(joinpath(output_path, "report-duplicates.md"), "w") do io

        println(io, """
        ### Duplicate Files Report
        """)

        if duplicates > 0
            
            println(io, "We found the following duplicate files:\n")

            # Write Markdown table header
            write(io, "| Filename | Size (MB) | Checksum (MD5) |\n")
            write(io, "|:---------|----------:|:--------------|\n")
            for ir in eachrow(table[nonunique(table, :checksum), :])
                write(io, "| $(ir.name) | $(round(ir.sizeMB, digits=2)) | $(ir.checksum) |\n")
            end
        else
            println(io, "We did not find any duplicate files.")
        end
    end

    # Zero size files report
    open(joinpath(output_path, "report-zero-files.md"), "w") do io

        println(io, """
        ### Zero Size Files Report
        """)

        if zeross > 0
            println(io, "We found the following zero size files:\n")
            # Write Markdown table header
            write(io, "| Filename | Size (MB) | Checksum (MD5) |\n")
            write(io, "|:---------|----------:|:--------------|\n")
            for ir in eachrow(table[table.size .== 0, :])
                write(io, "| $(ir.name) | $(round(ir.size, digits=2)) | $(ir.checksum) |\n")
            end
        else
            println(io, "We did not find any zero sized files.\n")
        end
    end

    # Large files report
    open(joinpath(output_path, "report-large-files.md"), "w") do io
        println(io, """
        ### Large Files Report
        """)
        if largefs > 0
            println(io, "We found the following files larger than $(large_size)MB:\n")

            @info "there are files larger than $large_size MB"
            # Write Markdown table header
            write(io, "| Filename | Size (MB)  |\n")
            write(io, "|:---------|----------:|\n")
            for ir in eachrow(table[table.sizeMB .> large_size, :])
                write(io, "| $(ir.name) | $(round(ir.sizeMB, digits=2))|\n")
            end
        else
            println(io, "We did not find any files larger than $(large_size)MB.\n")
        end
    end

    return table
end

"""
    write_extraction_summary(manifest::DataFrame, output_path::String)

Write a summary report about which files were extracted/checked vs catalogued only.

# Arguments
- `manifest::DataFrame`: Manifest with extraction and check status
- `output_path::String`: Directory to write report to
"""
function write_extraction_summary(manifest::DataFrame, output_path::String)
    open(joinpath(output_path, "report-extraction-summary.md"), "w") do io
        n_total = nrow(manifest)
        n_extracted = sum(manifest.extracted)
        n_skipped = n_total - n_extracted
        
        total_size_gb = sum(manifest.size_gb)
        extracted_size_gb = sum(manifest[manifest.extracted, :size_gb])
        skipped_size_gb = total_size_gb - extracted_size_gb
        
        println(io, "## Extraction Summary\n")
        println(io, "This package was processed with **selective extraction** due to its large size.\n")
        println(io, "**Package Statistics:**\n")
        println(io, "- Total files in package: **$n_total**")
        println(io, "- Files extracted and checked: **$n_extracted**")
        println(io, "- Files catalogued but not checked: **$n_skipped**")
        println(io, "- Total package size: **$(round(total_size_gb, digits=2)) GB**")
        println(io, "- Size extracted: **$(round(extracted_size_gb, digits=2)) GB**")
        println(io, "- Size not extracted: **$(round(skipped_size_gb, digits=2)) GB**\n")
        
        if n_skipped > 0
            println(io, "### Files Not Extracted\n")
            println(io, "The following files were catalogued but not extracted due to size constraints:\n")
            println(io, "| File | Size (GB) | Reason |")
            println(io, "|:-----|----------:|:-------|")
            
            skipped = manifest[.!manifest.extracted, :]
            sort!(skipped, :size_gb, rev=true)
            
            for row in eachrow(skipped)
                println(io, "| $(row.filepath) | $(round(row.size_gb, digits=2)) | Exceeds threshold |")
            end
            
            println(io, "\n**Note:** These files are included in the file manifest but were not scanned for PII or other checks.")
        end
    end
    
    @info "Extraction summary written to $(joinpath(output_path, "report-extraction-summary.md"))"
end

"""
    write_illegal_files_report(manifest::DataFrame, output_path::String)

Generate a report of files that are not valid regular files (broken symlinks, special files, etc.)

# Arguments
- `manifest::DataFrame`: Manifest with is_valid_file column
- `output_path::String`: Directory to write report to
"""
function write_illegal_files_report(manifest::DataFrame, output_path::String)
    if !("is_valid_file" in names(manifest))
        @warn "Manifest missing is_valid_file column, skipping illegal files report"
        return
    end
    
    open(joinpath(output_path, "report-illegal-files.md"), "w") do io
        println(io, "## Invalid/Illegal Files Report\n")
        
        # Count invalid files (excluding missing values)
        invalid_files = manifest[coalesce.(manifest.is_valid_file, true) .== false, :]
        n_invalid = nrow(invalid_files)
        
        if n_invalid == 0
            println(io, "✅ **All files are valid regular files.**\n")
            println(io, "No broken symlinks or special files detected.")
        else
            println(io, "⚠️ **Found $n_invalid invalid file(s)**\n")
            println(io, "The following files exist in the package manifest but cannot be read as regular files.")
            println(io, "This typically indicates:")
            println(io, "- Broken symbolic links")
            println(io, "- Special device files")
            println(io, "- Files with permission issues\n")
            
            println(io, "| File Path | Size (bytes) | Extracted |")
            println(io, "|:----------|-------------:|:----------|")
            
            for row in eachrow(invalid_files)
                extracted_status = get(row, :extracted, missing)
                extracted_str = ismissing(extracted_status) ? "N/A" : (extracted_status ? "Yes" : "No")
                println(io, "| $(row.filepath) | $(row.size_bytes) | $extracted_str |")
            end
            
            println(io, "\n**Recommendation:** These files should be removed or fixed in your replication package.")
        end
    end
    
    @info "Illegal files report written to $(joinpath(output_path, "report-illegal-files.md"))"
end
