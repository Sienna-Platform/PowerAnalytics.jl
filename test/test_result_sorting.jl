# Parked for the psy6 port. Depends on `run_test_sim`'s `PSI.Simulation` results and
# `PowerSimulations.VariableKey`/`ParameterKey`, which have no psy6 counterpart. Re-home
# against a rebuilt single-`DecisionModel` fixture using IOM's same-named key types.

(results_uc, results_ed) = run_test_sim(TEST_RESULT_DIR, TEST_SIM_NAME)
problem_results = run_test_prob()

@testset "test filter results" begin
    gen = PA.get_generation_data(results_uc; curtailment = false)
    @test keys(gen.data) == Set([
        :ActivePowerVariable__HydroTurbine,
        :ActivePowerOutVariable__EnergyReservoirStorage,
        :ActivePowerTimeSeriesParameter__RenewableNonDispatch,
        :ActivePowerVariable__RenewableDispatch,
        :ActivePowerInVariable__EnergyReservoirStorage,
        :ActivePowerTimeSeriesParameter__HydroDispatch,
        :ActivePowerVariable__ThermalStandard,
    ])
    @test length(gen.time) == 48

    gen = PA.get_generation_data(
        results_uc;
        variable_keys = [
            PowerSimulations.VariableKey{ActivePowerVariable, ThermalStandard}(""),
            PowerSimulations.VariableKey{ActivePowerVariable, RenewableDispatch}(""),
        ],
        parameter_keys = [
            PowerSimulations.ParameterKey{ActivePowerTimeSeriesParameter, RenewableDispatch}(
                "",
            ),
        ],
        initial_time = Dates.DateTime("2020-01-02T02:00:00"),
        len = 3,
    )
    @test length(gen.data) == 3
    @test length(gen.time) == 3

    load = PA.get_load_data(results_ed)
    @test length(load.data) == 1
    @test length(load.time) == 48
    @test !any(Matrix(PA.no_datetime(load.data[:Load])) .< 0.0)

    load = PA.get_load_data(
        results_ed;
        parameter_keys = [
            PowerSimulations.ParameterKey{ActivePowerTimeSeriesParameter, PowerLoad}(""),
        ],
        initial_time = Dates.DateTime("2020-01-02T02:00:00"),
        len = 3,
    )
    @test length(load.data) == 1
    @test length(load.time) == 3
    @test !any(Matrix(PA.no_datetime(load.data[:Load])) .< 0.0)

    srv = PA.get_service_data(results_ed)
    @test length(srv.data) == 0

    srv = PA.get_service_data(results_uc)
    @test length(srv.data) == 1

    srv = PA.get_service_data(
        results_uc;
        variable_keys = [
            PowerSimulations.VariableKey{
                ActivePowerReserveVariable,
                VariableReserve{ReserveUp},
            }(
                "REG1",
            ),
        ],
        initial_time = Dates.DateTime("2020-01-02T02:00:00"),
        len = 5,
    )
    @test length(srv.data) == 1
    @test length(srv.time) == 5

    # TODO: make tests for subsetting data
    sub_gen =
        get_generation_data(results_uc; filter_func = x -> get_name(get_bus(x)) == "bus1")
    @test length(sub_gen.data) == 8
end

@testset "_get_components_axis handles non-contiguous bus numbers" begin
    # Regression: the bus method previously allocated a length-N vector and
    # indexed it by bus number. Bus numbers are arbitrary positive identifiers,
    # so a number greater than the bus count threw BoundsError (and a sparse
    # set left #undef slots -> UndefRefError).
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")
    buses = collect(PSY.get_components(PSY.ACBus, sys))
    PSY.set_number!(buses[1], 9999)  # far larger than length(buses)
    expected = Set(string.(PSY.get_number.(buses)))
    axis = PA._get_components_axis(x -> true, PSY.ACBus, sys)
    @test Set(axis) == expected
    @test length(axis) == length(buses)
    @test "9999" in axis
end

@testset "test curtailment calculations" begin
    curtailment_params = PA._curtailment_parameters(
        PA.get_generation_parameter_keys(results_uc),
        PA.get_generation_variable_keys(results_uc),
    )
    @test length(curtailment_params) == 1

    curtailment_params = PA._curtailment_parameters(
        PA.get_generation_parameter_keys(problem_results),
        PA.get_generation_variable_keys(problem_results),
    )
    @test length(curtailment_params) == 1
end

@testset "test data aggregation" begin
    gen = PA.get_generation_data(results_uc)

    # `make_fuel_dictionary` categorizes generators and storage only. Loads have
    # no fuel and are handled by a separate path (`get_load_data` /
    # `categorize_data`'s load/slack handling), so there is intentionally no
    # "Load" category here (the function iterated `StaticInjection` before the
    # `Generator`/`Storage` refactor; this assertion predates that change).
    # The test system's natural-gas units have the CT prime mover, which maps to
    # NG-CC (the combustion-turbine half of a decomposed combined-cycle plant),
    # so there is no NG-CT category here.
    cat = PA.make_fuel_dictionary(results_uc.system)
    @test keys(cat) ==
          Set(["Coal", "Wind", "Hydropower", "NG-CC", "Storage", "PV"])

    # `categorize_data` splits storage into "Storage In" (charging, -) and
    # "Storage Out" (discharging, +) and surfaces "Curtailment" by default, so
    # the 6 fuel-dictionary categories expand to 8 here.
    fuel = categorize_data(gen.data, cat)
    @test keys(fuel) == Set([
        "Coal", "Wind", "Hydropower", "NG-CC", "PV",
        "Storage In", "Storage Out", "Curtailment",
    ])

    fuel_agg = PA.combine_categories(fuel)
    @test size(fuel_agg) == (48, 8)
end

@testset "Test system data getters" begin
    # We can test get_load_data without running a simulation
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")

    load_data1 = PA.get_load_data(sys; aggregation = ACBus)
    @test length(load_data1.data) == 3
    @test length(load_data1.time) == 24

    load_data2 = PA.get_load_data(sys; aggregation = StaticLoad)
    @test length(load_data2.data) == 3
    @test length(load_data2.time) == 24

    # With System aggregation, everything gets lumped together
    load_data3 = PA.get_load_data(sys; aggregation = System)
    @test length(load_data3.data) == 1
    @test length(load_data3.time) == 24

    # No aggregation specified: default is StaticLoad
    load_data4 = PA.get_load_data(sys)
    @test length(load_data4.data) == 3
    @test length(load_data4.time) == 24

    load_data5 = PA.get_load_data(sys; aggregation = PowerLoad)
    @test length(load_data5.data) == 2
    @test length(load_data5.time) == 24

    load_data6 = PA.get_load_data(sys; aggregation = StandardLoad)
    @test length(load_data6.data) == 1
    @test length(load_data6.time) == 24

    # Test with a system with `DeterministicSingleTimeSeries`
    sys = PSB.build_system(PSB.PSISystems, "5_bus_hydro_uc_sys")
    @test length(PA.get_load_data(sys; aggregation = ACBus).data) == 3
end

@testset "categorize_data surfaces slack variables" begin
    ts = collect(
        Dates.DateTime("2024-01-01T00:00:00"):Dates.Hour(1):Dates.DateTime(
            "2024-01-01T02:00:00",
        ),
    )
    df_up = DataFrames.DataFrame(; DateTime = ts, var = [1.0, 2.0, 3.0])
    df_dn = DataFrames.DataFrame(; DateTime = ts, var = [0.5, 1.5, 2.5])
    data = Dict{Symbol, DataFrames.DataFrame}(
        :SystemBalanceSlackUp__System => df_up,
        :SystemBalanceSlackDown__System => df_dn,
    )

    result = PA.categorize_data(data, Dict())

    @test haskey(result, "Unserved Energy")
    @test haskey(result, "Over Generation")
    @test result["Unserved Energy"] === df_up
    @test result["Over Generation"] === df_dn
end

@testset "categorize_data splits storage into In (-) / Out (+)" begin
    # Regression: split_power_categories handling previously KeyError-ed and the
    # In/Out split never produced any data. Discharging (ActivePowerOutVariable)
    # is generation (+); charging (ActivePowerInVariable) is load (-). The
    # combined "Storage" category must not be emitted; non-split categories
    # (e.g. "NG-CC") are unaffected.
    ts = collect(
        Dates.DateTime("2024-01-01T00:00:00"):Dates.Hour(1):Dates.DateTime(
            "2024-01-01T01:00:00",
        ),
    )
    data = Dict{Symbol, DataFrames.DataFrame}(
        :ActivePowerVariable__ThermalStandard =>
            DataFrames.DataFrame(; DateTime = ts, gen1 = [3.0, 4.0]),
        :ActivePowerOutVariable__EnergyReservoirStorage =>
            DataFrames.DataFrame(; DateTime = ts, batt = [1.0, 2.0]),
        :ActivePowerInVariable__EnergyReservoirStorage =>
            DataFrames.DataFrame(; DateTime = ts, batt = [0.5, 0.0]),
    )
    aggregation = Dict(
        "Storage" => [("EnergyReservoirStorage", "batt")],
        "NG-CC" => [("ThermalStandard", "gen1")],
    )

    result = PA.categorize_data(data, aggregation; curtailment = false, slacks = false)

    @test Set(keys(result)) == Set(["NG-CC", "Storage In", "Storage Out"])
    @test !haskey(result, "Storage")
    @test collect(result["Storage Out"][!, 1]) == [1.0, 2.0]
    @test collect(result["Storage In"][!, 1]) == [-0.5, -0.0]
    @test collect(result["NG-CC"][!, 1]) == [3.0, 4.0]
end

@testset "Test make_fuel_dictionary filter_func applies to relevant component types" begin
    sys = PSB.build_system(PSB.PSITestSystems, "c_sys5_all_components")

    # Add a Storage component
    stor = PSY.EnergyReservoirStorage(nothing)
    PSY.set_bus!(stor, PSY.get_component(PSY.ACBus, sys, "nodeA"))
    PSY.set_available!(stor, true)
    PSY.add_component!(sys, stor)

    # Filter out everything → empty result
    cat_empty = PA.make_fuel_dictionary(sys; filter_func = x -> false)
    @test all(isempty, values(cat_empty))
    # Filter to one component of each type and verify exactly one result each
    # time. `make_fuel_dictionary` only categorizes generators and storage
    # (loads have no fuel and are handled elsewhere), so `StaticLoad` is
    # intentionally not exercised here.
    for T in (PSY.Generator, PSY.Storage)
        target = PSY.get_name(first(PSY.get_components(T, sys)))
        cat_one = PA.make_fuel_dictionary(sys; filter_func = x -> PSY.get_name(x) == target)
        @test sum(length(v) for v in values(cat_one)) == 1
    end
end

@testset "Test natural-gas prime-mover categorization" begin
    mapping = PA.get_generator_mapping()
    # NG-CT is reserved for the gas-turbine prime mover (GT).
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.GT, nothing, mapping,
    ) == "NG-CT"
    # NG-CC catches combined-cycle (CC), the steam side (CA) of decomposed CC
    # plants, and the combustion turbine (CT), which is the CT half of a
    # decomposed combined-cycle plant.
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.CC, nothing, mapping,
    ) == "NG-CC"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.CA, nothing, mapping,
    ) == "NG-CC"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.CT, nothing, mapping,
    ) == "NG-CC"
end

@testset "fuel OTHER falls back to Other for any prime mover (issue #40)" begin
    mapping = PA.get_generator_mapping()
    # Previously only (primemover=OT, fuel=OTHER) mapped to "Other", so a unit
    # with fuel OTHER and any other prime mover errored. The
    # `{gentype: Generator, primemover: null, fuel: OTHER}` fallback catches all.
    for pm in (
        PSY.PrimeMovers.OT,
        PSY.PrimeMovers.GT,
        PSY.PrimeMovers.CT,
        PSY.PrimeMovers.ST,
    )
        @test PA.get_generator_category(
            PSY.ThermalStandard, "OTHER", pm, nothing, mapping,
        ) == "Other"
    end
end

@testset "make_fuel_dictionary does not crash on unmapped generators" begin
    # Every PSY.ThermalFuels value now has a fuel-only fallback, so any
    # fuel-bearing unit is always categorized. A genuinely-unmapped generator is
    # one with no fuel and a prime mover that matches no rule (here a
    # RenewableDispatch coded with the OT prime mover). get_generator_category
    # returns `nothing` for it by design; make_fuel_dictionary must route that
    # into the "Other" catch-all rather than KeyError-ing.
    mapping = PA.get_generator_mapping()
    # The unmatched lookup emits the by-design @error; capture it locally with
    # `@test_logs` so it does not leak into the suite-wide "no Error log events"
    # guard in runtests.jl.
    unmapped_cat =
        @test_logs (:error, r"No mapping defined") match_mode = :any PA.get_generator_category(
            PSY.RenewableDispatch,
            nothing,
            PSY.PrimeMovers.OT,
            nothing,
            mapping,
        )
    @test unmapped_cat === nothing

    sys = PSB.build_system(
        PSB.PSITestSystems,
        "c_sys5_all_components";
        name = "unmapped_gen_sys",
    )
    g = first(PSY.get_components(PSY.RenewableDispatch, sys))
    PSY.set_prime_mover_type!(g, PSY.PrimeMovers.OT)

    # Pre-fix this throws `KeyError: key "nothing"`. The @error data-quality log
    # fires by design; assert it here with `@test_logs` so the intentional error
    # is both verified and captured locally rather than leaking into the
    # suite-wide "no Error log events" guard in runtests.jl.
    cat =
        @test_logs (:error, r"No mapping defined") match_mode = :any PA.make_fuel_dictionary(
            sys,
        )
    @test haskey(cat, "Other")
    @test ("RenewableDispatch", PSY.get_name(g)) in cat["Other"]
end

@testset "fuel-only fallbacks cover the full ThermalFuels enum (CATS regression)" begin
    # Regression for the CATS plotting flood: the 4d45fdc mapping refactor
    # dropped the pre-refactor fuel-only fallbacks, so real systems with units
    # whose prime mover is OT/IC (and gas/waste/coal fuels) errored on every
    # categorization. Every PSY.ThermalFuels value must now resolve via a
    # fuel-only fallback regardless of prime mover.
    mapping = PA.get_generator_mapping()
    for fuel in instances(PSY.ThermalFuels)
        for pm in (PSY.PrimeMovers.OT, PSY.PrimeMovers.IC, PSY.PrimeMovers.ST)
            @test PA.get_generator_category(
                PSY.ThermalStandard, string(fuel), pm, nothing, mapping,
            ) !== nothing
        end
    end

    # The fuels reported by the CATS system land in the expected buckets, and
    # the gas prime-mover specificity (GT/CC/CA/CT) is preserved.
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.OT, nothing, mapping,
    ) == "NG-Steam"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.IC, nothing, mapping,
    ) == "NG-Steam"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "OTHER_GAS", PSY.PrimeMovers.OT, nothing, mapping,
    ) == "NG-Steam"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "MUNICIPAL_WASTE", PSY.PrimeMovers.OT, nothing, mapping,
    ) == "Biopower"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "MUNICIPAL_WASTE", PSY.PrimeMovers.ST, nothing, mapping,
    ) == "Biopower"
    # Prime-mover-specific gas rules still win over the fuel-only fallback.
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.GT, nothing, mapping,
    ) == "NG-CT"
    @test PA.get_generator_category(
        PSY.ThermalStandard, "NATURAL_GAS", PSY.PrimeMovers.CC, nothing, mapping,
    ) == "NG-CC"
end

@testset "Test HydroGen subtypes map to Hydropower" begin
    mapping = PA.get_generator_mapping()
    # HydroPumpTurbine advertises primemover=PS; without the HydroGen rule it
    # would fall through to the generic `{Any, PS, null}` Storage rule.
    @test PA.get_generator_category(
        PSY.HydroPumpTurbine, nothing, PSY.PrimeMovers.PS, nothing, mapping,
    ) == "Hydropower"
    @test PA.get_generator_category(
        PSY.HydroTurbine, nothing, PSY.PrimeMovers.HY, nothing, mapping,
    ) == "Hydropower"
end
