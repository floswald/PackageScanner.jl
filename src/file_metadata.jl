# File Metadata Module
# Functions for analyzing file sizes, checksums, and duplicates

"""
    generate_file_sizes_md5(folder_path::String, output_path::String; large_size = 100)

Read entire package content and tabulate file sizes with file hash to check for duplicates.

# Arguments
- `folder_path`: Path to scan
- `output_path`: Where to write reports
- `large_size`: Threshold in MB for "large" files (default: 100)

Returns a DataFrame with file metadata.
"""
function generate_file_sizes_md5(folder_path::String, output_path::String; large_size = 100)

    table = DataFrame(name = [], name_slug = [], size = [], sizeMB = [], checksum = [])

    # Count and analyze all files
    for (root, _, files) in walkdir(folder_path)
        for file in files
            name = file
            file_path = joinpath(root, file)
            short_path = path_splitter(file_path, basename(folder_path))
            file_size = filesize(file_path)
            size_mb = file_size / 1024^2  # Convert bytes to megabytes
            md5_checksum = open(file_path, "r") do fio
                bytes2hex(sha1(fio))
            end
            push!(table, (name_slug = name, name = short_path, size = file_size, sizeMB = size_mb, checksum = md5_checksum))
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
