using PowerSimulations
using PowerSystems
using StorageSystemsSimulations
using HydroPowerSimulations
using Dates
using HiGHS
using Logging
using PowerSystemCaseBuilder
const PSI = PowerSimulations
const PSY = PowerSystems
const SSS = StorageSystemsSimulations
const PSB = PowerSystemCaseBuilder

# HiGHS Open Source Optimizer
function get_optimizer_highs()
    solver = optimizer_with_attributes(
        HiGHS.Optimizer,
        "time_limit" => 1500.0,
        "log_to_console" => true,
        "mip_rel_gap" => 1e-2,
    )
    return solver
end

#####################
##### Simulations ###
#####################
function run_scenario(scenario::String)
    # Load the System
    sys = PSB.build_system(PSISystems, "RTS_GMLC_DA_sys")
    transform_single_time_series!(sys, Hour(48), Hour(24))

    # Storage Device Parameters
    comp_storage = get_component(EnergyReservoirStorage, sys, "313_STORAGE_1")
    set_initial_storage_capacity_level!(comp_storage, 0.0) # intital SOC of storage device equal to 0

    # Scenario Specific Parameters
    if scenario == "Scenario_2"
        set_storage_capacity!(comp_storage, get_storage_capacity(comp_storage) * 10) # increasing the energy capacity of the storage device
        set_input_active_power_limits!(
            comp_storage,
            (
                min = get_input_active_power_limits(comp_storage).min * 10,
                max = get_input_active_power_limits(comp_storage).max * 10,
            ),
        ) # increasing the power capacity of the storage device
        set_output_active_power_limits!(
            comp_storage,
            (
                min = get_output_active_power_limits(comp_storage).min * 10,
                max = get_output_active_power_limits(comp_storage).max * 10,
            ),
        ) # increasing the power capacity of the storage device
    end

    # Problem Template
    template_uc = ProblemTemplate()

    # Branch Formulations
    set_device_model!(template_uc, Line, StaticBranch)
    set_device_model!(template_uc, TapTransformer, StaticBranch)
    # Injection Device Formulations
    set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
    set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
    set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)
    set_device_model!(template_uc, HydroTurbine, HydroDispatchRunOfRiver)
    set_device_model!(
        template_uc,
        DeviceModel(
            EnergyReservoirStorage,
            StorageDispatchWithReserves;
            attributes = Dict{String, Any}(
                "reservation" => false,
                "cycling_limits" => false,
                "energy_target" => false,
                "complete_coverage" => false,
                "regularization" => false,
            ),
        ),
    )
    # Network Formulation
    set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel; use_slacks = false))

    # Optimization Solver
    solver = get_optimizer_highs()

    # Decision Model
    models = SimulationModels(;
        decision_models = [
            DecisionModel(
                template_uc,
                sys;
                name = "UC",
                optimizer = solver,
                initialize_model = false,
                optimizer_solve_log_print = true,
                check_numerical_bounds = false,
                warm_start = true,
                store_variable_names = true,
                calculate_conflict = true,
            ),
        ],
    )

    DA_sequence = SimulationSequence(;
        models = models,
        ini_cond_chronology = InterProblemChronology(),
    )
    output_folder = joinpath(@__DIR__, "_simulation_results_RTS")
    mkpath(output_folder)

    # Build and Run the Simulation
    sim = Simulation(;
        name = scenario,
        steps = 31,
        models = models,
        sequence = DA_sequence,
        initial_time = DateTime("2020-07-01T00:00:00"),
        simulation_folder = output_folder,
    )

    build!(sim; console_level = Logging.Info, file_level = Logging.Debug, serialize = false)
    execute!(sim; enable_progress_bar = true)
end

for scenario in ["Scenario_1", "Scenario_2"]
    @info "Running RTS-GMLC $scenario..."
    run_scenario(scenario)
end
