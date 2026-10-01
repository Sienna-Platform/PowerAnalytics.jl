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
    isnothing(pm) || (pm = PSY.parse_enum_mapping(PSY.PrimeMovers, pm))

    fc = get(category_spec, "fuel", nothing)
    isnothing(fc) || (fc = PSY.parse_enum_mapping(PSY.ThermalFuels, fc))

    return gen_type, pm, fc
end

# One rule of a `generator_mapping.yaml` category, parsed into the component type, prime
# mover and fuel it matches on (`nothing` meaning "any").
struct FuelCategoryRule
    gen_type::Type
    prime_mover::Union{Nothing, PSY.PrimeMovers}
    fuel::Union{Nothing, PSY.ThermalFuels}
end

function FuelCategoryRule(
    category_spec::Dict;
    root_type::Type{<:Component} = PSY.StaticInjection,
)
    return FuelCategoryRule(parse_fuel_category(category_spec; root_type = root_type)...)
end

function _attribute_matches(getter::Function, expected, comp::Component)
    hasmethod(getter, Tuple{typeof(comp)}) || return false
    return getter(comp) == expected
end
_attribute_matches(::Function, ::Nothing, ::Component) = true

function rule_matches(rule::FuelCategoryRule, comp::Component)
    return typeof(comp) <: rule.gen_type &&
           _attribute_matches(PSY.get_prime_mover_type, rule.prime_mover, comp) &&
           _attribute_matches(PSY.get_fuel, rule.fuel, comp)
end

# Number of `supertype` steps from `t` up to `target`. The mapping's `gentype`s are types
# read from a YAML file at runtime, so the comparison has to be made on type values.
function _type_distance(@nospecialize(t::Type), @nospecialize(target::Type))
    dist = 0
    while t !== target
        # `target` contains `t` without being in its supertype chain (e.g. a `Union`): rank
        # it behind every rule whose type the chain does reach.
        (t === Any) && return typemax(Int)
        t = supertype(t)
        dist += 1
    end
    return dist
end

# Specificity of `rule` for a component it matches, smaller is more specific: the closest
# component supertype first, then a specific prime mover over any prime mover, then a
# specific fuel over any fuel.
function rule_rank(rule::FuelCategoryRule, comp::Component)
    return (
        _type_distance(typeof(comp), rule.gen_type),
        isnothing(rule.prime_mover),
        isnothing(rule.fuel),
    )
end

# Whether `rule` is the most specific of `rules` matching `comp`, so that each component
# belongs to exactly one category even when the fallback rules of several categories match
# it (e.g. a natural gas combined cycle matches both a prime mover rule and a fuel-only
# rule).
function is_best_rule(rule::FuelCategoryRule, rules, comp::Component)
    rule_matches(rule, comp) || return false
    rank = rule_rank(rule, comp)
    for other in rules
        (other !== rule && rule_matches(other, comp) && rule_rank(other, comp) < rank) &&
            return false
    end
    return true
end

function _fuel_rule_selector_name(rule::FuelCategoryRule)
    selector_name = string(nameof(rule.gen_type))
    if !(isnothing(rule.prime_mover) && isnothing(rule.fuel))
        selector_name *=
            COMPONENT_NAME_DELIMITER *
            join(
                (isnothing(x) ? "Any" : string(x) for x in (rule.prime_mover, rule.fuel)),
                COMPONENT_NAME_DELIMITER,
            )
    end
    return selector_name
end

# `competing_rules` are all the rules of the mapping file; a component is only selected by
# the most specific rule that matches it.
function _make_fuel_rule_selector(rule::FuelCategoryRule, competing_rules)
    filter_closure(comp::Component) = is_best_rule(rule, competing_rules, comp)
    # The name is guaranteed to never collide with fully-qualified component names
    return make_selector(filter_closure, rule.gen_type;
        name = _fuel_rule_selector_name(rule))
end

# A repeated rule, in the same or another category, would select its components twice.
function _check_no_shared_rules(rules::AbstractDict)
    owner = Dict{Tuple{Type, Any, Any}, String}()
    for category in sort!(collect(keys(rules)))
        for rule in rules[category]
            key = (rule.gen_type, rule.prime_mover, rule.fuel)
            haskey(owner, key) && throw(
                ArgumentError(
                    "the rule gentype = $(rule.gen_type), primemover = " *
                    "$(rule.prime_mover), fuel = $(rule.fuel) appears more than once " *
                    "(categories \"$(owner[key])\" and \"$category\"); each rule may " *
                    "appear only once in a generator mapping file",
                ),
            )
            owner[key] = category
        end
    end
    return nothing
end

# Based on old PowerAnalytics' get_generator_mapping
"""
Parse a `generator_mapping.yaml` file into a dictionary of `ComponentSelector`s and a
dictionary of metadata if present.

Each category has one subselector per rule in the file. A component is selected only by
the most specific rule that matches it across the whole file, so each component belongs to
at most one category. Specificity follows the closest component supertype first, then a
rule naming a prime mover over one that does not, then a rule naming a fuel over one that
does not: for example, with the default mapping a natural gas combined cycle unit is in
`NG-CC` only, not also in the fuel-only `NG-Steam` fallback.

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
    categories = filter(!=(FUEL_TYPES_META_KEY), collect(keys(in_data)))
    rules = Dict(
        category => [
            FuelCategoryRule(spec; root_type = root_type) for spec in in_data[category]
        ] for category in categories
    )
    # A rule whose gentype does not fit under root_type is dropped
    for category_rules in values(rules)
        filter!(rule -> !(rule.gen_type <: Union{}), category_rules)
    end
    _check_no_shared_rules(rules)
    all_rules = reduce(vcat, values(rules); init = FuelCategoryRule[])
    mappings = Dict{String, ComponentSelector}()
    for category in categories
        # Omit the category entirely if root_type causes elimination of all subselectors
        (length(in_data[category]) > 0 && isempty(rules[category])) && continue
        subselectors = [_make_fuel_rule_selector(r, all_rules) for r in rules[category]]
        mappings[category] = make_selector(subselectors...; name = category)
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
