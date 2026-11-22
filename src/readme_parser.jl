# README Parser Module
# Functions for reading and analyzing README files

"""
    get_pdf_text(src::String) -> String

Extract text from a PDF file via PyMuPDF (`pymupdf`, imported as `pymupdf` --
not the deprecated `fitz` alias), called through `PyCall`. Returns the
concatenated per-page text, in reading order, joined by newlines.

PyMuPDF is used instead of PDFIO.jl because its text extraction is
layout-aware: on two-column academic PDFs, PDFIO frequently interleaves the
two columns mid-sentence, while PyMuPDF's `get_text("text")` follows the
page's actual reading order.
"""
function get_pdf_text(src::String)
    isfile(src) || error("PDF file not found: $src")
    pymupdf = pyimport("pymupdf")
    doc = pymupdf.open(src)
    try
        return join((doc.load_page(i).get_text("text") for i in 0:(length(doc) - 1)), "\n")
    finally
        doc.close()
    end
end

"""
    read_README(pkg_loc, fp::String)

Find the README in the package and read from either `.md` or `.pdf` format. 
Then produce a report with mentions of interesting terms like software used, 
whether confidential, etc.

# Arguments
- `pkg_loc`: Package location
- `fp`: Output folder path
"""
function read_README(pkg_loc, fp::String)

    doclist = joinpath(fp, "documentation-files.txt")
    isfile(doclist) || error("the file $doclist must exist")

    searches = ["confidential", "proprietary", "not available", "restricted", "HPC", "intensive", "IPUMS", "LEHD", "Statistics Norway", "Census", "IRB", "FDZ", "IAB", "RDC", "Statistics Sweden", "CASD", "VisitINPS", "THEOPS", "experiment", "seed", "identifiable"]
    
    d0 = readlines(doclist)
    is_readmes = occursin.(r"README"i, d0)

    open(joinpath(fp, "report-readme.md"), "w") do io
        println(io, "### `README` Analysis\n")
        if length(d0) == 0 || !any(is_readmes)
            println(io, "🚨 **No `README` found!** 🚨")
            println(io, "The package **must** contain either `README.md` or `README.pdf`. This file needs to be placed at the root of your replication package. Please fix.")
        else
            # Take first match
            d = first(d0[is_readmes])
            
            # Check if file is accessible
            if !isfile(d)
                println(io, "🚨 **README file not accessible!** 🚨")
                println(io, "The README file listed at `$d` cannot be read (broken symlink or special file).")
                println(io, "**Please fix.**")
                return 1
            end
            
            println(io, """
            👉 We are considering the file at 

            ```
            $d 
            ```
            to be the relevant `README`.\n
            """)

            if dirname(d) != pkg_loc
                println(io, 
                """**Wrong `README` location warning:**
                
                The `README` file needs to be placed at the root of your replication package. **Please fix.**
                """)
            end

            println(io, """
            #### Keyword search

            👉 We searched the readme for keywords to help the reproducibility team. This is only for internal use. 

            _Replicator_: The line numbers refer to the readme file printed above.

            """)

            if contains(d, r".md"i)
                open(d, "r") do jo 
                    for s in searches
                        for (i, line) in enumerate(eachline(jo))
                            if occursin(Regex(s, "i"), line)
                                println(io, @sprintf("Line %d : %s", i, strip(line)))
                            end
                        end
                    end
                end
            elseif contains(d, r".pdf"i)
                text = try
                    get_pdf_text(d)
                catch e
                    println(io, "README.PDF text extraction failed with error $e")
                    return 1
                end
                for (i, line) in enumerate(split(text, "\n"))
                    for s in searches
                        if occursin(Regex(s, "i"), line)
                            println(io, @sprintf("Line %d : %s", i, strip(line)))
                        end
                    end
                end
            end
        end
    end
    @info "README analysis done."
end
