# LaTeX Paper Text Extraction Module
#
# Stage C input (JPE-Reproducibility/JPE.jl#29): produce the flattened plain
# text of a paper from its LaTeX source, for an LLM claims-extraction prompt.
# Deliberately does NOT "detex" to clean prose -- raw LaTeX (tables, labels,
# captions, \includegraphics paths) is kept as-is and fed to the model
# directly, since stripping markup would destroy exactly the table/figure
# structure a claims extractor needs. No external LaTeX engine or pandoc
# dependency: this is a lightweight, best-effort \input/\include flattener
# with simple macro substitution, not a full TeX processor.
#
# PDF extraction (the no-tex-available fallback) is out of scope here --
# tracked separately, see JPE-Reproducibility/JPE.jl#29 Stage C.

"""
    find_tex_roots(dir::String)

Recursively search `dir` for candidate main `.tex` files: those containing
`\\begin{document}` (so sub-included table/figure/preamble files are excluded),
and excluding latexdiff artifacts (filename containing `-diff` or `_diff`).

Returns a sorted `Vector{String}` of absolute paths. A paper submitted as
`main.tex` + `appendix.tex` yields both; the caller concatenates.
"""
function find_tex_roots(dir::String)
    candidates = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(lowercase(f), ".tex") || continue
            occursin(r"[-_]diff"i, f) && continue
            path = joinpath(root, f)
            txt = try
                read(path, String)
            catch
                continue
            end
            if occursin(r"\\begin\{document\}", txt)
                push!(candidates, abspath(path))
            end
        end
    end
    return sort(candidates)
end

"""
    strip_latex_comment(line::String)

Remove everything from the first *unescaped* `%` onward (i.e. not preceded by
a literal `\\`). Does not account for verbatim environments, where `%` is not
a comment marker -- a known limitation.
"""
strip_latex_comment(line::AbstractString) = replace(line, r"(?<!\\)%.*$" => "")

const NEWCOMMAND_RE = r"\\(?:re)?newcommand\*?\{\\(\w+)\}\{([^{}]*)\}"
const DEF_RE = r"\\def\\(\w+)\{([^{}]*)\}"

"""
    find_macro_defs_in_line(line::String)

Find `\\newcommand{\\x}{val}`, `\\newcommand*{\\x}{val}`, `\\renewcommand{\\x}{val}`,
and `\\def\\x{val}` definitions on a single (comment-stripped) line.

Returns a `Vector{Pair{String,String}}` of `(macro_name, value)`, values only
matched when they contain no nested braces (simple literal macros, the common
case for path-fragment macros like `\\inputpath`).
"""
function find_macro_defs_in_line(line::AbstractString)
    defs = Pair{String,String}[]
    for m in eachmatch(NEWCOMMAND_RE, line)
        push!(defs, m[1] => m[2])
    end
    for m in eachmatch(DEF_RE, line)
        push!(defs, m[1] => m[2])
    end
    return defs
end

"""
    substitute_macros(s::String, macros::Dict{String,String})

Replace every `\\name` token in `s` with `macros["name"]` if known, iterating
a few times to handle a macro expanding to another macro. Unknown tokens are
left untouched.
"""
function substitute_macros(s::AbstractString, macros::Dict{String,String})
    for _ in 1:5
        news = replace(s, r"\\\w+" => m -> get(macros, m[2:end], m))
        news == s && break
        s = news
    end
    return s
end

"""
    resolve_include_path(arg::String, root_dir::String, macros::Dict{String,String})

Substitute macros in `arg`, normalize it against `root_dir`, and append `.tex`
if no extension was given and the bare path doesn't itself exist. Returns the
resolved absolute path (which may not exist -- check with `isfile`).
"""
function resolve_include_path(arg::AbstractString, root_dir::String, macros::Dict{String,String})
    substituted = substitute_macros(arg, macros)
    candidate = normpath(joinpath(root_dir, substituted))
    if isempty(splitext(candidate)[2])
        with_ext = candidate * ".tex"
        isfile(with_ext) && return with_ext
    end
    return candidate
end

"""
    resolve_includes!(filepath, root_dir, macros, seen, unresolved; depth=0, max_depth=10)

Read `filepath`, strip comments line by line, collect macro definitions as
they're encountered (document order, matching how LaTeX itself resolves
macros), and recursively inline every `\\input{...}`/`\\include{...}` target.
`\\includegraphics{...}` is left untouched (it's a pointer to a binary figure
file, not inlineable text, and `token_occurs` from the data dependency audit
can cross-reference these paths against package output files directly).

All include paths resolve relative to `root_dir` (the paper's root), not to
the including file's own directory -- matching how `\\inputpath`-style macros
are used in practice (defined once relative to the root).

`seen` is the set of absolute paths on the current inclusion chain (cycle
guard); `unresolved` accumulates `(command, arg, attempted_path)` tuples for
includes that couldn't be resolved, mutated in place.

Returns the flattened text of `filepath` with all includes inlined.
"""
function resolve_includes!(filepath::String, root_dir::String, macros::Dict{String,String},
                            seen::Set{String}, unresolved::Vector{NTuple{3,String}};
                            depth::Int = 0, max_depth::Int = 10)
    if depth > max_depth
        return "% MAX INCLUDE DEPTH REACHED: $filepath\n"
    end

    raw = read(filepath, String)
    out = IOBuffer()

    for line in split(raw, '\n')
        line = strip_latex_comment(line)

        for (name, val) in find_macro_defs_in_line(line)
            macros[name] = val
        end

        println(out, inline_includes_in_line(line, root_dir, macros, seen, unresolved, depth, max_depth))
    end

    return String(take!(out))
end

"""
    inline_includes_in_line(line, root_dir, macros, seen, unresolved, depth, max_depth)

Replace every `\\input{...}`/`\\include{...}` on `line` with the recursively
flattened content of its target (or a `% UNRESOLVED INCLUDE` placeholder).
"""
function inline_includes_in_line(line::AbstractString, root_dir::String, macros::Dict{String,String},
                                  seen::Set{String}, unresolved::Vector{NTuple{3,String}},
                                  depth::Int, max_depth::Int)
    out = IOBuffer()
    lastidx = firstindex(line)

    for m in eachmatch(r"\\(input|include)\{([^{}]*)\}", line)
        write(out, line[lastidx:prevind(line, m.offset)])
        command, arg = String(m[1]), String(m[2])
        resolved = resolve_include_path(arg, root_dir, macros)

        if resolved in seen
            write(out, "% CYCLIC INCLUDE SKIPPED: \\$command{$arg}")
        elseif !isfile(resolved)
            push!(unresolved, (command, arg, resolved))
            write(out, "% UNRESOLVED INCLUDE: \\$command{$arg} (tried $resolved)")
        else
            child_seen = copy(seen)
            push!(child_seen, resolved)
            write(out, resolve_includes!(resolved, root_dir, macros, child_seen, unresolved;
                                          depth = depth + 1, max_depth = max_depth))
        end

        lastidx = nextind(line, m.offset + ncodeunits(m.match) - 1)
    end
    write(out, line[lastidx:end])

    return String(take!(out))
end

"""
    extract_latex_text(paper_dir::String; main_files::Union{Nothing,Vector{String}} = nothing)

Find candidate main `.tex` file(s) under `paper_dir` (see `find_tex_roots`),
flatten each by inlining `\\input`/`\\include`, and concatenate.

If `main_files` is given explicitly, auto-discovery and the ambiguity check
below are skipped entirely -- exactly those files are flattened. Use this
once a human has disambiguated (see below).

If `main_files` is omitted, `find_tex_roots` runs auto-discovery:
- **0 candidates**: returns `text = ""`, `roots = []`, `ambiguous = false`.
  This is the "no tex available" signal -- callers should fall back to the PDF
  (out of scope here).
- **1 candidate**: proceeds normally, flattens it.
- **>1 candidates**: this is genuinely ambiguous -- a paper legitimately
  shipping `main.tex` + `appendix.tex` looks identical, structurally, to two
  unrelated conflicting drafts. Rather than guess (auto-concatenating or
  picking one), this returns `text = ""`, `ambiguous = true`, and `roots` set
  to the full candidate list. **The caller must surface this list and ask the
  user which file(s) are the actual paper source**, then re-call with
  `main_files` set to the confirmed list.

Returns a named tuple `(text, roots, unresolved, ambiguous)`:
- `text`: the flattened content of the resolved root file(s), concatenated.
  Empty when nothing was found, or when discovery was ambiguous and
  `main_files` was not given.
- `roots`: the main `.tex` files used (or, when ambiguous, *all* candidates
  found, for the caller to present as choices).
- `unresolved`: `(command, arg, attempted_path)` tuples for includes that
  could not be resolved (e.g. a macro that was never defined, or a typo).
- `ambiguous`: `true` iff auto-discovery found more than one candidate and
  `main_files` was not given to disambiguate.
"""
function extract_latex_text(paper_dir::String; main_files::Union{Nothing,Vector{String}} = nothing)
    if !isnothing(main_files)
        roots = abspath.(main_files)
    else
        roots = find_tex_roots(paper_dir)

        isempty(roots) && return (text = "", roots = String[], unresolved = NTuple{3,String}[], ambiguous = false)

        if length(roots) > 1
            return (text = "", roots = roots, unresolved = NTuple{3,String}[], ambiguous = true)
        end
    end

    macros = Dict{String,String}()
    unresolved = NTuple{3,String}[]
    parts = String[]

    for root in roots
        push!(parts, resolve_includes!(root, paper_dir, macros, Set{String}([root]), unresolved))
    end

    return (text = join(parts, "\n\n"), roots = roots, unresolved = unresolved, ambiguous = false)
end
