# Secret Scanner Module
# Detects likely live API keys/credentials in code files.

"""
    SecretFinding

A single possible-secret detection.

Deliberately carries no field for the matched text itself — only enough to
locate (`filepath`, `line_number`) and classify (`secret_type`) the finding.
This is a stronger guarantee than redacting at write time: there is no code
path by which a live credential could ever reach a report, because there is
no field to carry it in.

# Fields
- `filepath`: path to the file containing the finding
- `line_number`: line number of the finding
- `secret_type`: human-readable label for the matched pattern (e.g. `"AWS access key ID"`)
"""
struct SecretFinding
    filepath::String
    line_number::Int
    secret_type::String
end

"""
    scan_secrets(codefiles::Vector{String}) -> Vector{SecretFinding}

Scan `codefiles` line-by-line for common API-key/credential formats
(`SECRET_PATTERNS`, shared with `redact_secrets` in `reporting.jl`). Stops at
the first matching pattern per line — a line worth alerting on doesn't need
a second match counted.
"""
function scan_secrets(codefiles::Vector{String})::Vector{SecretFinding}
    findings = SecretFinding[]

    for filepath in codefiles
        isfile(filepath) || continue
        try
            open(filepath, "r") do io
                for (i, line) in enumerate(eachline(io))
                    isempty(strip(line)) && continue
                    for (secret_type, pat) in SECRET_PATTERNS
                        if occursin(pat, line)
                            push!(findings, SecretFinding(filepath, i, secret_type))
                            break
                        end
                    end
                end
            end
        catch e
            @warn "Skipping $filepath: could not read as text" exception=e
        end
    end

    return findings
end
