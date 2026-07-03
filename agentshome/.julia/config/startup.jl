import Pkg as var"#Pkg"

if isnothing(Base.find_package("Revise"))
    var"#Pkg".add("Revise")
end

if !isfile(joinpath(first(DEPOT_PATH), "bin", "kaimon"))
    var"#Pkg".Apps.add("Kaimon")
end

atreplinit() do repl
    try
        @eval using Revise
    catch e
        @warn "Could not load Revise" exception = e
    end
end
