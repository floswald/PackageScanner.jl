# LLM Usage Scanner Module
# Detects calls to proprietary/hosted LLM APIs in code files, as a
# reproducibility flag rather than a security issue -- kept as a genuinely
# separate module from CodeQualityScanner.jl because its report needs a
# multi-paragraph explanation plus a citation link, not a one-line context
# string grouped by language.

"""
    LLMUsageFinding

A single detection of code that calls a proprietary/hosted LLM API.

Unlike `SecretFinding`, `context` here is safe to show verbatim: matching an
`import openai` line is not a secret.

# Fields
- `filepath`: path to the file containing the finding
- `line_number`: line number of the finding
- `provider`: the LLM provider/service matched (e.g. `"OpenAI"`, `"AWS Bedrock"`)
- `context`: the matched line, stripped of leading/trailing whitespace
"""
struct LLMUsageFinding
    filepath::String
    line_number::Int
    provider::String
    context::String
end

"""
    LLM_PROVIDER_PATTERNS

Patterns for proprietary/hosted LLM API usage across Python, R, and Stata:
SDK imports/constructors and direct REST calls to each provider's hostname.

Deliberately excludes purely local/open-weight model loading (e.g.
`AutoModelForCausalLM.from_pretrained`, local `ollama` calls) -- consistent
with the reproducibility literature's own recommendation that local
execution is the more-reproducible path. This is a scoping choice, not a
technical limitation: none of these patterns match transformers/ollama
usage, so nothing needs to be explicitly filtered out.
"""
const LLM_PROVIDER_PATTERNS = [
    ("OpenAI",       r"(import\s+openai|from\s+openai\s+import|\bopenai\.OpenAI\s*\(|\bOpenAI\s*\(|api\.openai\.com)"i),
    ("Anthropic",    r"(import\s+anthropic|from\s+anthropic\s+import|\bAnthropic\s*\(|api\.anthropic\.com)"i),
    ("Google Gemini",r"(import\s+google\.generativeai|from\s+google\s+import\s+genai|import\s+google\.genai|generativelanguage\.googleapis\.com)"i),
    ("Cohere",       r"(import\s+cohere|from\s+cohere\s+import|api\.cohere\.ai)"i),
    ("Mistral",      r"(import\s+mistralai|from\s+mistralai\s+import|api\.mistral\.ai)"i),
    ("Azure OpenAI", r"(AzureOpenAI\s*\(|azure_endpoint|AZURE_OPENAI_[A-Z_]+|openai\.api_type\s*=\s*[\"']azure[\"'])"i),
    ("AWS Bedrock",  r"(boto3\.client\s*\(\s*[\"']bedrock|bedrock-runtime)"i),
]

"""
    scan_llm_usage(codefiles::Vector{String}) -> Vector{LLMUsageFinding}

Scan `codefiles` line-by-line for calls to proprietary/hosted LLM APIs
(`LLM_PROVIDER_PATTERNS`). Stops at the first matching provider per line.
"""
function scan_llm_usage(codefiles::Vector{String})::Vector{LLMUsageFinding}
    findings = LLMUsageFinding[]

    for filepath in codefiles
        isfile(filepath) || continue
        try
            open(filepath, "r") do io
                for (i, line) in enumerate(eachline(io))
                    isempty(strip(line)) && continue
                    for (provider, pat) in LLM_PROVIDER_PATTERNS
                        if occursin(pat, line)
                            push!(findings, LLMUsageFinding(filepath, i, provider, strip(line)))
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
