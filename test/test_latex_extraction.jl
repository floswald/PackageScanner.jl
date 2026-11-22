@testitem "extract_latex_text: no .tex source found" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "notes.txt"), "no latex here")

    result = PackageScanner.extract_latex_text(tmpdir)

    @test isempty(result.roots)
    @test result.text == ""
    @test result.ambiguous == false
end

@testitem "extract_latex_text: single root, no includes" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "main.tex"), """
    \\documentclass{article}
    \\begin{document}
    Hello world.
    \\end{document}
    """)

    result = PackageScanner.extract_latex_text(tmpdir)

    @test result.ambiguous == false
    @test length(result.roots) == 1
    @test occursin("Hello world.", result.text)
    @test isempty(result.unresolved)
end

@testitem "extract_latex_text: nested \\input is flattened" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "main.tex"), """
    \\documentclass{article}
    \\begin{document}
    \\input{chapter1}
    \\end{document}
    """)
    write(joinpath(tmpdir, "chapter1.tex"), "Chapter one text. \\input{subsection}")
    write(joinpath(tmpdir, "subsection.tex"), "Subsection text.")

    result = PackageScanner.extract_latex_text(tmpdir)

    @test occursin("Chapter one text.", result.text)
    @test occursin("Subsection text.", result.text)
    @test isempty(result.unresolved)
end

@testitem "extract_latex_text: \\include resolves without extension in target" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "main.tex"), """
    \\documentclass{article}
    \\begin{document}
    \\include{appendix}
    \\end{document}
    """)
    write(joinpath(tmpdir, "appendix.tex"), "Appendix content here.")

    result = PackageScanner.extract_latex_text(tmpdir)

    @test occursin("Appendix content here.", result.text)
end

@testitem "extract_latex_text: multiple roots are ambiguous" begin
    using PackageScanner
    tmpdir = mktempdir()
    for name in ("paper", "appendix")
        write(joinpath(tmpdir, "$name.tex"), """
        \\documentclass{article}
        \\begin{document}
        content of $name
        \\end{document}
        """)
    end

    result = PackageScanner.extract_latex_text(tmpdir)

    @test result.ambiguous == true
    @test length(result.roots) == 2
    @test result.text == ""
end

@testitem "extract_latex_text: main_files overrides auto-detection" begin
    using PackageScanner
    tmpdir = mktempdir()
    for name in ("paper", "appendix")
        write(joinpath(tmpdir, "$name.tex"), """
        \\documentclass{article}
        \\begin{document}
        content of $name
        \\end{document}
        """)
    end

    paper_path = joinpath(tmpdir, "paper.tex")
    appendix_path = joinpath(tmpdir, "appendix.tex")
    result = PackageScanner.extract_latex_text(tmpdir; main_files = [paper_path, appendix_path])

    @test result.ambiguous == false
    @test occursin("content of paper", result.text)
    @test occursin("content of appendix", result.text)
end

@testitem "extract_latex_text: missing \\input target is recorded, not dropped" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "main.tex"), """
    \\documentclass{article}
    \\begin{document}
    \\input{missing_chapter}
    \\end{document}
    """)

    result = PackageScanner.extract_latex_text(tmpdir)

    @test length(result.unresolved) == 1
    @test result.unresolved[1][2] == "missing_chapter"
    @test occursin("\\input{missing_chapter}", result.text)
end

@testitem "extract_latex_text: commented-out \\input is not flattened" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "main.tex"), """
    \\documentclass{article}
    \\begin{document}
    % \\input{draft_notes}
    kept text
    \\end{document}
    """)
    write(joinpath(tmpdir, "draft_notes.tex"), "SHOULD NOT APPEAR")

    result = PackageScanner.extract_latex_text(tmpdir)

    @test !occursin("SHOULD NOT APPEAR", result.text)
    @test occursin("kept text", result.text)
end

@testitem "extract_latex_text: circular \\input terminates" begin
    using PackageScanner
    tmpdir = mktempdir()
    write(joinpath(tmpdir, "main.tex"), """
    \\documentclass{article}
    \\begin{document}
    \\input{a}
    \\end{document}
    """)
    write(joinpath(tmpdir, "a.tex"), "A text. \\input{b}")
    write(joinpath(tmpdir, "b.tex"), "B text. \\input{a}")

    result = PackageScanner.extract_latex_text(tmpdir)

    @test occursin("A text.", result.text)
    @test occursin("B text.", result.text)
    @test any(u -> u[2] == "circular \\input/\\include, not re-expanded", result.unresolved)
end

@testitem "extract_pdf_text: returns extract_latex_text-compatible shape" begin
    using PackageScanner
    fixture = joinpath(@__DIR__, "data", "sample_readme.pdf")

    result = PackageScanner.extract_pdf_text(fixture)

    @test result.roots == [fixture]
    @test result.ambiguous == false
    @test isempty(result.unresolved)
    @test occursin("confidential survey data", result.text)
end

@testitem "extract_pdf_text: errors on missing file" begin
    using PackageScanner
    @test_throws ErrorException PackageScanner.extract_pdf_text(joinpath(@__DIR__, "data", "does_not_exist.pdf"))
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
