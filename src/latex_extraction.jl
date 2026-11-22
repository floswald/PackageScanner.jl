# LaTeX/PDF paper-text extraction for JPE.jl's Stage C claims extraction
# (JPE-Reproducibility/JPE.jl#29, #34). PackageScanner.jl does the
# deterministic flattening/extraction here; JPE.jl shells out to this
# environment for it (see that repo's extract_paper_text) and separately
# calls `claude -p` on the result -- no LLM calls happen in this package.

"""
    LATEX_INPUT_RE

Matches `\\input{path}`, `\\include{path}`, and the braceless form
`\\input path` (rare, but valid LaTeX). Capture group 2 is the braced
target, group 3 the braceless one -- exactly one is non-`nothing` per match.
"""
const LATEX_INPUT_RE = r"\\(input|include)\s*(?:\{([^}]*)\}|([^\s{}\\]+))"

"""
    _strip_latex_comments(s::String) -> String

Remove everything from an unescaped `%` to end of line, per line. `\\%` is
left alone (escaped literal percent, not a comment marker).
"""
function _strip_latex_comments(s::String)
    lines = split(s, '\n'; keepempty = true)
    stripped = [replace(line, r"(?<!\\)%.*" => "") for line in lines]
    return join(stripped, '\n')
end

"""
    _is_tex_root(path::String) -> Bool

A `.tex` file is a compilable root (as opposed to a fragment only ever
reached via `\\input`/`\\include`) iff it declares both `\\documentclass`
and `\\begin{document}`, after comment-stripping.
"""
function _is_tex_root(path::String)
    content = _strip_latex_comments(read(path, String))
    return occursin(r"\\documentclass", content) && occursin(r"\\begin\{document\}", content)
end

"""
    find_tex_roots(dir::String) -> Vector{String}

Recursively find every `.tex` file under `dir` that is a compilable root
(see `_is_tex_root`). Unreadable files are skipped silently. Returned sorted
for determinism.
"""
function find_tex_roots(dir::String)
    roots = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(lowercase(f), ".tex") || continue
            fpath = joinpath(root, f)
            try
                _is_tex_root(fpath) && push!(roots, fpath)
            catch
                continue
            end
        end
    end
    return sort(roots)
end

"""
    _resolve_tex_path(target::String, including_dir::String, root_dir::String)

Resolve an `\\input`/`\\include` target: try relative to the including
file's own directory first (how LaTeX actually resolves it), then relative
to the package root `root_dir` (handles the common case of a flat `tex/`
directory where every file `\\input`s by root-relative path regardless of
its own location). Appends `.tex` if the target has no extension and the
bare name isn't found. Returns `nothing` if nothing matches.
"""
function _resolve_tex_path(target::AbstractString, including_dir::String, root_dir::String)
    for base in (including_dir, root_dir)
        for cand in (joinpath(base, target), joinpath(base, target * ".tex"))
            isfile(cand) && return cand
        end
    end
    return nothing
end

"""
    _flatten_tex(path, root_dir, visited, unresolved) -> String

Recursively inline every `\\input`/`\\include` in the `.tex` file at `path`,
comments already stripped. `visited` (absolute paths) guards against
circular includes -- a revisit is recorded in `unresolved` and not
re-expanded (left as the raw command text) rather than looping forever. A
target that can't be resolved on disk at all is likewise recorded in
`unresolved` and left as the raw command, so a human (or Stage D, reading
`report-claims-extraction.md`) can see something didn't resolve instead of
it silently vanishing.
"""
function _flatten_tex(path::String, root_dir::String, visited::Set{String}, unresolved::Vector{Tuple{String,String}})
    key = isfile(path) ? realpath(path) : abspath(path)
    if key in visited
        push!(unresolved, (path, "circular \\input/\\include, not re-expanded"))
        return ""
    end
    push!(visited, key)

    content = _strip_latex_comments(read(path, String))
    including_dir = dirname(path)

    out = IOBuffer()
    pos = firstindex(content)
    for m in eachmatch(LATEX_INPUT_RE, content)
        write(out, content[pos:(m.offset - 1)])
        target = isnothing(m.captures[2]) ? m.captures[3] : m.captures[2]
        resolved = _resolve_tex_path(target, including_dir, root_dir)
        if isnothing(resolved)
            push!(unresolved, (path, target))
            write(out, m.match)
        else
            write(out, _flatten_tex(resolved, root_dir, visited, unresolved))
        end
        pos = m.offset + ncodeunits(m.match)
    end
    write(out, content[pos:end])
    return String(take!(out))
end

"""
    extract_latex_text(dir::String; main_files = nothing)

Stage C input: flatten the paper's LaTeX source under `dir` into one text
blob with every `\\input`/`\\include` inlined, so cross-references like
"controls listed in Table A3" resolve against content that's actually
present in the returned text. Returns a named tuple:

- `text::String`: the flattened source (empty if `ambiguous` is `true`, or
  no `.tex` root was found at all).
- `roots::Vector{String}`: the candidate root `.tex` file(s) found (or
  `main_files`, if given).
- `unresolved::Vector{Tuple{String,String}}`: `(including_file, target)`
  pairs for every `\\input`/`\\include` that couldn't be resolved on disk, or
  that formed a cycle.
- `ambiguous::Bool`: `true` iff auto-detection found more than one
  compilable root and `main_files` wasn't given to disambiguate.

If `main_files` is given explicitly (one path, or several -- e.g. a main
paper plus a separately-compiled appendix), auto-detection is skipped
entirely and exactly those files are flattened and concatenated; this is
how a caller resolves an earlier `ambiguous = true` result.
"""
function extract_latex_text(dir::String; main_files::Union{Nothing,Vector{String}} = nothing)
    if !isnothing(main_files)
        unresolved = Tuple{String,String}[]
        texts = String[]
        for mf in main_files
            visited = Set{String}()
            push!(texts, _flatten_tex(mf, dir, visited, unresolved))
        end
        return (text = join(texts, "\n\n"), roots = main_files, unresolved = unresolved, ambiguous = false)
    end

    roots = find_tex_roots(dir)

    if isempty(roots)
        return (text = "", roots = String[], unresolved = Tuple{String,String}[], ambiguous = false)
    elseif length(roots) > 1
        return (text = "", roots = roots, unresolved = Tuple{String,String}[], ambiguous = true)
    end

    unresolved = Tuple{String,String}[]
    text = _flatten_tex(roots[1], dir, Set{String}(), unresolved)
    return (text = text, roots = roots, unresolved = unresolved, ambiguous = false)
end

"""
    extract_pdf_text(pdf_path::String)

Stage C fallback when no `.tex` source is available at all: extract text
from the compiled PDF directly via `get_pdf_text`. Returns the same named
tuple shape as `extract_latex_text` so callers can treat the two
interchangeably: `roots = [pdf_path]`, `ambiguous = false` (a single PDF
has no root-selection problem), `unresolved = []` (a compiled PDF has no
`\\input` chains left to resolve -- that structure is already gone, which is
a real loss for precision but means there's nothing left to resolve either).
"""
function extract_pdf_text(pdf_path::String)
    isfile(pdf_path) || error("PDF file not found: $pdf_path")
    text = get_pdf_text(pdf_path)
    return (text = text, roots = [pdf_path], unresolved = Tuple{String,String}[], ambiguous = false)
end
