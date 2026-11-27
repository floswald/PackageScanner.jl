@testitem "is_journal_office_upload" begin
    using PackageScanner
    @test PackageScanner.is_journal_office_upload("/some/dir/Connie - 20200631.zip")
    @test !PackageScanner.is_journal_office_upload("/some/dir/pablo brañas garza - revised ms.pdf")
end

@testitem "find_paper_pdf - prefers author upload over journal-office upload" begin
    using PackageScanner
    mktempdir() do dir
        write(joinpath(dir, "Connie - 123.pdf"), "journal office copy")
        write(joinpath(dir, "author draft.pdf"), "author copy")

        @test PackageScanner.find_paper_pdf(dir) == joinpath(dir, "author draft.pdf")
    end
end

@testitem "find_paper_pdf - falls back to journal-office upload if it's the only one" begin
    using PackageScanner
    mktempdir() do dir
        write(joinpath(dir, "Connie - 123.pdf"), "journal office copy")

        @test PackageScanner.find_paper_pdf(dir) == joinpath(dir, "Connie - 123.pdf")
    end
end

@testitem "find_paper_pdf - paper.pdf wins over everything, including journal-office naming" begin
    using PackageScanner
    mktempdir() do dir
        write(joinpath(dir, "Connie - 123.pdf"), "journal office copy")
        write(joinpath(dir, "paper.pdf"), "the real one")

        @test PackageScanner.find_paper_pdf(dir) == joinpath(dir, "paper.pdf")
    end
end

@testitem "find_paper_pdf - no pdf anywhere returns nothing, then finds one once added" begin
    using PackageScanner
    mktempdir() do dir
        @test isnothing(PackageScanner.find_paper_pdf(dir))

        write(joinpath(dir, "notes.txt"), "not a pdf")
        @test isnothing(PackageScanner.find_paper_pdf(dir))

        write(joinpath(dir, "appendix.pdf"), "fake pdf bytes")
        @test PackageScanner.find_paper_pdf(dir) == joinpath(dir, "appendix.pdf")

        # paper.pdf is preferred over an alphabetically-earlier file
        write(joinpath(dir, "AAA_cover_letter.pdf"), "fake pdf bytes")
        write(joinpath(dir, "paper.pdf"), "fake pdf bytes")
        @test PackageScanner.find_paper_pdf(dir) == joinpath(dir, "paper.pdf")
    end
end

@testitem "find_paper_pdf - recurses into subfolders" begin
    using PackageScanner
    mktempdir() do dir
        subdir = joinpath(dir, "paper-source")
        mkpath(subdir)
        write(joinpath(subdir, "main.pdf"), "fake pdf bytes")
        @test PackageScanner.find_paper_pdf(dir) == joinpath(subdir, "main.pdf")
    end
end

@testitem "claims_extraction_prompt - references the given path" begin
    using PackageScanner
    prompt = PackageScanner.claims_extraction_prompt("/tmp/flattened.tex")
    @test occursin("/tmp/flattened.tex", prompt)
    @test occursin("no code execution", prompt)
    @test occursin("Resolve cross-references", prompt)
    @test occursin("Skip purely conceptual figures", prompt)
end

@testitem "CLAIMS_JSON_SCHEMA - parses and has the expected fields" begin
    using PackageScanner
    using JSON
    schema = JSON.parse(PackageScanner.CLAIMS_JSON_SCHEMA)
    @test Set(keys(schema["properties"])) == Set(["data_sources", "data_processing_steps", "tables", "figures"])

    table_props = schema["properties"]["tables"]["items"]["properties"]
    @test haskey(table_props, "controls")
    @test haskey(table_props, "key_regressors")

    dps_props = schema["properties"]["data_processing_steps"]["items"]["properties"]
    @test Set(keys(dps_props)) == Set(["description", "variables_involved"])
end

@testitem "claude_jpe_config_dir - respects env, falls back to ~/.claude-jpe" begin
    using PackageScanner
    withenv("CLAUDE_CONFIG_DIR" => nothing) do
        @test PackageScanner.claude_jpe_config_dir() == joinpath(homedir(), ".claude-jpe")
    end
    withenv("CLAUDE_CONFIG_DIR" => "/custom/dir") do
        @test PackageScanner.claude_jpe_config_dir() == "/custom/dir"
    end
end

@testitem "build_claude_claims_cmd - flags and env" begin
    using PackageScanner
    withenv("CLAUDE_CONFIG_DIR" => "/custom/claude-config") do
        cmd = PackageScanner.build_claude_claims_cmd("/tmp/flattened.tex"; effort = "medium")
        cmd_str = string(cmd)
        @test occursin("--safe-mode", cmd_str)
        @test occursin("--tools", cmd_str)
        @test occursin("Read", cmd_str)
        @test occursin("--json-schema", cmd_str)
        @test occursin("--effort", cmd_str)
        @test occursin("medium", cmd_str)
        @test occursin("CLAUDE_CONFIG_DIR=/custom/claude-config", cmd_str)
        @test occursin("--add-dir", cmd_str)
        @test occursin("/tmp", cmd_str)
    end
end
