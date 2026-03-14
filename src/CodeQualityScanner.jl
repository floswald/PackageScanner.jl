# Code Quality Scanner Module
# Detects high-risk coding patterns in replication packages.

using TOML

"""
    CodeQualityFinding

A single finding from the code quality scanner.

# Fields
- `rule`: rule identifier (e.g. `"missing_seed"`, `"absolute_path"`)
- `risk_level`: `:critical` or `:advisory`
- `language`: detected language (`"stata"`, `"r"`, `"python"`, `"julia"`, `"all"`)
- `filepath`: path to the file containing the finding (empty for package-level findings)
- `line_number`: line number of the finding, or `nothing` for package-level findings
- `message`: human-readable explanation for the report
- `context`: matched line or brief summary
"""
struct CodeQualityFinding
    rule::String
    risk_level::Symbol
    language::String
    filepath::String
    line_number::Union{Int,Nothing}
    message::String
    context::String
end

"""
    language_of(filepath::String) -> Union{String,Nothing}

Map a file path to a language key used in the config (`"stata"`, `"r"`, `"python"`, `"julia"`).
Returns `nothing` for unrecognised extensions.
"""
function language_of(filepath::String)::Union{String,Nothing}
    ext = lowercase(splitext(filepath)[2])
    if ext in (".do", ".ado")
        return "stata"
    elseif ext in (".r", ".rmd", ".qmd")
        return "r"
    elseif ext in (".py", ".ipynb")
        return "python"
    elseif ext in (".jl", ".jmd")
        return "julia"
    else
        return nothing
    end
end

# ---------------------------------------------------------------------------
# Rule 1: Missing random seed (package-level, per language)
# ---------------------------------------------------------------------------

function _check_missing_seed(files_by_lang::Dict{String,Vector{String}},
                              config::Dict)::Vector{CodeQualityFinding}
    findings = CodeQualityFinding[]
    languages = ("stata", "r", "python", "julia")

    for lang in languages
        files = get(files_by_lang, lang, String[])
        isempty(files) && continue

        lang_cfg = get(config, lang, Dict())
        trigger_cfg = get(lang_cfg, "seed_triggers", nothing)
        seed_cfg    = get(lang_cfg, "seed_calls", nothing)
        (isnothing(trigger_cfg) || isnothing(seed_cfg)) && continue

        trigger_pats = trigger_cfg["patterns"]
        seed_pats    = seed_cfg["patterns"]

        # Collect all trigger matches across the package
        trigger_hits = Tuple{String,Int,String}[]   # (file, lineno, line)
        for f in files
            isfile(f) || continue
            for (i, line) in enumerate(eachline(f))
                for pat in trigger_pats
                    if occursin(Regex(pat, "i"), line)
                        push!(trigger_hits, (f, i, strip(line)))
                        break
                    end
                end
            end
        end

        isempty(trigger_hits) && continue   # no stochastic calls → nothing to flag

        # Check whether any seed call exists anywhere in the package
        seed_found = false
        for f in files
            isfile(f) || continue
            seed_found && break
            for line in eachline(f)
                for pat in seed_pats
                    if occursin(Regex(pat, "i"), line)
                        seed_found = true
                        break
                    end
                end
                seed_found && break
            end
        end

        if !seed_found
            # Summarise where triggers were seen
            summary_hits = join(
                ["$(basename(f)):$ln" for (f, ln, _) in trigger_hits[1:min(3, end)]],
                ", "
            )
            more = length(trigger_hits) > 3 ? " (and $(length(trigger_hits)-3) more)" : ""
            push!(findings, CodeQualityFinding(
                "missing_seed",
                :critical,
                lang,
                "",   # package-level finding
                nothing,
                "No random seed set — stochastic calls detected in $lang code.",
                "Triggers found at: $summary_hits$more"
            ))
        end
    end
    return findings
end

# ---------------------------------------------------------------------------
# Rule 2: Hardcoded absolute paths (all languages, line-level)
# ---------------------------------------------------------------------------

function _check_absolute_paths(files::Vector{String},
                                config::Dict)::Vector{CodeQualityFinding}
    findings = CodeQualityFinding[]
    all_cfg = get(config, "all", Dict())
    path_cfg = get(all_cfg, "absolute_paths", nothing)
    isnothing(path_cfg) && return findings

    patterns = path_cfg["patterns"]
    message  = path_cfg["message"]
    regexes  = [Regex(p) for p in patterns]

    for f in files
        isfile(f) || continue
        for (i, line) in enumerate(eachline(f))
            for re in regexes
                if occursin(re, line)
                    push!(findings, CodeQualityFinding(
                        "absolute_path",
                        :critical,
                        something(language_of(f), "unknown"),
                        f,
                        i,
                        message,
                        strip(line)
                    ))
                    break  # one finding per line is enough
                end
            end
        end
    end
    return findings
end

# ---------------------------------------------------------------------------
# Rule 3: merge m:m (Stata only, line-level)
# ---------------------------------------------------------------------------

function _check_merge_mm(stata_files::Vector{String},
                          config::Dict)::Vector{CodeQualityFinding}
    findings = CodeQualityFinding[]
    stata_cfg = get(config, "stata", Dict())
    mm_cfg    = get(stata_cfg, "merge_mm", nothing)
    isnothing(mm_cfg) && return findings

    pat     = Regex(mm_cfg["pattern"], "i")
    message = mm_cfg["message"]

    for f in stata_files
        isfile(f) || continue
        for (i, line) in enumerate(eachline(f))
            if occursin(pat, line)
                push!(findings, CodeQualityFinding(
                    "merge_mm",
                    :critical,
                    "stata",
                    f,
                    i,
                    message,
                    strip(line)
                ))
            end
        end
    end
    return findings
end

# ---------------------------------------------------------------------------
# Rule 4: Undocumented sample drops (Stata, R, Python)
# ---------------------------------------------------------------------------

function _check_undocumented_drops(files_by_lang::Dict{String,Vector{String}},
                                    config::Dict)::Vector{CodeQualityFinding}
    findings = CodeQualityFinding[]

    lang_rule_pairs = [
        ("stata", "undocumented_drop"),
        ("r",     "undocumented_filter"),
        ("python","undocumented_drop"),
    ]

    for (lang, rule_key) in lang_rule_pairs
        files = get(files_by_lang, lang, String[])
        isempty(files) && continue

        lang_cfg = get(config, lang, Dict())
        rule_cfg = get(lang_cfg, rule_key, nothing)
        isnothing(rule_cfg) && continue

        drop_pats    = [Regex(p, "i") for p in rule_cfg["patterns"]]
        comment_re   = Regex(rule_cfg["comment_pattern"])
        message      = rule_cfg["message"]

        for f in files
            isfile(f) || continue
            lines = readlines(f)
            for (i, line) in enumerate(lines)
                for drop_re in drop_pats
                    if occursin(drop_re, line)
                        # Look for a comment in the 2 preceding lines
                        preceding = lines[max(1, i-2):i-1]
                        has_comment = any(l -> occursin(comment_re, l), preceding)
                        if !has_comment
                            push!(findings, CodeQualityFinding(
                                "undocumented_drop",
                                :advisory,
                                lang,
                                f,
                                i,
                                message,
                                strip(line)
                            ))
                        end
                        break
                    end
                end
            end
        end
    end
    return findings
end

# ---------------------------------------------------------------------------
# Rule 5: Merge without explicit join type (R, Python)
# ---------------------------------------------------------------------------

function _check_implicit_join(files_by_lang::Dict{String,Vector{String}},
                               config::Dict)::Vector{CodeQualityFinding}
    findings = CodeQualityFinding[]

    # --- R ---
    r_files = get(files_by_lang, "r", String[])
    r_cfg   = get(get(config, "r", Dict()), "implicit_join", nothing)

    if !isnothing(r_cfg) && !isempty(r_files)
        merge_re    = Regex(r_cfg["pattern"], "i")
        required_re = [Regex(p, "i") for p in r_cfg["required_args"]]
        message     = r_cfg["message"]

        for f in r_files
            isfile(f) || continue
            for (i, line) in enumerate(eachline(f))
                if occursin(merge_re, line)
                    has_explicit = any(re -> occursin(re, line), required_re)
                    if !has_explicit
                        push!(findings, CodeQualityFinding(
                            "implicit_join",
                            :advisory,
                            "r",
                            f,
                            i,
                            message,
                            strip(line)
                        ))
                    end
                end
            end
        end
    end

    # --- Python ---
    py_files = get(files_by_lang, "python", String[])
    py_cfg   = get(get(config, "python", Dict()), "implicit_join", nothing)

    if !isnothing(py_cfg) && !isempty(py_files)
        merge_pats  = [Regex(p, "i") for p in py_cfg["patterns"]]
        required_re = Regex(py_cfg["required_arg"], "i")
        message     = py_cfg["message"]

        for f in py_files
            isfile(f) || continue
            for (i, line) in enumerate(eachline(f))
                for merge_re in merge_pats
                    if occursin(merge_re, line)
                        if !occursin(required_re, line)
                            push!(findings, CodeQualityFinding(
                                "implicit_join",
                                :advisory,
                                "python",
                                f,
                                i,
                                message,
                                strip(line)
                            ))
                        end
                        break
                    end
                end
            end
        end
    end

    return findings
end

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

"""
    scan_code_quality(codefiles::Vector{String}, config_path::String) -> Vector{CodeQualityFinding}

Scan `codefiles` for high-risk coding patterns defined in `config_path` (TOML).

Returns a vector of `CodeQualityFinding` items, each carrying a `risk_level`
(`:critical` or `:advisory`), the affected file and line, and a human-readable
`message`.
"""
function scan_code_quality(codefiles::Vector{String},
                            config_path::String)::Vector{CodeQualityFinding}
    config = TOML.parsefile(config_path)

    # Group files by language
    files_by_lang = Dict{String,Vector{String}}()
    for f in codefiles
        lang = language_of(f)
        isnothing(lang) && continue
        push!(get!(files_by_lang, lang, String[]), f)
    end

    findings = CodeQualityFinding[]

    append!(findings, _check_missing_seed(files_by_lang, config))
    append!(findings, _check_absolute_paths(codefiles, config))
    append!(findings, _check_merge_mm(get(files_by_lang, "stata", String[]), config))
    append!(findings, _check_undocumented_drops(files_by_lang, config))
    append!(findings, _check_implicit_join(files_by_lang, config))

    return findings
end
