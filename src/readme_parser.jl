# README Parser Module
# Functions for reading and analyzing README files

"""
    getPDFText(src, out) -> Dict 

Extract text from a PDF file.

# Arguments
- `src`: Input PDF file path from where text is to be extracted
- `out`: Output TXT file path where the output will be written

Returns a dictionary containing metadata of the document.
"""
function getPDFText(src, out)
    # Handle that can be used for subsequent operations on the document
    doc = pdDocOpen(src)
    
    # Metadata extracted from the PDF document
    # This value is retained and returned as the return from the function
    docinfo = pdDocGetInfo(doc) 
    open(out, "w") do io
    
        # Returns number of pages in the document       
        npage = pdDocGetPageCount(doc)

        for i = 1:npage
        
            # Handle to the specific page given the number index
            page = pdDocGetPage(doc, i)
            
            # Extract text from the page and write it to the output file
            pdPageExtractText(io, page)

        end
    end
    # Close the document handle
    # The doc handle should not be used after this call
    pdDocClose(doc)
    return docinfo
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
                tmpfile = joinpath(fp, "temp.txt")
                try
                    z = getPDFText(d, tmpfile)
                catch e
                    println(io, "README.PDF text extraction failed with error $e")
                    return 1
                end
                open(tmpfile, "r") do jo 
                    for (i, line) in enumerate(eachline(jo))
                        for s in searches
                            if occursin(Regex(s, "i"), line)
                                println(io, @sprintf("Line %d : %s", i, strip(line)))
                            end
                        end
                    end
                end
            end
        end
    end
    @info "README analysis done."
end
