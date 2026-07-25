using Documenter
using PowerAnalytics
import DataStructures: OrderedDict
using DocumenterInterLinks
using Dates
using Literate

# UPDATE FOR CURRENT MODULE NAME HERE
const _DOCS_BASE_URL = "https://sienna-platform.github.io/PowerAnalytics.jl/stable"

ENV["GKSwstype"] = "100"  # Prevent GR from opening gksqt GUI

links = InterLinks(
    "Julia" => "https://docs.julialang.org/en/v1/",
    "InfrastructureSystems" => "https://sienna-platform.github.io/InfrastructureSystems.jl/stable/",
    "PowerSystems" => "https://sienna-platform.github.io/PowerSystems.jl/stable/",
    "PowerSimulations" => "https://sienna-platform.github.io/PowerSimulations.jl/stable/",
    "StorageSystemsSimulations" => "https://sienna-platform.github.io/StorageSystemsSimulations.jl/stable/",
    "HydroPowerSimulations" => "https://sienna-platform.github.io/HydroPowerSimulations.jl/dev/",
)

include(joinpath(@__DIR__, "make_tutorials.jl"))
make_tutorials()

pages = OrderedDict(
    "Welcome Page" => "index.md",
    "Tutorials" => Any[
        "Simulation Scenarios Analysis" => "tutorials/generated_PA_workflow_tutorial.md",
    ],
    "How to..." => Any[
        "How to group generation by fuel or technology category" => "how_to_guides/how_to_group_generation_by_fuel.md",
        "How to define a custom metric" => "how_to_guides/how_to_define_a_custom_metric.md",
    ],
    "Explanation" => Any[
        "How `PowerAnalytics` thinks" => "explanation/metrics_and_component_selectors.md",
        "Choosing built-in metrics" => "explanation/choosing_built_in_metrics.md",
    ],
    "Reference" => Any[
        "Public API" => "reference/public.md",
        "Developers" => ["Developer Guidelines" => "reference/developer_guidelines.md",
        "Internals" => "reference/internal.md"]]

)

# Run simulation scenarios for RTS-GMLC Tutorial
include(joinpath(@__DIR__, "src", "tutorials", "_run_scenarios_RTS_Tutorial.jl"))


makedocs(
    modules = [PowerAnalytics],
    format = Documenter.HTML(
        prettyurls = haskey(ENV, "GITHUB_ACTIONS"),
        size_threshold = nothing,),
    sitename = "PowerAnalytics.jl",
    authors = "Gabriel Konar-Steenberg and Clayton Barrows",
    pages = Any[p for p in pages],
    draft = false,
    plugins = [links]
)


deploydocs(
    repo= "github.com/Sienna-Platform/PowerAnalytics.jl",
    target="build",
    branch="gh-pages",
    devbranch="main",
    devurl="dev",
    push_preview=true,
    versions=["stable" => "v^", "v#.#"],
)
