
# Stage C: Claude-CLI claims-extraction helpers (ported from
# JPE-Reproducibility/JPE.jl's claims_runner_helpers.jl, see
# JPE-Reproducibility/PackageScanner.jl#21).
#
# These were kept self-contained in JPE.jl (no DB calls, no DataFrameRow
# access, no interactive RadioMenu) only so that file's source text could be
# spliced verbatim into a generated runner script run inside
# JULIA_RUNNER_ENV, which has PackageScanner.jl installed but not JPE.jl
# itself. That constraint is why this logic belongs here as real,
# importable functions instead: both JPE.jl and the generated runner
# script already depend on PackageScanner.jl, so there is no reason left to
# duplicate this as spliced source text.

"""
    claude_binary()

Path to the `claude` CLI, resolved via `PATH`.
"""
claude_binary() = Sys.which("claude")

"""
    claude_jpe_config_dir()

The `CLAUDE_CONFIG_DIR` used by the `claude-jpe` shell alias (the JPE Claude
Pro account, distinct from the user's personal one). Falls back to
`~/.claude-jpe` if `CLAUDE_CONFIG_DIR` isn't already set in the environment
(e.g. when this is called from a session that isn't itself a nested
claude-jpe invocation).
"""
claude_jpe_config_dir() = get(ENV, "CLAUDE_CONFIG_DIR", joinpath(homedir(), ".claude-jpe"))

"""
    JOURNAL_OFFICE_UPLOADER_MARKERS

Filename substrings that identify a file as uploaded by JPE staff rather
than the author (e.g. the editorial assistant forwarding a copy of the
accepted manuscript into `paper-appendices/`, filename-prefixed with their
own name). These are a less-authoritative, potentially-stale fallback --
the author's own upload should always win when both exist. Add more names
here as staff turn over; there's no structural way to distinguish uploader
identity from the filename alone, so this is necessarily manually maintained.
"""
const JOURNAL_OFFICE_UPLOADER_MARKERS = ["Connie -"]

"""
    is_journal_office_upload(path::String) -> Bool

True iff `path`'s filename matches one of `JOURNAL_OFFICE_UPLOADER_MARKERS`.
"""
is_journal_office_upload(path::String) = any(m -> occursin(m, basename(path)), JOURNAL_OFFICE_UPLOADER_MARKERS)

"""
    find_paper_pdf(dir::String) -> Union{String,Nothing}

Stage C PDF fallback (see `extract_pdf_text`): find a compiled PDF of the
paper under `dir`, for use when `extract_latex_text` found no `.tex` root at
all. Prefers a file literally named `paper.pdf` (case-insensitive) if
present; otherwise prefers an author-uploaded PDF over one matching
`JOURNAL_OFFICE_UPLOADER_MARKERS` (the author's own copy is more likely to
be up to date than a journal-office-forwarded one), then falls back to the
first PDF found (sorted, for determinism across runs). Returns `nothing`
if no PDF exists anywhere under `dir`.
"""
function find_paper_pdf(dir::String)
    pdfs = String[]
    for (root, _, files) in walkdir(dir)
        for f in files
            endswith(lowercase(f), ".pdf") && push!(pdfs, joinpath(root, f))
        end
    end
    isempty(pdfs) && return nothing
    sort!(pdfs)

    named = findfirst(p -> lowercase(basename(p)) == "paper.pdf", pdfs)
    isnothing(named) || return pdfs[named]

    author_pdfs = filter(!is_journal_office_upload, pdfs)
    return isempty(author_pdfs) ? first(pdfs) : first(author_pdfs)
end

"""
    CLAIMS_JSON_SCHEMA

JSON schema passed to `claude -p --json-schema` to force structured claims
output: data sources (with access date / URL/DOI if the paper gives one),
general data processing steps (file loading/merging/cleaning/filtering
applied before any specific table -- the part Stage D cross-references
against Stage A's "which code loads which data" findings), and per-table
specs (estimator, outcome variable, key regressors, controls, fixed effects,
clustering, sample restriction, data source) plus per-figure descriptions.
Unknown/unstated fields must be `null`, not guessed.
"""
const CLAIMS_JSON_SCHEMA = """
{"type":"object","properties":{
"data_sources":{"type":"array","items":{"type":"object","properties":{
  "name":{"type":"string"},"access_date":{"type":["string","null"]},"url_or_doi":{"type":["string","null"]}
},"required":["name","access_date","url_or_doi"]}},
"data_processing_steps":{"type":"array","items":{"type":"object","properties":{
  "description":{"type":"string"},"variables_involved":{"type":"array","items":{"type":"string"}}
},"required":["description","variables_involved"]}},
"tables":{"type":"array","items":{"type":"object","properties":{
  "label":{"type":"string"},"title":{"type":["string","null"]},"estimator":{"type":["string","null"]},
  "outcome_var":{"type":["string","null"]},"key_regressors":{"type":"array","items":{"type":"string"}},
  "controls":{"type":"array","items":{"type":"string"}},
  "fixed_effects":{"type":"array","items":{"type":"string"}},"clustering":{"type":["string","null"]},
  "sample_restriction":{"type":["string","null"]},"data_source":{"type":["string","null"]}
},"required":["label","title","estimator","outcome_var","key_regressors","controls","fixed_effects","clustering","sample_restriction","data_source"]}},
"figures":{"type":"array","items":{"type":"object","properties":{
  "label":{"type":"string"},"description":{"type":"string"}
},"required":["label","description"]}}
},"required":["data_sources","data_processing_steps","tables","figures"]}
"""

"""
    claims_extraction_prompt(paper_text_path::String)

The prompt given to `claude -p` for the claims-extraction call. Points at the
flattened paper text by path (read via the `Read` tool) rather than embedding
it inline, so the shell command itself stays short regardless of paper size.
"""
function claims_extraction_prompt(paper_text_path::String)
    """
    Read the flattened LaTeX paper source at $paper_text_path and extract a
    structured summary of its empirical claims, for a static plausibility
    cross-check against the paper's replication package (no code execution
    involved -- this is not a reproducibility check). Follow the provided
    JSON schema exactly. For each table, fill in as many structured fields as
    the text actually supports; use null for anything the paper doesn't
    specify. Do not invent or guess values that aren't in the text.

    Resolve cross-references before extracting: when the text says "see
    Appendix H" or "controls listed in Table A3" or "as defined in Section
    2", go find that content elsewhere in the flattened text (it has already
    been inlined) and extract the actual content there -- do not leave a
    reference unresolved. For `controls`, enumerate every control variable
    individually rather than writing an aggregate description like
    "socio-demographic controls".

    Skip purely conceptual figures that have no replicable data behind them
    (flow diagrams, conceptual frameworks, schematics, screenshots, photos,
    maps) -- only extract figures that plot actual data or model output.
    """
end

"""
    build_claude_claims_cmd(paper_text_path::String; effort = "medium")

The `Cmd` for the headless claims-extraction call. Split out from
`run_claude_claims_extraction` so the flags are testable without actually
invoking `claude` (no live API/CLI calls in tests).

Uses `--safe-mode` (not `--bare`, which strictly requires `ANTHROPIC_API_KEY`
and would break the Pro-subscription OAuth auth this relies on) to drop
CLAUDE.md/memory/hooks overhead, and restricts tools to `Read` only --
a single turn, no agentic loop, to keep this cheap under a Pro quota.

Uses `addenv` (not `setenv`, which replaces the *entire* child environment
with just the pairs given) so the override merges with the inherited
environment -- `claude` still needs `HOME`/`PATH` etc. to find its
credentials, or it fails immediately with "Not logged in".

Passes `--add-dir` for the directory containing `paper_text_path` to
explicitly grant `Read` access to it. This call happens to work without it
today (the prompt states the full absolute path verbatim, which `--safe-mode`
appears to auto-approve), but Stage D's identical setup silently returned
empty results once its prompt stopped doing that (see `build_crosscheck_cmd`)
-- `--add-dir` makes the grant explicit instead of relying on that heuristic.
"""
function build_claude_claims_cmd(paper_text_path::String; effort::String = "medium")
    bin = claude_binary()
    isnothing(bin) && error("claude CLI not found on PATH")

    addenv(
        `$bin -p $(claims_extraction_prompt(paper_text_path))
         --output-format json --tools Read --safe-mode --effort $effort
         --add-dir $(dirname(paper_text_path))
         --json-schema $CLAIMS_JSON_SCHEMA`,
        "CLAUDE_CONFIG_DIR" => claude_jpe_config_dir(),
    )
end

"""
    run_claude_claims_extraction(paper_text_path::String; effort = "medium")

Run the headless claims-extraction call and return
`(claims = <parsed structured_output>, cost_usd = <reported cost>)`.
"""
function run_claude_claims_extraction(paper_text_path::String; effort::String = "medium")
    cmd = build_claude_claims_cmd(paper_text_path; effort = effort)
    out = read(cmd, String)
    parsed = JSON.parse(out)

    get(parsed, "is_error", true) == false || error("claude -p failed: $(get(parsed, "result", "unknown error"))")

    return (claims = parsed["structured_output"], cost_usd = get(parsed, "total_cost_usd", missing))
end
