# Precheck Module
# Main orchestration function for package analysis

"""
    precheck_package(pkg_loc::String)

Comprehensive check of a replication package in directory `pkg_loc`.

It is assumed that `pkg_loc` is descendant in a directory structure of this kind, 
i.e. what is implemented in https://github.com/JPE-Reproducibility/JPEtemplate

In this example, `pkg_loc = abspath(replication-package)`:

```
.
├── generated
├── images
├── LICENSE
├── replication-package
├── package-output-map.xlsx
├── README.md
└── TEMPLATE.qmd
```

# Arguments
- `pkg_loc`: Path to the replication package directory

# Performs
1. File classification (code/data/docs)
2. File metadata analysis (sizes, checksums, duplicates)
3. Code line counting (via cloc)
4. File path analysis in code files
5. PII detection in data and code files
6. README analysis

All reports are written to `generated/` folder at the package root.
"""
function precheck_package(pkg_loc::String)

    pkg_root = joinpath(pkg_loc, "..")
    @info "Starting precheck of package $(basename(pkg_root))"

    out = joinpath(pkg_root, "generated")
    mkpath(out)

    # Make package manifest table
    @info "Generate package manifest: all files, sizes, md5 hash"
    generate_file_sizes_md5(pkg_loc, out)

    # Classify all files
    @info "Classify each file as code/data/docs"
    codefiles = classify_files(pkg_loc, "code", out)
    datafiles = classify_files(pkg_loc, "data", out)
    docsfiles = classify_files(pkg_loc, "docs", out)

    # Run cloc to get line counts
    @info "Running cloc for code statistics"
    try
        cloc = read(run(`cloc --md --quiet --out=$(joinpath(out, "report-cloc.md")) $pkg_loc`))
        @info "Printing cloc output"

        open(joinpath(out, "report-cloc.md")) do IO
            for i in eachline(IO)
                println(i)
            end
        end
    catch e
        @warn "cloc command failed or not available: $e"
        # Create a placeholder file
        open(joinpath(out, "report-cloc.md"), "w") do io
            println(io, "### Code Statistics\n")
            println(io, "⚠️ cloc command not available or failed to run.\n")
            println(io, "Install cloc for detailed code statistics: https://github.com/AlDanial/cloc")
        end
    end

    # Check file paths in code files
    @info "Parse code files and search for filepaths"
    file_paths(codefiles, out)

    # Look for PII
    @info "Look for PII in data and code files"
    data_matches = scan_data_files(datafiles)
    code_matches = scan_code_files(codefiles)
    write_pii_report(data_matches, code_matches, out, splitat = dirname(pkg_loc))

    # Parse README
    @info "Read the README file"
    read_README(pkg_loc, out)

    @info "Precheck done. Reports written to $out"

end

# Testing and helper functions

"""
    create_example_package(at_root::String)

Create an example test package structure for testing purposes.
"""
function create_example_package(at_root::String)

    pkg = joinpath(at_root, "replication-package")
    mkpath(pkg)
    
    mkpath(joinpath(pkg, "data"))
    mkpath(joinpath(pkg, "code"))
    mkpath(joinpath(pkg, "output"))
    
    # Create data content
    ipath = joinpath(pkgdir(DataFrames), "docs", "src", "assets", "iris.csv")
    cp(ipath, joinpath(pkg, "data", "iris.csv"), force = true)

    # Create code content
    Pkg.generate(joinpath(pkg, "code", "Oswald.jl"))

    # Fill with more stuff
    open(joinpath(pkg, "code", "Oswald.jl", "src", "code.jl"), "w") do io
        println(io, "func2() = raw\"my/file/path\\\\mixed\"")
        println(io, "func3() = raw\"C:\\\\my\\\\file\"")
        println(io, "func4() = 1 + 1 + 14")
    end
    open(joinpath(pkg, "code", "Oswald.jl", "src", "code2.jl"), "w") do io
        println(io, "func4() = 1 + 1 + 14")
        println(io, "func4() = rand()")
        println(io, "func5() = raw\"X:\\\\my\"")
        println(io, "func6() = \"path/to/file\"")
        println(io, "func4() = 1 + 1 + 14")
    end

    open(joinpath(pkg, "code", "Makefile"), "w") do io 
        println(io, "default:")
    end

    # Create a readme
    open(joinpath(pkg, "README.md"), "w") do io
        println(io, "# Replication Package - TEST PACKAGE")
        println(io, "\nIn this package you will find code, data and output for the test package. Have fun! ✌️")
        println(io, "\nAs you can see, there is a lot of important info missing. Checkout [our readme](https://www.templatereadme.org) generator and our dedicated [website](https://jpedataeditor.github.io/) for more info.")
    end
    @info "Example package created at $pkg"

end
