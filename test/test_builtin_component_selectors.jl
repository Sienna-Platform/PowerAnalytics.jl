test_sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")
test_sys2 = PSB.build_system(PSB.PSITestSystems, "c_sys5_bat")
name_and_type = component -> (typeof(component), get_name(component))

@testset "Test helper functions" begin
    @test PA.lookup_gentype("Component") === PSY.Component
    @test PA.lookup_gentype("PowerSystems.Component") === PSY.Component
    @test PA.lookup_gentype("InfrastructureSystems.InfrastructureSystemsComponent") ===
          IS.InfrastructureSystemsComponent
end
@testset "Test `all_loads` and `all_storage`" begin
    @test Set(name_and_type.(get_components(all_loads, test_sys))) ==
          Set([(PowerLoad, "Bus2"), (PowerLoad, "Bus4"), (StandardLoad, "Bus3")])
    @test Set(name_and_type.(get_components(all_storage, test_sys2))) ==
          Set([(EnergyReservoirStorage, "Bat")])
end

@testset "Test `generator_mapping.yaml`-based functionality" begin
    @test isfile(PA.FUEL_TYPES_DATA_FILE)
    @test Set(keys(injector_categories)) ==
          Set(["Biopower", "CSP", "Coal", "Geothermal", "Hydropower", "NG-CC", "NG-CT",
        "NG-Steam", "Nuclear", "Other", "PV", "Petroleum", "Wind",
        "Storage", "Source", "Load"])
    @test Set(keys(generator_categories)) ==
          Set(["Biopower", "CSP", "Coal", "Geothermal", "Hydropower", "NG-CC", "NG-CT",
        "NG-Steam", "Nuclear", "Other", "PV", "Petroleum", "Wind"])
    @test Set(
        name_and_type.(get_components(injector_categories["Wind"], test_sys)),
    ) == Set([(RenewableDispatch, "WindBusB"), (RenewableDispatch, "WindBusC"),
        (RenewableDispatch, "WindBusA")])
    @test Set(
        name_and_type.(get_components(generator_categories["Coal"], test_sys)),
    ) == Set([(ThermalStandard, "Park City"), (ThermalStandard, "Sundance"),
        (ThermalStandard, "Alta"), (ThermalStandard, "Solitude"),
        (ThermalStandard, "Brighton")])
    @test Set(get_groups(categorized_injectors, test_sys)) ==
          Set(values(injector_categories))
    @test Set(get_groups(categorized_generators, test_sys)) ==
          Set(values(generator_categories))
    @test Set(keys(first(parse_generator_mapping_file(PA.FUEL_TYPES_DATA_FILE)))) ==
          Set(keys(injector_categories))
end

@testset "Each component is in at most one generator-mapping category" begin
    sys = deepcopy(test_sys)
    thermals = collect(get_components(ThermalStandard, sys))
    # A natural gas unit with a specific prime mover matches both its prime mover rule and
    # the fuel-only fallback rule; only the more specific one may select it
    set_fuel!(thermals[1], ThermalFuels.NATURAL_GAS)
    set_prime_mover_type!(thermals[1], PrimeMovers.CC)
    # A natural gas unit with an unlisted prime mover falls back to the fuel-only rule
    set_fuel!(thermals[2], ThermalFuels.NATURAL_GAS)
    set_prime_mover_type!(thermals[2], PrimeMovers.IC)

    in_category(name, comp) =
        comp in collect(get_components(injector_categories[name], sys))
    @test in_category("NG-CC", thermals[1])
    @test !in_category("NG-Steam", thermals[1])
    @test in_category("NG-Steam", thermals[2])
    @test !in_category("NG-CC", thermals[2])

    memberships = Dict{Component, Vector{String}}()
    for (name, selector) in injector_categories, comp in get_components(selector, sys)
        push!(get!(memberships, comp) do
                String[]
            end, name)
    end
    @test !isempty(memberships)
    @test all(length(v) == 1 for v in values(memberships))
end

@testset "A repeated generator-mapping rule is rejected" begin
    dir = mktempdir()
    rule = "  - {gentype: ThermalStandard, fuel: COAL}\n"
    across = joinpath(dir, "across.yaml")
    write(across, "CoalA:\n" * rule * "CoalB:\n" * rule)
    @test_throws ArgumentError parse_generator_mapping_file(across)
    within = joinpath(dir, "within.yaml")
    write(within, "Coal:\n" * rule * rule)
    @test_throws ArgumentError parse_generator_mapping_file(within)
end
