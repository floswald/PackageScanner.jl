# Data Dependency Audit Module
#
# Cross-references data files present in a replication package against the code
# files, to determine which code file(s) (if any) reference each data file.
#
# This is deliberately language-agnostic: instead of parsing per-language loader
# syntax (`read_csv`, `haven::read_dta`, `pd.read_stata`, ...), it reverse-indexes
# each data file's name as a plain-text token against every code file. Any
# language that loads a local file passes its name as a string literal somewhere,
# so this covers all languages present in the package without enumerating loader
# function names.

"""
    is_word_char(c::Char)

A character that can be part of an identifier/filename token (letters, digits, underscore).
Used to check word-boundaries around a matched filename token, so that e.g. a short
stem like `"data"` does not match inside an unrelated longer word.
"""
is_word_char(c::Char) = isletter(c) || isdigit(c) || c == '_'

"""
    token_occurs(token::AbstractString, text::AbstractString)

Check whether `token` occurs in `text` as a whole, word-bounded match (not merely
as a substring of a longer token). Dots and other non-word characters in `token`
(as in a filename like `survey.dta`) are matched literally.
"""
function token_occurs(token::AbstractString, text::AbstractString)
    isempty(token) && return false
    start = firstindex(text)
    while true
        rng = findnext(token, text, start)
        isnothing(rng) && return false
        i, j = first(rng), last(rng)
        before_ok = i == firstindex(text) || !is_word_char(text[prevind(text, i)])
        after_ok = j == lastindex(text) || !is_word_char(text[nextind(text, j)])
        before_ok && after_ok && return true
        start = nextind(text, i)
    end
end

"""
    data_file_tokens(datafile::AbstractString; min_stem_length = 3)

Candidate search tokens for a data file: its basename (with extension) always,
and its filename stem (without extension) only if at least `min_stem_length`
characters long, to avoid false positives from very short stems.
"""
function data_file_tokens(datafile::AbstractString; min_stem_length::Int = 3)
    fname = basename(datafile)
    stem, _ = splitext(fname)
    tokens = [fname]
    if length(stem) >= min_stem_length && stem != fname
        push!(tokens, stem)
    end
    return tokens
end

"""
    data_dependency_audit(datafiles::Array, codefiles::Array, fp::String; min_stem_length = 3)

For each file in `datafiles`, search every file in `codefiles` for a word-bounded
occurrence of that data file's basename or stem. Writes `report-data-dependencies.md`
into `fp`.

# Arguments
- `datafiles`: paths to data files, as returned by `classify_files(pkg_loc, "data", fp)`
- `codefiles`: paths to code files, as returned by `classify_files(pkg_loc, "code", fp)`
- `fp`: output folder path (must already exist, i.e. `classify_files` ran first)
- `min_stem_length`: minimum stem length to use as a search token (default 3)

# Returns
`Dict{String, Vector{String}}` mapping each data file to the list of code files
that reference it. An empty vector means the data file is an orphan: present in
the package but no code reference to it was found.

# Known limitations
Static string matching cannot catch filenames built dynamically at runtime
(e.g. `paste0(dir, year, ".csv")`, glob loops, `file.path(...)`), nor files
fetched from a URL rather than loaded from a local path already in the package.
"""
function data_dependency_audit(datafiles::Array, codefiles::Array, fp::String; min_stem_length::Int = 3)
    isdir(fp) || error("execute `classify_files()` first")

    output_file = joinpath(fp, "report-data-dependencies.md")

    # Read each code file once
    code_contents = Dict{String, String}()
    for cf in codefiles
        code_contents[cf] = try
            read(cf, String)
        catch e
            @warn "could not read code file $cf: $e"
            ""
        end
    end

    references = Dict{String, Vector{String}}()

    for df in datafiles
        tokens = data_file_tokens(df; min_stem_length = min_stem_length)
        hits = String[]
        for (cf, content) in code_contents
            if any(t -> token_occurs(t, content), tokens)
                push!(hits, cf)
            end
        end
        references[df] = sort(hits)
    end

    n_total = length(references)
    orphans = [df for (df, hits) in references if isempty(hits)]
    n_orphans = length(orphans)

    splitat = basename(dirname(fp))

    open(output_file, "w") do io
        println(io, "### Data Dependency Audit\n")
        println(io, "_Generated on $(Dates.now())_\n")
        println(io,
        """
        **Warning**: this audit is a static string search (data file name as a word-bounded
        token in the code text), not a trace of actual data loading. It cannot catch filenames
        built dynamically at runtime, or data fetched from a URL rather than a local path. Treat
        it as a lead for manual review, not as ground truth.

        """)
        println(io, "| Data files | Referenced by code | Orphans (no code reference found) |")
        println(io, "|------------|---------------------|-------------------------------------|")
        println(io, "| $n_total | $(n_total - n_orphans) | $n_orphans |\n")

        println(io, "#### Detail\n")
        for df in sort(collect(keys(references)))
            hits = references[df]
            println(io, "**$(path_splitter(df, splitat))**\n")
            if isempty(hits)
                println(io, "- ⚠️ ORPHAN: no code reference found")
            else
                for cf in hits
                    println(io, "- referenced by `$(path_splitter(cf, splitat))`")
                end
            end
            println(io)
        end
    end

    return references
end
