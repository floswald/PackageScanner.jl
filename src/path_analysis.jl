# Path Analysis Module
# Functions for detecting and analyzing file paths in code

"""
    detect_path_kinds(line::String)

Detects all relevant path patterns in a line of code.
Returns tuple: (windows, unix, drive_letter)
"""
function detect_path_kinds(line::String)
    windows = is_windows_filepath(line)
    unix = is_unix_filepath(line)
    drive_letter = occursin(r"[A-Z]:\\\\*", line)
    return (windows, unix, drive_letter)
end

"""
    is_windows_filepath(line::String)

Find a Windows filepath, omitting various comment and command strings.
Looks for patterns like: this\\is\\123\\a\\path-yes\\1t\\is
"""
function is_windows_filepath(line::String)
    # Find all patterns like : this\is\123\a\path-yes\1t\is
    # but not \cmd{ (latex command), a \ b (right division operator), etc.
    # https://stackoverflow.com/a/31976060/1168848
    pat = r"^(?=.*[\w\-:]\\[\w\-]|.*[\w\-:]\\\\[\w\-])(?:(?!\\\w+{|^\\\w+ |\\\w+ | \\\w+ |[a-zA-Z] \\ [a-zA-Z]|[\<\>\|\?\*]|//).)*$"
    contains(line, pat)
end

"""
    is_unix_filepath(line::String)

Find a Unix filepath, omitting various comment and command strings.
Looks for patterns like: here/we/have/a_/1234/unix-1/path
"""
function is_unix_filepath(line::String)
    # Find all patterns like : here/we/have/a_/1234/unix-1/path
    # but not // or /* or */ (stata and C comments), a / b (division operator)
    pat = r"^(?=.*[\w/-]/[\w/-])(?:(?!//|/\*|\*/|[\<\>\"\|\?\*]|\w / \w).)*$"
    contains(line, pat)
end

"""
    hardcode_regex()

Regular expression for detecting hardcoded numeric constants.
"""
hardcode_regex() = r"\d{1,10}\.\d{3,10}"

"""
    check_file_paths(filepath)

Read each line of code and analyze. Looking for file paths and hardcoded numeric constants.
Returns: (lines, classification, has_drive, hardcodes)
"""
function check_file_paths(filepath)
    lines = String[]
    hardcodes = String[]
    has_windows = false
    has_unix = false
    has_drive = false

    try
        open(filepath, "r") do io
            for (i, line) in enumerate(eachline(io))
                windows, unix, drive = detect_path_kinds(line)
                if windows || unix
                    whichone = if windows & !unix
                            "windows"
                        elseif !windows & unix
                            "unix"
                        elseif windows & unix
                            "mixed"
                        end
                    push!(lines, @sprintf("Line %d, %s : %s", i, whichone, strip(line)))
                end
                has_windows |= windows
                has_unix |= unix
                has_drive |= drive

                if contains(line, hardcode_regex())
                    push!(hardcodes, @sprintf("Line %d, : %s", i, strip(line)))
                end
            end
        end
    catch e
        push!(lines, "⚠️ Error reading file: $e")
    end

    classification = if has_windows && has_unix
        "mixed"
    elseif has_windows
        "windows"
    elseif has_unix
        "unix"
    else
        "none"
    end

    return (lines, classification, has_drive, hardcodes)
end

"""
    path_splitter(path::String, at)

Split a path at a specific delimiter.
"""
path_splitter(path::String, at) = split(path, at, limit = 2)[end]

"""
    file_paths(files::Array, fp::String)

Takes an array of file paths, reads each associated file and checks its content for 
the existence of file paths of various kinds: windows `C:\\file\\paths\\like\\this` 
or unix `/paths/like/that`. Also searches for numeric constants which could be hardcoded results.

Outputs three markdown files into `fp` with partial reports.
"""
function file_paths(files::Array, fp::String)
    
    isdir(fp) || error("execute `classify_files()` first")

    output_file = joinpath(fp, "report-file-paths.md")

    # Run analysis
    results = Dict{String, Vector{String}}()
    hardcodes = Dict{String, Vector{String}}()
    stats = Dict("windows" => 0, "unix" => 0, "mixed" => 0, "drive" => 0)

    for file in files
        file = strip(file)
        lines, classification, has_drive, hardcoded = check_file_paths(file)
        if !isempty(lines)
            results[file] = lines
        end
        if !isempty(hardcoded)
            hardcodes[file] = hardcoded
        end
        if classification != "none"
            stats[classification] += 1
        end
        if has_drive
            stats["drive"] += 1
        end
    end

    total_files = length(files)

    # Write summary report
    open(output_file, "w") do io
        println(io, "### File Paths Report\n")
        println(io, "_Generated on $(Dates.now())_\n")

        println(io, 
        """
        **Warning**: Our search on file path types is imperfect and incurs both type 1 and type 2 errors. We aim to strike a reasonable balance between both. The below table is therefore only indicative. Detailed listings can be found in the appendix to this report.
        
        In this table we analyse all files which contain source code (not data and documentation), and we report the grand total of each type of filepath we encountered. 
        
        Please check and replace any `windows` filepaths with unix compliant paths, insofar as this is possible in your setup. (Notice that `STATA` allows `/` to be a filepath separator on a windows platform, hence this is a requirement for *all* `STATA` applications.)
        
        """)

        println(io, "| Files Analyzed | Windows Paths | Unix Paths | Mixed Paths | Drive Letters (`C:\\` etc) |")
        println(io, "|-------------|---------------------|------------------|-------------------|----------------------|")
        println(io, @sprintf("| %d | %d | %d | %d | %d |\n",
            total_files,
            stats["windows"],
            stats["unix"],
            stats["mixed"],
            stats["drive"]
        ))
    end

    splitat = basename(dirname(fp))

    # Write detailed file paths report
    open(joinpath(fp, "report-file-paths-detail.md"), "w") do io
        println(io, "## Filepaths Analysis Details\n")

        if isempty(results)
            println(io, "No file paths found.")
        else
            for (file, lines) in results
                println(io, "**$(path_splitter(file, splitat))**\n")
                for l in lines
                    println(io, "- ", l)
                end
                println(io)
            end
        end
    end

    # Write hardcoded numbers report
    open(joinpath(fp, "report-hardcoded-numbers.md"), "w") do io
        println(io, "## Potentially Hardcoded Numeric Constants\n")

        if isempty(hardcodes)
            println(io, "✅ No hardcoded numeric constants found.")
        else
            println(io, "\nWe found the following set of hard coded numbers. This may be completely legitimate (parameter input, thresholds for computations, etc), and is hence only for information.\n")
            for (file, lines) in hardcodes
                println(io, "**$(path_splitter(file, splitat))**\n")
                for l in lines
                    println(io, "- ", l)
                end
                println(io)
            end
        end
    end

    nothing
end
