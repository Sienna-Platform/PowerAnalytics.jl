"""Return a dict where keys are a tuple of input parameters (fuel, unit_type) and values are
generator types."""
function get_generator_mapping(filename = nothing)
    if isnothing(filename)
        filename = GENERATOR_MAPPING_FILE
    end
    genmap = open(filename) do file
        YAML.load(file)
    end

    mappings = Dict{NamedTuple, String}()
    for (gen_type, vals) in genmap
        (gen_type == "__META") && continue
        for val in vals
            pm = get(val, "primemover", nothing)
            pm = isnothing(pm) ? nothing : uppercase(string(pm))
            ext = get(val, "ext_category", nothing)
            ext = isnothing(ext) ? nothing : uppercase(string(ext))
            gentype = get(val, "gentype", "Any")
            fuel = get(val, "fuel", nothing)
            key = (gentype = gentype, fuel = fuel, primemover = pm, ext = ext)
            if haskey(mappings, key)
                error(
                    "duplicate generator mappings: $gen_type $(key.gentype) $(key.fuel) $(key.primemover) $(key.ext)",
                )
            end
            mappings[key] = gen_type
        end
    end

    return mappings
end

"""Return the generator category for this fuel and unit_type."""
function get_generator_category(
    gentype,
    fuel,
    primemover,
    ext,
    mappings::Dict{NamedTuple, String},
)
    fuel = isnothing(fuel) ? nothing : uppercase(string(fuel))
    primemover = isnothing(primemover) ? nothing : uppercase(string(primemover))
    generator = nothing
    ext = isnothing(ext) ? nothing : uppercase(ext)

    # Try to match the primemover if it's defined. If it's nothing then just match on fuel.
    for t in InteractiveUtils.supertypes(gentype),
        pm in (primemover, nothing),
        f in (fuel, nothing),
        ext in (ext, nothing)

        key = (gentype = string(nameof(t)), fuel = f, primemover = pm, ext = ext)
        if haskey(mappings, key)
            generator = mappings[key]
            break
        end
    end

    if isnothing(generator)
        @error "No mapping defined for generator type=$gentype fuel=$fuel primemover=$primemover ext=$ext"
    end

    return generator
end

"""
Build a dictionary from fuel (or custom) category name to generator `(type, name)`
pairs for `sys`, using `mapping` of `(gentype, fuel, primemover, …)` keys to category
labels.

# Arguments
 - `sys`: [`PowerSystems.System`](@extref) whose generators are categorized
 - `mapping`: map from generator attribute `NamedTuple` to category `String`

# Keyword Arguments
 - `filter_func`: additional component filter (combined with availability)
 - `generator_mapping_file`: used only by the one-argument method that loads mapping from YAML

# Examples

```julia
generators = make_fuel_dictionary(sys)
generators = make_fuel_dictionary(sys, mapping)
```

See also [`categorize_data`](@ref).
"""
function make_fuel_dictionary(
    sys::PSY.System,
    mapping::Dict{NamedTuple, String};
    filter_func = x -> true,
    kwargs...,
)
    filter_func2 = x -> PSY.get_available(x) && filter_func(x)
    gen_categories = Dict{String, Vector{Tuple{String, String}}}()

    for category in unique(values(mapping))
        gen_categories["$category"] = Tuple{String, String}[]
    end

    for gen in PSY.get_components(PSY.Generator, sys)
        if !filter_func2(gen)
            continue
        end

        fuel = hasmethod(PSY.get_fuel, Tuple{typeof(gen)}) ? PSY.get_fuel(gen) : nothing
        pm =
            if hasmethod(PSY.get_prime_mover_type, Tuple{typeof(gen)})
                PSY.get_prime_mover_type(gen)
            else
                nothing
            end
        ext = get(PSY.get_ext(gen), "ext_category", nothing)
        category = something(
            get_generator_category(typeof(gen), fuel, pm, ext, mapping),
            UNMAPPED_GENERATOR_CATEGORY,
        )
        push!(
            get!(gen_categories, "$category", Tuple{String, String}[]),
            (string(nameof(typeof(gen))), PSY.get_name(gen)),
        )
    end

    for battery in PSY.get_components(PSY.Storage, sys)
        if !filter_func2(battery)
            continue
        end

        ext = get(PSY.get_ext(battery), "ext_category", nothing)
        category = something(
            get_generator_category(
                typeof(battery),
                nothing,
                PSY.get_prime_mover_type(battery),
                ext,
                mapping,
            ),
            UNMAPPED_GENERATOR_CATEGORY,
        )
        push!(
            get!(gen_categories, "$category", Tuple{String, String}[]),
            (string(nameof(typeof(battery))), PSY.get_name(battery)),
        )
    end

    for source in PSY.get_components(PSY.Source, sys)
        if !filter_func2(source)
            continue
        end

        ext = get(PSY.get_ext(source), "ext_category", nothing)
        category = something(
            get_generator_category(typeof(source), nothing, nothing, ext, mapping),
            UNMAPPED_GENERATOR_CATEGORY,
        )
        push!(
            get!(gen_categories, "$category", Tuple{String, String}[]),
            (string(nameof(typeof(source))), PSY.get_name(source)),
        )
    end

    filter!(p -> !isempty(p.second), gen_categories)
    return gen_categories
end

"""
Build a fuel-category dictionary for `sys` using the default generator mapping file
(or `generator_mapping_file` from `kwargs`).

See [`make_fuel_dictionary`](@ref) with an explicit `mapping` argument.
"""
function make_fuel_dictionary(sys::PSY.System; kwargs...)
    mapping = get_generator_mapping(get(kwargs, :generator_mapping_file, nothing))
    return make_fuel_dictionary(sys, mapping; kwargs...)
end
