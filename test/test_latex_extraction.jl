@testitem "find_tex_roots - excludes preamble, tables, and latexdiff artifacts" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "preamble.tex"), "\\usepackage{amsmath}\n")
        mkpath(joinpath(dir, "tables"))
        write(joinpath(dir, "tables", "table1.tex"), "\\begin{tabular}{c}1\\end{tabular}\n")
        write(joinpath(dir, "main.tex"), "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n")
        write(joinpath(dir, "main_diff.tex"), "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n")

        roots = PackageScanner.find_tex_roots(dir)
        @test roots == [abspath(joinpath(dir, "main.tex"))]
    end
end

@testitem "substitute_macros - resolves known tokens, leaves unknown alone" begin
    using PackageScanner
    macros = Dict("inputpath" => "inputs/", "tabdir" => "tables")
    @test PackageScanner.substitute_macros("\\inputpath/\\tabdir/foo", macros) == "inputs//tables/foo"
    @test PackageScanner.substitute_macros("\\unknownmacro/foo", macros) == "\\unknownmacro/foo"
end

@testitem "resolve_include_path - normalizes double slashes, appends .tex" begin
    using PackageScanner
    mktempdir() do dir
        mkpath(joinpath(dir, "inputs", "tables"))
        write(joinpath(dir, "inputs", "tables", "estimation.tex"), "content")
        macros = Dict("inputpath" => "inputs/", "tabdir" => "tables")
        resolved = PackageScanner.resolve_include_path("\\inputpath/\\tabdir/estimation", dir, macros)
        @test resolved == abspath(joinpath(dir, "inputs", "tables", "estimation.tex"))
        @test isfile(resolved)
    end
end

@testitem "extract_latex_text - flattens multi-file tree with macro-pathed includes" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "preamble.tex"), "\\usepackage{amsmath}\n")

        mkpath(joinpath(dir, "inputs", "tables"))
        write(joinpath(dir, "inputs", "tables", "estimation.tex"), "ESTIMATION TABLE CONTENT")

        write(joinpath(dir, "main.tex"), """
        \\documentclass{article}
        \\input{preamble}
        \\newcommand{\\inputpath}{inputs/}
        \\newcommand{\\tabdir}{tables}
        \\begin{document}
        Body text before table.
        \\input{\\inputpath/\\tabdir/estimation}
        % \\input{\\inputpath/\\tabdir/should_not_be_included}
        \\includegraphics{\\inputpath/figs/plot.pdf}
        \\end{document}
        """)

        result = PackageScanner.extract_latex_text(dir)

        @test !result.ambiguous
        @test length(result.roots) == 1
        @test occursin("ESTIMATION TABLE CONTENT", result.text)
        @test occursin("Body text before table.", result.text)
        # commented-out include must not be followed
        @test !occursin("should_not_be_included", result.text)
        # includegraphics left untouched, not treated as an include
        @test occursin("\\includegraphics{\\inputpath/figs/plot.pdf}", result.text)
        @test isempty(result.unresolved)
    end
end

@testitem "extract_latex_text - unresolved include recorded, not silently dropped" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "main.tex"), """
        \\documentclass{article}
        \\begin{document}
        \\input{does_not_exist}
        \\end{document}
        """)

        result = PackageScanner.extract_latex_text(dir)

        @test length(result.unresolved) == 1
        @test result.unresolved[1][1] == "input"
        @test result.unresolved[1][2] == "does_not_exist"
        @test occursin("UNRESOLVED INCLUDE", result.text)
    end
end

@testitem "extract_latex_text - no tex at all signals empty, not ambiguous" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "paper.pdf"), "not actually a pdf")

        result = PackageScanner.extract_latex_text(dir)

        @test result.text == ""
        @test isempty(result.roots)
        @test !result.ambiguous
    end
end

@testitem "extract_latex_text - multiple candidate roots are flagged ambiguous, not guessed" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "draft_v1.tex"), "\\documentclass{article}\n\\begin{document}\nOld draft\n\\end{document}\n")
        write(joinpath(dir, "draft_v2.tex"), "\\documentclass{article}\n\\begin{document}\nNew draft\n\\end{document}\n")

        result = PackageScanner.extract_latex_text(dir)

        @test result.ambiguous
        @test result.text == ""
        @test length(result.roots) == 2
    end
end

@testitem "extract_latex_text - main_files given explicitly bypasses ambiguity check" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "draft_v1.tex"), "\\documentclass{article}\n\\begin{document}\nOld draft\n\\end{document}\n")
        write(joinpath(dir, "draft_v2.tex"), "\\documentclass{article}\n\\begin{document}\nNew draft\n\\end{document}\n")

        result = PackageScanner.extract_latex_text(dir; main_files = [joinpath(dir, "draft_v2.tex")])

        @test !result.ambiguous
        @test occursin("New draft", result.text)
        @test !occursin("Old draft", result.text)
    end
end

@testitem "extract_latex_text - cyclic self-include does not infinite-loop" begin
    using PackageScanner

    mktempdir() do dir
        write(joinpath(dir, "main.tex"), """
        \\documentclass{article}
        \\begin{document}
        \\input{main}
        \\end{document}
        """)

        result = PackageScanner.extract_latex_text(dir)

        @test occursin("CYCLIC INCLUDE SKIPPED", result.text)
    end
end
