@testitem "scan_llm_usage - detects one line per provider" begin
    using PackageScanner

    tmp = mktempdir()
    f = joinpath(tmp, "llm_calls.py")
    open(f, "w") do io
        println(io, "import openai")
        println(io, "import anthropic")
        println(io, "from google import genai")
        println(io, "import cohere")
        println(io, "from mistralai import Mistral")
        println(io, "client = AzureOpenAI(azure_endpoint=ENDPOINT)")
        println(io, "bedrock = boto3.client('bedrock-runtime')")
    end

    findings = PackageScanner.scan_llm_usage([f])
    providers = Set(x.provider for x in findings)

    @test length(findings) == 7
    @test "OpenAI" in providers
    @test "Anthropic" in providers
    @test "Google Gemini" in providers
    @test "Cohere" in providers
    @test "Mistral" in providers
    @test "Azure OpenAI" in providers
    @test "AWS Bedrock" in providers
end

@testitem "scan_llm_usage - detects direct REST calls by hostname" begin
    using PackageScanner

    tmp = mktempdir()
    f = joinpath(tmp, "curl_calls.r")
    open(f, "w") do io
        println(io, "httr::POST(\"https://api.openai.com/v1/chat/completions\")")
        println(io, "httr::POST(\"https://api.anthropic.com/v1/messages\")")
        println(io, "httr::GET(\"https://generativelanguage.googleapis.com/v1/models\")")
        println(io, "httr::POST(\"https://api.cohere.ai/v1/generate\")")
        println(io, "httr::POST(\"https://api.mistral.ai/v1/chat/completions\")")
    end

    findings = PackageScanner.scan_llm_usage([f])
    providers = Set(x.provider for x in findings)

    @test length(findings) == 5
    @test providers == Set(["OpenAI", "Anthropic", "Google Gemini", "Cohere", "Mistral"])
end

@testitem "scan_llm_usage - excludes local/open-weight model loading" begin
    using PackageScanner

    tmp = mktempdir()
    f = joinpath(tmp, "local_model.py")
    open(f, "w") do io
        println(io, "from transformers import AutoModelForCausalLM")
        println(io, "model = AutoModelForCausalLM.from_pretrained('gpt2')")
        println(io, "import ollama")
        println(io, "response = ollama.chat(model='llama3', messages=messages)")
    end

    findings = PackageScanner.scan_llm_usage([f])
    @test isempty(findings)
end

@testitem "scan_llm_usage - no false positives on plain non-LLM code" begin
    using PackageScanner

    tmp = mktempdir()
    f = joinpath(tmp, "clean.py")
    open(f, "w") do io
        println(io, "import pandas as pd")
        println(io, "df = pd.read_csv('data.csv')")
        println(io, "df.groupby('id').mean()")
    end

    findings = PackageScanner.scan_llm_usage([f])
    @test isempty(findings)
end

@testitem "scan_llm_usage - correct file, line, and context" begin
    using PackageScanner

    tmp = mktempdir()
    f = joinpath(tmp, "script.py")
    open(f, "w") do io
        println(io, "# comment")
        println(io, "x = 1")
        println(io, "  import openai  ")
    end

    findings = PackageScanner.scan_llm_usage([f])
    @test length(findings) == 1
    @test findings[1].filepath == f
    @test findings[1].line_number == 3
    @test findings[1].provider == "OpenAI"
    @test findings[1].context == "import openai"
end

@testitem "write_llm_usage_report - clean package" begin
    using PackageScanner

    tmp = mktempdir()
    PackageScanner.write_llm_usage_report(PackageScanner.LLMUsageFinding[], tmp)
    content = read(joinpath(tmp, "report-llm-reproducibility.md"), String)
    @test occursin("No LLM API usage detected", content)
    @test !occursin("ALERT", content)
end

@testitem "write_llm_usage_report - alerts, groups by provider, cites the paper" begin
    using PackageScanner

    tmp = mktempdir()
    findings = [
        PackageScanner.LLMUsageFinding("src/classify.py", 12, "OpenAI", "import openai"),
        PackageScanner.LLMUsageFinding("src/classify.py", 20, "Anthropic", "import anthropic"),
    ]
    PackageScanner.write_llm_usage_report(findings, tmp)

    content = read(joinpath(tmp, "report-llm-reproducibility.md"), String)
    @test occursin("LLM API usage detected", content)
    @test occursin("### OpenAI", content)
    @test occursin("### Anthropic", content)
    @test occursin("src/classify.py", content)
    @test occursin("arxiv.org/abs/2607.24372", content)
    @test occursin("temperature", content)
end
