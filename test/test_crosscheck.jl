@testitem "CROSSCHECK_JSON_SCHEMA - parses and has the expected fields" begin
    using PackageScanner
    using JSON
    schema = JSON.parse(PackageScanner.CROSSCHECK_JSON_SCHEMA)
    @test Set(keys(schema["properties"])) == Set(["verdicts", "orphan_code_files"])

    verdict_props = schema["properties"]["verdicts"]["items"]["properties"]
    @test Set(keys(verdict_props)) == Set(["claim_type", "claim_label", "verdict", "rationale", "supporting_files"])
    @test Set(verdict_props["verdict"]["enum"]) == Set(["Matched", "Plausible", "Missing"])
    @test Set(verdict_props["claim_type"]["enum"]) == Set(["data_source", "table", "figure"])
end

@testitem "read_or_placeholder" begin
    using PackageScanner
    mktempdir() do dir
        p = joinpath(dir, "exists.txt")
        write(p, "hello")
        @test PackageScanner.read_or_placeholder(p, "(missing)") == "hello"
        @test PackageScanner.read_or_placeholder(joinpath(dir, "nope.txt"), "(missing)") == "(missing)"
    end
end

@testitem "compute_coverage - full credit, half credit, zero credit" begin
    using PackageScanner
    verdicts = [
        Dict("claim_type" => "table", "verdict" => "Matched"),
        Dict("claim_type" => "table", "verdict" => "Plausible"),
        Dict("claim_type" => "table", "verdict" => "Missing"),
        Dict("claim_type" => "table", "verdict" => "Missing"),
    ]
    coverage = PackageScanner.compute_coverage(verdicts)
    # (1.0 + 0.5 + 0 + 0) / 4 = 37.5%
    @test coverage["overall"] == 37.5
    @test coverage["by_claim_type"]["table"] == 37.5
    @test coverage["n_claims"] == 4
end

@testitem "compute_coverage - breaks down by claim_type independently" begin
    using PackageScanner
    verdicts = [
        Dict("claim_type" => "data_source", "verdict" => "Matched"),
        Dict("claim_type" => "figure", "verdict" => "Missing"),
    ]
    coverage = PackageScanner.compute_coverage(verdicts)
    @test coverage["by_claim_type"]["data_source"] == 100.0
    @test coverage["by_claim_type"]["figure"] == 0.0
    @test coverage["overall"] == 50.0
end

@testitem "compute_coverage - empty verdicts returns missing, not an error" begin
    using PackageScanner
    coverage = PackageScanner.compute_coverage(Dict[])
    @test ismissing(coverage["overall"])
    @test coverage["n_claims"] == 0
end

@testitem "render_crosscheck_report - includes caveats, coverage table, verdicts, orphans" begin
    using PackageScanner
    verdicts = [
        Dict("claim_type" => "table", "claim_label" => "Table 3", "verdict" => "Matched",
             "rationale" => "found in analysis.R", "supporting_files" => ["analysis.R"]),
        Dict("claim_type" => "data_source", "claim_label" => "Census data", "verdict" => "Missing",
             "rationale" => "no reference found", "supporting_files" => String[]),
    ]
    coverage = PackageScanner.compute_coverage(verdicts)
    report = PackageScanner.render_crosscheck_report(verdicts, coverage, ["unused_script.R"])

    @test occursin("static plausibility only", lowercase(report))
    @test occursin("file-level citations only", lowercase(report))
    @test occursin("Table 3", report)
    @test occursin("analysis.R", report)
    @test occursin("Census data", report)
    @test occursin("unused_script.R", report)
    @test occursin("Overall", report)
end

@testitem "crosscheck_prompt - references bundle dir, warns against line-level citations" begin
    using PackageScanner
    prompt = PackageScanner.crosscheck_prompt("/tmp/bundle")
    @test occursin("/tmp/bundle", prompt)
    @test occursin("cannot see line", prompt)
    @test occursin("static plausibility", prompt)
end

@testitem "build_crosscheck_cmd - flags and env" begin
    using PackageScanner
    withenv("CLAUDE_CONFIG_DIR" => "/custom/claude-config") do
        cmd = PackageScanner.build_crosscheck_cmd("/tmp/bundle"; effort = "medium")
        cmd_str = string(cmd)
        @test occursin("--safe-mode", cmd_str)
        @test occursin("Read", cmd_str)
        @test occursin("--json-schema", cmd_str)
        @test occursin("CLAUDE_CONFIG_DIR=/custom/claude-config", cmd_str)
        @test occursin("--add-dir", cmd_str)
        @test occursin("/tmp/bundle", cmd_str)
    end
end
