using Documenter, PIIScanner

makedocs(sitename="PIIScanner.jl Documentation", 
        modules = [PIIScanner],
        authors = "Florian Oswald",
        repo = Documenter.Remotes.GitHub("floswald","PIIScanner.jl"))


deploydocs(
        repo = "github.com/floswald/PIIScanner.jl.git",
        versions = nothing
        )