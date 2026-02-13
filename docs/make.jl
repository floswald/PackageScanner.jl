using Documenter, PackageScanner

makedocs(sitename="PackageScanner.jl Documentation", 
        modules = [PackageScanner],
        authors = "Florian Oswald",
        repo = Documenter.Remotes.GitHub("floswald","PackageScanner.jl"))


deploydocs(
        repo = "github.com/floswald/PackageScanner.jl.git",
        versions = nothing
        )