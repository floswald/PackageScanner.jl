@testitem "SecretFinding - cannot carry raw matched text" begin
    using PackageScanner

    # By construction: no field exists to hold matched text at all.
    @test fieldnames(PackageScanner.SecretFinding) == (:filepath, :line_number, :secret_type)

    fake_key = "sk-proj-" * "Ab3" ^ 10
    tmp = mktempdir()
    f = joinpath(tmp, "creds.py")
    open(f, "w") do io
        println(io, "key = \"$fake_key\"")
    end

    findings = PackageScanner.scan_secrets([f])
    @test length(findings) == 1
    @test !occursin(fake_key, string(findings[1]))
    @test !occursin(fake_key, repr(findings[1]))
end

@testitem "scan_secrets - detects one pattern per provider" begin
    using PackageScanner

    # Built via concatenation, not written as a contiguous literal, so these
    # synthetic fixtures can never look like a real credential to a secret
    # scanner reading this source file.
    fake_openai_key  = "sk-proj-" * "Ab3" ^ 10
    fake_aws_key     = "AKIA" * "IOSFODNN7EXAMPLE"
    fake_gh_token    = "ghp_" * "1234567890abcdef" ^ 3
    fake_slack_token = "xoxb-" * "1234567890" ^ 3
    fake_google_key  = "AIza" * "A" ^ 35

    tmp = mktempdir()
    f = joinpath(tmp, "creds.py")
    open(f, "w") do io
        println(io, "openai_key = \"$fake_openai_key\"")
        println(io, "aws_key = \"$fake_aws_key\"")
        println(io, "gh_token = \"$fake_gh_token\"")
        println(io, "slack_token = \"$fake_slack_token\"")
        println(io, "google_key = \"$fake_google_key\"")
    end

    findings = PackageScanner.scan_secrets([f])
    types = Set(x.secret_type for x in findings)

    @test length(findings) == 5
    @test "OpenAI project key" in types
    @test "AWS access key ID" in types
    @test "GitHub token" in types
    @test "Slack token" in types
    @test "Google API key" in types
end

@testitem "scan_secrets - correct file and line number" begin
    using PackageScanner

    fake_key = "sk-proj-" * "Ab3" ^ 10
    tmp = mktempdir()
    f = joinpath(tmp, "script.py")
    open(f, "w") do io
        println(io, "# comment")
        println(io, "x = 1")
        println(io, "key = \"$fake_key\"")
    end

    findings = PackageScanner.scan_secrets([f])
    @test length(findings) == 1
    @test findings[1].filepath == f
    @test findings[1].line_number == 3
end

@testitem "scan_secrets - no false positives on clean code" begin
    using PackageScanner

    tmp = mktempdir()
    f = joinpath(tmp, "clean.py")
    open(f, "w") do io
        println(io, "import os")
        println(io, "def main():")
        println(io, "    print('hello world')")
        println(io, "    x = os.environ.get('SOME_VAR')")
    end

    findings = PackageScanner.scan_secrets([f])
    @test isempty(findings)
end

@testitem "write_secrets_report - clean package" begin
    using PackageScanner

    tmp = mktempdir()
    PackageScanner.write_secrets_report(PackageScanner.SecretFinding[], tmp)
    content = read(joinpath(tmp, "report-secrets.md"), String)
    @test occursin("No credentials detected", content)
    @test !occursin("ALERT", content)
end

@testitem "write_secrets_report - alerts on findings, no raw text" begin
    using PackageScanner

    fake_key = "sk-proj-" * "Ab3" ^ 10
    tmp = mktempdir()
    findings = [PackageScanner.SecretFinding("src/classify.py", 49, "OpenAI project key")]
    PackageScanner.write_secrets_report(findings, tmp)

    content = read(joinpath(tmp, "report-secrets.md"), String)
    @test occursin("ALERT", content)
    @test occursin("src/classify.py", content)
    @test occursin("49", content)
    @test occursin("OpenAI project key", content)
    @test !occursin(fake_key, content)
end
