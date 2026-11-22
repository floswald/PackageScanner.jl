# README Structure Audit Module
#
# Stage B of the paper-vs-code/data crosscheck (JPE-Reproducibility/JPE.jl#29):
# required-section presence/absence, and per-data-source citation metadata.
# Deterministic, no LLM. Complements (does not replace) `read_README`'s
# flat keyword search.

"""
    README_REQUIRED_SECTIONS

Required sections for a replication package README, each mapped to a
case-insensitive regex used to detect its presence by header or keyword
proximity. Based on JPE-Reproducibility/PackageScanner.jl#7.
"""
const README_REQUIRED_SECTIONS = [
    "Data availability / sources"      => r"data\s+(availability|sources?)|where.*(the )?data.*(from|obtained)"i,
    "Software requirements"            => r"software\s+(requirements?|dependencies)|\brequirements\.txt\b|\benvironment\.ya?ml\b|\bdepend(ency|encies)\b"i,
    "Reproduction instructions"        => r"(instructions?|how)\s+to\s+(reproduce|run|replicate)|getting\s+started|reproduc(e|ing)\s+(the\s+)?results?"i,
    "Computational requirements"       => r"computational\s+requirements?|\bruntime\b|hardware\s+requirements?|memory\s+requirements?|expected\s+run\s*time"i,
    "License / terms of use"           => r"\blicense\b|terms\s+of\s+use"i,
]

"""
    README_URL_DOI_REGEX, README_ACCESS_DATE_REGEX

Patterns used by `readme_data_citations` to flag whether a data source
mention is accompanied by citation metadata.
"""
const README_URL_DOI_REGEX = r"https?://\S+|\b10\.\d{4,9}/\S+"
const README_ACCESS_DATE_REGEX = r"(accessed|retrieved|downloaded)\b[^.\n]{0,60}?(\d{4}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})"i

"""
    readme_section_checklist(readme_text::AbstractString)

For each entry of `README_REQUIRED_SECTIONS`, find the first matching line.

Returns a `Vector{Tuple{String, Union{Int,Nothing}}}` of `(section_name, line_number)`
pairs, in the same order as `README_REQUIRED_SECTIONS`; `line_number` is `nothing`
if the section was not found.
"""
function readme_section_checklist(readme_text::AbstractString)
    lines = split(readme_text, '\n')
    results = Tuple{String, Union{Int,Nothing}}[]
    for (section, pat) in README_REQUIRED_SECTIONS
        hit = findfirst(l -> occursin(pat, l), lines)
        push!(results, (section, hit))
    end
    return results
end

"""
    readme_data_citations(readme_text::AbstractString, datafiles::Array; window = 2, min_stem_length = 3)

For each file in `datafiles`, check whether the README mentions it (by basename
or stem, reusing `data_file_tokens`/`token_occurs` from the data dependency
audit), and if so whether a URL/DOI and an access date are present within
`window` lines of the first mention.

Returns a `Vector{NamedTuple}` with fields `datafile`, `mentioned`, `has_url_or_doi`,
`has_access_date` — one row per data file.
"""
function readme_data_citations(readme_text::AbstractString, datafiles::Array; window::Int = 2, min_stem_length::Int = 3)
    lines = split(readme_text, '\n')
    results = NamedTuple[]

    for df in datafiles
        tokens = data_file_tokens(df; min_stem_length = min_stem_length)
        hit = findfirst(l -> any(t -> token_occurs(t, l), tokens), lines)

        if isnothing(hit)
            push!(results, (datafile = df, mentioned = false, has_url_or_doi = false, has_access_date = false))
            continue
        end

        lo = max(1, hit - window)
        hi = min(length(lines), hit + window)
        context = join(lines[lo:hi], '\n')

        push!(results, (
            datafile = df,
            mentioned = true,
            has_url_or_doi = occursin(README_URL_DOI_REGEX, context),
            has_access_date = occursin(README_ACCESS_DATE_REGEX, context),
        ))
    end

    return results
end

"""
    readme_structure_audit(pkg_loc::String, datafiles::Array, fp::String)

Find the README in `fp`'s sibling `documentation-files.txt` manifest (as written
by `classify_files(pkg_loc, "docs", fp)`), run the section checklist and
data-citation audit against it, and write `report-readme-structure.md` into `fp`.

Only handles `.md` READMEs directly (PDF extraction is left to `read_README`'s
existing `getPDFText` fallback, out of scope here per JPE-Reproducibility/JPE.jl#29).

Returns `nothing` if no markdown README was found (still writes a report noting this).
"""
function readme_structure_audit(pkg_loc::String, datafiles::Array, fp::String)
    doclist = joinpath(fp, "documentation-files.txt")
    isfile(doclist) || error("the file $doclist must exist")

    output_file = joinpath(fp, "report-readme-structure.md")
    d0 = readlines(doclist)

    open(output_file, "w") do io
        println(io, "### README Structure Audit\n")
        println(io, "_Generated on $(Dates.now())_\n")

        readme_candidates = d0[occursin.(r"README"i, d0) .& .!occursin.(r"\.pdf$"i, d0)]

        if isempty(readme_candidates)
            println(io, "🚨 No markdown `README` found (or only a PDF `README` is present — structural audit here only covers markdown; see `report-readme.md` for the PDF keyword search).")
            return nothing
        end

        d = first(readme_candidates)
        if !isfile(d)
            println(io, "🚨 README file listed at `$d` is not accessible.")
            return nothing
        end

        text = read(d, String)

        println(io, "#### Required Section Checklist\n")
        checklist = readme_section_checklist(text)
        for (section, line) in checklist
            if isnothing(line)
                println(io, "- ❌ $section: not found")
            else
                println(io, "- ✅ $section: mentioned on line $line")
            end
        end
        println(io)

        println(io, "#### Data Source Citation Coverage\n")
        println(io,
        """
        For each data file present in the package, we check whether the README mentions
        it by name, and if so whether a URL/DOI and an access date appear nearby. This is
        a static text-proximity check, not a trace of actual provenance — treat gaps as a
        lead for manual review.

        """)

        if isempty(datafiles)
            println(io, "No data files to check (data manifest was empty).")
        else
            citations = readme_data_citations(text, datafiles)
            n_mentioned = count(c -> c.mentioned, citations)
            n_cited = count(c -> c.mentioned && c.has_url_or_doi, citations)
            n_dated = count(c -> c.mentioned && c.has_access_date, citations)

            println(io, "| Data files | Mentioned in README | Has URL/DOI nearby | Has access date nearby |")
            println(io, "|------------|----------------------|---------------------|--------------------------|")
            println(io, "| $(length(citations)) | $n_mentioned | $n_cited | $n_dated |\n")

            splitat = basename(pkg_loc)
            for c in citations
                label = replace(c.datafile, pkg_loc => "", count = 1)
                if !c.mentioned
                    println(io, "- ⚠️ `$label`: not mentioned in README")
                elseif !c.has_url_or_doi || !c.has_access_date
                    missing_bits = String[]
                    c.has_url_or_doi || push!(missing_bits, "URL/DOI")
                    c.has_access_date || push!(missing_bits, "access date")
                    println(io, "- ⚠️ `$label`: mentioned, but missing $(join(missing_bits, " and "))")
                else
                    println(io, "- ✅ `$label`: mentioned, with URL/DOI and access date nearby")
                end
            end
        end
    end

    @info "README structure audit done."
    return nothing
end
