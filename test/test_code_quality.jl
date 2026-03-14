const CQ_CONFIG = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")

# ---------------------------------------------------------------------------
# Rule 1: Missing random seed
# ---------------------------------------------------------------------------

@testitem "Rule1 - missing seed flagged in Stata" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.do")
    open(f, "w") do io
        println(io, "bootstrap, reps(100): reg y x")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "missing_seed" && x.language == "stata" && x.risk_level == :critical, findings)
end

@testitem "Rule1 - seed present clears Stata finding" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.do")
    open(f, "w") do io
        println(io, "set seed 42")
        println(io, "bootstrap, reps(100): reg y x")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "missing_seed" && x.language == "stata", findings)
end

@testitem "Rule1 - missing seed flagged in R" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.R")
    open(f, "w") do io
        println(io, "x <- rnorm(100)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "missing_seed" && x.language == "r" && x.risk_level == :critical, findings)
end

@testitem "Rule1 - seed present clears R finding" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.R")
    open(f, "w") do io
        println(io, "set.seed(123)")
        println(io, "x <- rnorm(100)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "missing_seed" && x.language == "r", findings)
end

@testitem "Rule1 - missing seed flagged in Python" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.py")
    open(f, "w") do io
        println(io, "import numpy as np")
        println(io, "x = np.random.randn(100)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "missing_seed" && x.language == "python" && x.risk_level == :critical, findings)
end

@testitem "Rule1 - seed present clears Python finding" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.py")
    open(f, "w") do io
        println(io, "import numpy as np")
        println(io, "np.random.seed(0)")
        println(io, "x = np.random.randn(100)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "missing_seed" && x.language == "python", findings)
end

@testitem "Rule1 - missing seed flagged in Julia" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.jl")
    open(f, "w") do io
        println(io, "x = rand(100)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "missing_seed" && x.language == "julia" && x.risk_level == :critical, findings)
end

@testitem "Rule1 - seed present clears Julia finding" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "analysis.jl")
    open(f, "w") do io
        println(io, "using Random")
        println(io, "Random.seed!(42)")
        println(io, "x = rand(100)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "missing_seed" && x.language == "julia", findings)
end

@testitem "Rule1 - no triggers means no seed finding" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "clean.R")
    open(f, "w") do io
        println(io, "df <- read.csv('data.csv')")
        println(io, "summary(df)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "missing_seed", findings)
end

# ---------------------------------------------------------------------------
# Rule 2: Hardcoded absolute paths
# ---------------------------------------------------------------------------

@testitem "Rule2 - Unix home path flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "run.do")
    open(f, "w") do io
        println(io, raw"""use "/Users/alice/data/panel.dta" """)
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "absolute_path" && x.risk_level == :critical, findings)
end

@testitem "Rule2 - Windows path flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "run.R")
    open(f, "w") do io
        println(io, raw"""df <- read.csv("C:\\Users\\bob\\data.csv")""")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "absolute_path" && x.risk_level == :critical, findings)
end

@testitem "Rule2 - relative path not flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "run.py")
    open(f, "w") do io
        println(io, """df = pd.read_csv("data/panel.csv")""")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "absolute_path", findings)
end

@testitem "Rule2 - correct line number recorded" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "run.R")
    open(f, "w") do io
        println(io, "library(dplyr)")
        println(io, raw"""df <- read.csv("/home/carol/data.csv")""")
        println(io, "summary(df)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    match = findfirst(x -> x.rule == "absolute_path", findings)
    @test !isnothing(match)
    @test findings[match].line_number == 2
end

# ---------------------------------------------------------------------------
# Rule 3: merge m:m
# ---------------------------------------------------------------------------

@testitem "Rule3 - merge m:m flagged in Stata" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.do")
    open(f, "w") do io
        println(io, "merge m:m id using extra.dta")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "merge_mm" && x.risk_level == :critical, findings)
end

@testitem "Rule3 - merge 1:m not flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.do")
    open(f, "w") do io
        println(io, "merge 1:m id using extra.dta")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "merge_mm", findings)
end

@testitem "Rule3 - merge m:m correct line number" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.do")
    open(f, "w") do io
        println(io, "use master.dta, clear")
        println(io, "sort id")
        println(io, "merge m:m id using extra.dta")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    m = findfirst(x -> x.rule == "merge_mm", findings)
    @test !isnothing(m)
    @test findings[m].line_number == 3
end

# ---------------------------------------------------------------------------
# Rule 4: Undocumented sample drops
# ---------------------------------------------------------------------------

@testitem "Rule4 - undocumented Stata drop flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "clean.do")
    open(f, "w") do io
        println(io, "use data.dta, clear")
        println(io, "drop if age < 0")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "undocumented_drop" && x.risk_level == :advisory, findings)
end

@testitem "Rule4 - commented Stata drop not flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "clean.do")
    open(f, "w") do io
        println(io, "use data.dta, clear")
        println(io, "* Remove implausible ages")
        println(io, "drop if age < 0")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "undocumented_drop" && x.language == "stata", findings)
end

@testitem "Rule4 - undocumented R filter flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "clean.R")
    open(f, "w") do io
        println(io, "df <- read.csv('data.csv')")
        println(io, "df2 <- filter(df, age > 0)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "undocumented_drop" && x.language == "r" && x.risk_level == :advisory, findings)
end

@testitem "Rule4 - commented R filter not flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "clean.R")
    open(f, "w") do io
        println(io, "df <- read.csv('data.csv')")
        println(io, "# keep only valid ages")
        println(io, "df2 <- filter(df, age > 0)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "undocumented_drop" && x.language == "r", findings)
end

@testitem "Rule4 - undocumented Python query flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "clean.py")
    open(f, "w") do io
        println(io, "df = pd.read_csv('data.csv')")
        println(io, "df2 = df.query('age > 0')")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "undocumented_drop" && x.language == "python" && x.risk_level == :advisory, findings)
end

# ---------------------------------------------------------------------------
# Rule 5: Merge without explicit join type
# ---------------------------------------------------------------------------

@testitem "Rule5 - R merge without all= flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.R")
    open(f, "w") do io
        println(io, "panel <- merge(left, right, by='id')")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "implicit_join" && x.language == "r" && x.risk_level == :advisory, findings)
end

@testitem "Rule5 - R merge with all.x= not flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.R")
    open(f, "w") do io
        println(io, "panel <- merge(left, right, by='id', all.x=TRUE)")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "implicit_join" && x.language == "r", findings)
end

@testitem "Rule5 - Python merge without how= flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.py")
    open(f, "w") do io
        println(io, "panel = pd.merge(left, right, on='id')")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test any(x -> x.rule == "implicit_join" && x.language == "python" && x.risk_level == :advisory, findings)
end

@testitem "Rule5 - Python merge with how= not flagged" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    dir = mktempdir()
    f = joinpath(dir, "build.py")
    open(f, "w") do io
        println(io, "panel = pd.merge(left, right, on='id', how='left')")
    end
    findings = PackageScanner.scan_code_quality([f], cfg)
    @test !any(x -> x.rule == "implicit_join" && x.language == "python", findings)
end

# ---------------------------------------------------------------------------
# Report writing
# ---------------------------------------------------------------------------

@testitem "write_code_quality_report - empty findings" begin
    using PackageScanner
    out = mktempdir()
    PackageScanner.write_code_quality_report(PackageScanner.CodeQualityFinding[], out)
    content = read(joinpath(out, "report-code-quality.md"), String)
    @test occursin("No code quality issues", content)
end

@testitem "write_code_quality_report - findings appear in report" begin
    using PackageScanner
    cfg = joinpath(pkgdir(PackageScanner), "config", "code_quality_patterns.toml")
    out = mktempdir()
    dir = mktempdir()

    f = joinpath(dir, "build.do")
    open(f, "w") do io
        println(io, "merge m:m id using extra.dta")
    end

    findings = PackageScanner.scan_code_quality([f], cfg)
    PackageScanner.write_code_quality_report(findings, out)

    content = read(joinpath(out, "report-code-quality.md"), String)
    @test occursin("CRITICAL", content)
    @test occursin("merge_mm", content) || occursin("merge m:m", content)
end
