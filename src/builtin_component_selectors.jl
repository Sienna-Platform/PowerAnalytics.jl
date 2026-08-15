const FUEL_TYPES_DATA_FILE =
    joinpath(dirname(dirname(pathof(PowerAnalytics))), "deps", "generator_mapping.yaml")
const FUEL_TYPES_META_KEY = "__META"

"""
Parse the `gentype` to a type. This is done by first checking whether gentype is qualified
(`ModuleName.TypeName`). If so, the module is fetched from the `Main` scope and the type
name is fetched from the module. If not, we default to fetching from `PowerSystems` for
convenience.
"""
function lookup_gentype(gentype::AbstractString)
    if occursin(".", gentype)
        splitted = split(gentype, ".")
        (length(splitted) == 2) || throw(ArgumentError("Cannot parse gentype '$gentype'"))
        mod, typename = splitted
        return getproperty(getproperty(Main, Symbol(mod)), Symbol(typename))
    end
    return getproperty(PowerSystems, Symbol(gentype))
end

# Parse the strings in generator_mapping.yaml into types and enum items
function parse_fuel_category(
    category_spec::Dict;
    root_type::Type{<:Component} = PSY.StaticInjection,
)
    gen_type = lookup_gentype(get(category_spec, "gentype", "Component"))
    (gen_type === Any) && (gen_type = root_type)
    # Constrain gen_type such that gen_type <: root_type
    gen_type = typeintersect(gen_type, root_type)

    pm = get(category_spec, "primemover", nothing)
    isnothing(pm) || (pm = PSY.get_enum_value(PSY.PrimeMovers, pm))

    fc = get(category_spec, "fuel", nothing)
    isnothing(fc) || (fc = PSY.get_enum_value(PSY.ThermalFuels, fc))

    return gen_type, pm, fc
end

function make_fuel_component_selector(
    category_spec::Dict;
    root_type::Type{<:Component} = PSY.StaticInjection,
)
    parse_results = parse_fuel_category(category_spec; root_type = root_type)
    (gen_type, prime_mover, fuel_category) = parse_results
    # If gen_type is the bottom type, it means it doesn't fit in root_type and we shouldn't include the selector at all
    (gen_type <: Union{}) && return nothing

    function filter_closure(comp::Component)
        comp_sig = Tuple{typeof(comp)}
        if !isnothing(prime_mover)
            hasmethod(PowerSystems.get_prime_mover_type, comp_sig) || return false
            (PowerSystems.get_prime_mover_type(comp) == prime_mover) || return false
        end
        if !isnothing(fuel_category)
            hasmethod(PowerSystems.get_fuel, comp_sig) || return false
            (PowerSystems.get_fuel(comp) == fuel_category) || return false
        end
        return true
    end

    # Create a nice name that is guaranteed to never collide with fully-qualified component names
    selector_name = string(nameof(parse_results[1]))
    if !all(isnothing.(parse_results[2:end]))
        selector_name *=
            COMPONENT_NAME_DELIMITER * join(
                ifelse.(
                    isnothing.(parse_results[2:end]),
                    "Any",
                    string.(parse_results[2:end])),
                COMPONENT_NAME_DELIMITER)
    end

    return make_selector(filter_closure, gen_type; name = selector_name)
end

# Based on old PowerAnalytics' get_generator_mapping
"""
Parse a `generator_mapping.yaml` file into a dictionary of `ComponentSelector`s and a
dictionary of metadata if present.

# Arguments

  - `filename`: the path to the `generator_mapping.yaml` file
  - `root_type::Type{<:Component} = PSY.StaticInjection`: the [`Component`](@extref
    PowerSystems.Component) type assumed in cases where there is no more precise information
"""
function parse_generator_mapping_file(
    filename;
    root_type::Type{<:Component} = PSY.StaticInjection,
)
    # NOTE the YAML library does not support ordered loading
    in_data = open(YAML.load, filename)
    mappings = Dict{String, ComponentSelector}()
    for top_level in keys(in_data)
        (top_level == FUEL_TYPES_META_KEY) && continue
        subselectors =
            make_fuel_component_selector.(
                in_data[top_level]; root_type = root_type)
        # A subselector will be nothing if it doesn't fit under root_type
        subselectors = filter(!isnothing, subselectors)
        # Omit the category entirely if root_type causes elimination of all subselectors
        (length(in_data[top_level]) > 0 && isempty(subselectors)) && continue
        mappings[top_level] = make_selector(subselectors...; name = top_level)
    end
    return mappings, get(in_data, FUEL_TYPES_META_KEY, nothing)
end

"""
Use [`parse_generator_mapping_file`](@ref) to parse a `generator_mapping.yaml` file into a
dictionary of all `ComponentSelector`s.

# Arguments

  - `filename`: the path to the `generator_mapping.yaml` file
  - `root_type::Type{<:Component} = PSY.StaticInjection`: the [`Component`](@extref
    PowerSystems.Component) type assumed in cases where there is no more precise information

See also: [`parse_generator_categories`](@ref) if only generators are desired
"""
parse_injector_categories(filename; root_type::Type{<:Component} = PSY.StaticInjection) =
    first(parse_generator_mapping_file(filename; root_type = root_type))

"""
Use [`parse_generator_mapping_file`](@ref) to parse a `generator_mapping.yaml` file into a
dictionary of `ComponentSelector`s, excluding categories in the 'non_generators' list in
metadata.

# Arguments

  - `filename`: the path to the `generator_mapping.yaml` file
  - `root_type::Type{<:Component} = PSY.StaticInjection`: the [`Component`](@extref
    PowerSystems.Component) type assumed in cases where there is no more precise information

See also: [`parse_injector_categories`](@ref) if all injectors are desired
"""
function parse_generator_categories(filename;
    root_type::Type{<:Component} = PSY.StaticInjection)
    categories, meta = parse_generator_mapping_file(filename; root_type = root_type)
    (isnothing(meta) || !haskey(meta, "non_generators")) && return nothing
    return filter(pair -> !(first(pair) in meta["non_generators"]), categories)
end

# SELECTORS MODULE
"""
PowerAnalytics built-in `ComponentSelector`s. Use `names` to list what is available.

# Examples

```julia
using PowerAnalytics
names(PowerAnalytics.Selectors)  # lists built-in selectors
PowerAnalytics.Selectors.all_loads  # by default, must prefix built-in selectors with the module name
@isdefined all_loads  # -> false
using PowerAnalytics.Selectors
@isdefined all_loads  # -> true, can now refer to built-in selectors without the prefix
```
"""
module Selectors
import
    ..make_selector,
    ..PSY,
    ..parse_generator_mapping_file,
    ..parse_injector_categories,
    ..parse_generator_categories,
    ..ComponentSelector,
    ..FUEL_TYPES_DATA_FILE
export
    all_loads,
    all_storage,
    injector_categories,
    generator_categories,
    categorized_injectors,
    categorized_generators

"A `ComponentSelector` representing all the electric load in a [`System`](@extref PowerSystems.System)"
const all_loads::ComponentSelector = make_selector(PSY.ElectricLoad)

"A `ComponentSelector` representing all the storage in a [`System`](@extref PowerSystems.System)"
const all_storage::ComponentSelector = make_selector(PSY.Storage)

"""
A dictionary of `ComponentSelector`s, each of which corresponds to one of the static
injector categories in `generator_mapping.yaml`
"""
const injector_categories::AbstractDict{String, ComponentSelector} =
    parse_injector_categories(FUEL_TYPES_DATA_FILE)

"""
A dictionary of `ComponentSelector`s, each of which corresponds to one of the categories in
`generator_mapping.yaml`, only considering the components and categories that represent
generators (no storage or load)
"""
const generator_categories::Union{AbstractDict{String, ComponentSelector}, Nothing} = let
    result = parse_generator_categories(FUEL_TYPES_DATA_FILE)
    isnothing(result) && @warn "Could not construct generator categories"
    result
end

"""
A single `ComponentSelector` representing the static injectors in a [`System`](@extref
PowerSystems.System) grouped by the categories in `generator_mapping.yaml`
"""
const categorized_injectors::ComponentSelector =
    make_selector(values(injector_categories)...)

"""
A single `ComponentSelector` representing the generators in a [`System`](@extref
PowerSystems.System) (no storage or load) grouped by the categories in
`generator_mapping.yaml`
"""
const categorized_generators::Union{ComponentSelector, Nothing} =
    if isnothing(generator_categories)
        nothing
    else
        make_selector(values(generator_categories)...)
    end
end
