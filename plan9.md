# Plan: Issue #9 — LLM-based table results extractor

## Goal

Add `extract_table_results(pdf_path; api_key, model)` to PackageScanner.
Produces `report-table-results.md` with per-cell numeric values from all
paper tables. Optional step in `precheck_package` — skipped silently if no
PDF or no API key.

Reference implementation: `social_science_replicability/src/benchmark/results_extractor.py`
Core prompt source: `social_science_replicability/src/agents/extractor.py` lines 119–187
  (RESULTS_EXTRACTOR_SYSTEM, not EXTRACTION_SYSTEM_PROMPT which avoids results)

**Status update (2026-11-22, PR #19):** this plan predates PR #19, which
replaced `PDFIO.jl` with PyMuPDF (via `PyCall`) for all PDF text extraction
in the package, and separately added `extract_latex_text`/`extract_pdf_text`
for Stage C claims extraction (a different, narrower methodology-extraction
task — see `JPE-Reproducibility/JPE.jl#29`/`#34` — not implemented here).
Nothing in this plan has been implemented yet; the two helper sections below
are updated to use PyMuPDF instead of the Poppler CLIs (`pdftotext`,
`pdftoppm`) originally assumed, since that dependency now already exists in
the package for an unrelated reason. Tracked in issue #9.

---

## Source mapping: Python → Julia

| Python | Julia |
|---|---|
| `ResultsExtractor` class | `extract_table_results` function |
| `ExtractedTableResponse` Pydantic model | `ExtractedTableResponse` struct (JSON3-deserialised) |
| `CellValueResponse` Pydantic model | `CellValue` struct |
| `_anthropic_tool_call` | `_call_anthropic_tool` helper |
| `pdf_to_base64_images` (vision) | `pdf_to_page_images` via `pdftoppm` CLI + `Base64` stdlib |
| `extract_text_from_pdf` | `pdftotext` CLI (caption/table-id detection only) |
| `_extract_pages` (slice around "Table N") | not used — vision renders whole pages |

Vision mode is required for accuracy. Text extraction via pdftotext mangles table
column alignment; LLMs misassign values to columns on garbled text. The reference
implementation defaults `use_vision=True` for the same reason: "Accuracy matters
more than token cost since extraction runs once per paper." (~80–120k tokens per
paper, billed once).

---

## Data structures

```julia
# src/TableExtractor.jl

struct CellValue
    row_label::String
    column_label::String
    row_index::Int          # 0-based, every row including SE rows
    col_index::Int          # 0-based, excluding row-label column
    raw_text::String        # exact text as in paper e.g. "-0.174***"
    numeric_value::Union{Float64, Nothing}   # stripped of stars/parens
    is_standard_error::Bool
    significance_stars::Int  # 0,1,2,3
    significance_level::Union{Float64, Nothing}   # 0.1, 0.05, 0.01
    is_string::Bool
    row_type::String        # see VALID_ROW_TYPES below
    statistic_detail::Union{String, Nothing}
    refers_to::Union{Int, Nothing}   # row_index of parent coef for se/p_value rows
end

const VALID_ROW_TYPES = Set([
    "coefficient", "se", "p_value", "ci", "t_stat",
    "statistic_r2", "statistic_n_obs", "statistic_f", "statistic_other",
    "string", "panel_header",
])

struct ExtractedTable
    table_id::String
    column_labels::Vector{String}
    row_labels::Vector{String}
    cells::Vector{CellValue}
    significance_convention::Union{String, Nothing}
    notes::Union{String, Nothing}
end

struct TableExtractionResult
    paper_id::String
    tables::Vector{ExtractedTable}
    model::String
    timestamp::String
    token_usage::Dict{String, Int}
end
```

---

## Prompts (port from Python, unchanged)

Copy verbatim from `results_extractor.py`:

- `RESULTS_EXTRACTOR_SYSTEM` (lines 119–168) → system prompt for every call
- `RESULTS_EXTRACTOR_PROMPT` (lines 171–187) → user prompt for vision mode

---

## JSON schema for Anthropic tool use

Anthropic tool use forces structured output. Schema mirrors `ExtractedTableResponse`:

```json
{
  "name": "submit_table",
  "description": "Submit the extracted table result.",
  "input_schema": {
    "type": "object",
    "required": ["table_id", "column_labels", "row_labels", "cells"],
    "properties": {
      "table_id":       { "type": "string" },
      "column_labels":  { "type": "array", "items": { "type": "string" } },
      "row_labels":     { "type": "array", "items": { "type": "string" } },
      "significance_convention": { "type": ["string", "null"] },
      "notes":          { "type": ["string", "null"] },
      "cells": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["row_label", "column_label", "row_index", "col_index", "raw_text", "row_type"],
          "properties": {
            "row_label":           { "type": "string" },
            "column_label":        { "type": "string" },
            "row_index":           { "type": "integer" },
            "col_index":           { "type": "integer" },
            "raw_text":            { "type": "string" },
            "numeric_value":       { "type": ["number", "null"] },
            "is_standard_error":   { "type": "boolean" },
            "significance_stars":  { "type": "integer" },
            "significance_level":  { "type": ["number", "null"] },
            "is_string":           { "type": "boolean" },
            "row_type":            { "type": "string" },
            "statistic_detail":    { "type": ["string", "null"] },
            "refers_to":           { "type": ["integer", "null"] }
          }
        }
      }
    }
  }
}
```

---

## API call flow

```
extract_table_results(pdf_path; api_key, model="claude-sonnet-4-6", dpi=200)
  → pdf_text  = pdftotext(pdf_path)              # CLI — used only for table-id detection
  → table_ids = detect_table_ids(pdf_text)       # regex r"[Tt]able\s+\d+" → ["Table 1", ...]
  → page_images = pdf_to_page_images(pdf_path, dpi)  # pdftoppm → Vector{String} (base64 PNG)
  → for each table_id:
      prompt  = format(RESULTS_EXTRACTOR_PROMPT; table_id, ...)
      response = call_anthropic_vision(system, prompt, page_images, tool_schema; api_key, model)
      parsed  = JSON3.read(response["input"])     # tool_use block
      push!(tables, struct_from_json(parsed))
  → write_table_results_report(tables, out_dir)
```

### `pdf_to_text` helper (table-id detection only)

**Update (PR #19, superseding the Poppler plan below):** PackageScanner.jl no
longer shells out to Poppler CLI tools for anything. `get_pdf_text`
(`src/readme_parser.jl`) already extracts a PDF's full text via **PyMuPDF**
(`PyCall`), replacing both the old `PDFIO.jl` dependency and the
`pdftotext`/`pdftoppm` CLIs this plan originally assumed. Table-id detection
should reuse `PackageScanner.get_pdf_text(pdf_path)` directly instead of a
new `pdf_to_text` wrapping a `pdftotext` shell-out:

```julia
# instead of shelling out to `pdftotext -layout`:
text = PackageScanner.get_pdf_text(pdf_path)
table_ids = detect_table_ids(text)
```

### `pdf_to_page_images` helper

**Update (PR #19):** use PyMuPDF's own page-rendering (`page.get_pixmap()`)
instead of `pdftoppm`, via the same `PyCall`-bound `pymupdf` module
`get_pdf_text` already imports — one Python dependency instead of two
system CLIs:

```julia
using PyCall, Base64

function pdf_to_page_images(pdf_path::String; dpi::Int=200)::Vector{String}
    pymupdf = pyimport("pymupdf")
    doc = pymupdf.open(pdf_path)
    try
        zoom = dpi / 72  # PyMuPDF's default render resolution is 72 dpi
        mat = pymupdf.Matrix(zoom, zoom)
        [base64encode(doc.load_page(i).get_pixmap(matrix = mat).tobytes("png"))
         for i in 0:(length(doc) - 1)]
    finally
        doc.close()
    end
end
```

### Anthropic vision HTTP call

```julia
function call_anthropic_vision(system::String, user_text::String,
                                page_images::Vector{String}, tool_schema::Dict;
                                api_key::String, model::String, max_tokens::Int=16000)
    image_blocks = [
        Dict("type" => "image",
             "source" => Dict("type" => "base64",
                              "media_type" => "image/png",
                              "data" => img))
        for img in page_images
    ]
    content = vcat([Dict("type" => "text", "text" => user_text)], image_blocks)

    body = Dict(
        "model"      => model,
        "max_tokens" => max_tokens,
        "system"     => system,
        "tools"      => [tool_schema],
        "tool_choice"=> Dict("type" => "tool", "name" => "submit_table"),
        "messages"   => [Dict("role" => "user", "content" => content)],
    )
    resp = HTTP.post(
        "https://api.anthropic.com/v1/messages",
        ["x-api-key" => api_key,
         "anthropic-version" => "2023-06-01",
         "content-type" => "application/json"],
        JSON3.write(body),
    )
    data = JSON3.read(resp.body)
    tool_block = first(filter(b -> b[:type] == "tool_use", data[:content]))
    tool_block[:input], data[:usage]
end
```

Note: `max_tokens=16000` matches reference impl. All pages sent per table call —
same rationale as Python: table detection by text is unreliable (image-based
tables, multi-page tables, extraction failures).

---

## Report format: `report-table-results.md`

```markdown
## Table Results Extraction

*Extracted with claude-sonnet-4-6 on 2026-06-03. Total tokens: 14,231.*

---

### Table 1

| Row | Column | Value | SE | Stars | Type |
|-----|--------|-------|----|-------|------|
| Treatment | (1) | -0.174 | (0.052) | *** | coefficient |
| ... | ... | ... | ... | ... | ... |

---

### Table 2
...
```

One `###` section per table. Coefficient + SE paired on same row when
`refers_to` links them. Non-numeric cells (Yes/No, FE indicators) shown as-is.

---

## Integration into `precheck_package`

After the existing code quality scan block in `precheck.jl` (around line 115):

```julia
# Optional: extract table values from paper PDF using LLM
paper_pdf = get(kwargs, :paper_pdf, nothing)
extract_tables_flag = get(kwargs, :extract_tables, false)
api_key = get(ENV, "ANTHROPIC_API_KEY", "")

if extract_tables_flag && !isnothing(paper_pdf) && !isempty(api_key)
    @info "Extracting table results from paper PDF"
    extract_table_results(paper_pdf, out; api_key=api_key)
else
    @debug "Skipping table extraction (no PDF, no API key, or extract_tables=false)"
end
```

Caller API:
```julia
precheck_package(pkg_loc; paper_pdf="paper.pdf", extract_tables=true)
```

---

## Dependencies

### Julia packages
- `HTTP.jl` — check Project.toml first; add if missing
- `JSON3.jl` — already used elsewhere in the package
- `Base64` — stdlib, no add needed
- `PyCall` — already a dependency as of PR #19 (PDFIO → PyMuPDF swap); no new addition needed here
- `pymupdf` (Python, via the `PyCall`-bound interpreter) — already installed as of PR #19; this plan's original Poppler CLIs (`pdftotext`, `pdftoppm`) are superseded, see the two helpers above

No remaining system-CLI dependency: text extraction and page-image rendering both go through the same `pymupdf` module `get_pdf_text` already uses.

---

## Files to create/modify

| File | Action |
|---|---|
| `src/TableExtractor.jl` | New — all extraction logic |
| `src/PackageScanner.jl` | Add `include("TableExtractor.jl")` and export |
| `src/precheck.jl` | Add optional extraction call after line ~115 |
| `test/test_table_extractor.jl` | New — unit tests (mock HTTP, fixture PDF text) |
| `Project.toml` | Add HTTP.jl if missing |

---

## Tests

Per CLAUDE.md requirement: each addition covered by specific unit test.

1. `test_pdf_to_text_missing` — graceful error when the PDF file doesn't exist (was: pdftotext not found; no system CLI left to be missing)
2. `test_pdf_to_page_images_missing` — graceful error when the PDF file doesn't exist (was: pdftoppm not found)
3. `test_detect_table_ids` — regex finds ["Table 1", "Table 2", "Table A1"] from fixture text
4. `test_pdf_to_page_images` — fixture single-page PDF → Vector of one base64 string, valid PNG header
5. `test_call_anthropic_vision_mocked` — mock HTTP.post; verify request body contains image blocks, tool schema, tool_choice
6. `test_struct_from_json` — deserialise fixture JSON → `ExtractedTable`; check CellValue fields
7. `test_normalize_row_type` — legacy/unknown row_type values map to valid types
8. `test_write_report` — given fixture `ExtractedTable`, output markdown contains expected table rows
9. `test_extract_table_results_no_key` — skips cleanly, returns nothing when `ANTHROPIC_API_KEY` absent

---

## Out of scope (v1)

- Caching extracted results to JSON (run once per paper pattern)
- Comparator / diff against replicated output
- Methodology extraction (EXTRACTION_SYSTEM_PROMPT from extractor.py) — different task
