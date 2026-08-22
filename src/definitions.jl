
const NEGATIVE_PARAMETERS = [PSY.StaticLoad]
const SUPPORTED_CURTAILMENT_PARAMETERS = [PSI.ActivePowerTimeSeriesParameter]

const SUPPORTED_CURTAILMENT_VARIABLES = [PSI.ActivePowerVariable]
const SUPPORTED_LOAD_VARIABLES = [PSI.ActivePowerVariable]
const SUPPORTED_STORAGE_VARIABLES = [PSI.ActivePowerInVariable, PSI.ActivePowerOutVariable]
const SUPPORTED_SOURCE_VARIABLES = [PSI.ActivePowerInVariable, PSI.ActivePowerOutVariable]
const SUPPORTED_SOURCE_PARAMETERS =
    [PSI.ActivePowerInTimeSeriesParameter, PSI.ActivePowerOutTimeSeriesParameter]
const SUPPORTED_SERVICE_VARIABLES = [PSI.ActivePowerReserveVariable]

const SUPPORTED_BRANCH_VARIABLES = [
    PSI.FlowActivePowerVariable,
    PSI.FlowActivePowerFromToVariable,
    PSI.FlowActivePowerToFromVariable,
]
const SUPPORTED_BRANCH_AUX_VARIABLES = [
    PSI.PowerFlowBranchActivePowerFromTo,
    PSI.PowerFlowBranchActivePowerToFrom,
]

const SUPPORTED_OVERGENERATION_VARIABLE = PSI.SystemBalanceSlackDown
const SUPPORTED_UNSERVEDENERGY_VARIABLES = PSI.SystemBalanceSlackUp
const BALANCE_SLACKVARS = Dict(
    SUPPORTED_OVERGENERATION_VARIABLE => "Over Generation",
    SUPPORTED_UNSERVEDENERGY_VARIABLES => "Unserved Energy",
)

const LOAD_RENAMING = Dict(
    :ActivePowerTimeSeriesParameter__StandardLoad => :Load,
    :ActivePowerTimeSeriesParameter__PowerLoad => :Load,
    :ActivePowerTimeSeriesParameter__ExponentialLoad => :Load,
    :ActivePowerVariable__StandardLoad => :Dispatchable_Load,
    :ActivePowerVariable__PowerLoad => :Dispatchable_Load,
    :ActivePowerVariable__ExponentialLoad => :Dispatchable_Load,
)

const GENERATOR_MAPPING_FILE =
    joinpath(dirname(dirname(pathof(PowerAnalytics))), "deps", "generator_mapping.yaml")

"""Catch-all category for generators whose (gentype, fuel, primemover, ext) combination
has no entry in the generator mapping. `get_generator_category` logs an `@error` and
returns `nothing` for such units; `make_fuel_dictionary` routes them here so the
unit's energy still appears in fuel plots instead of crashing or being dropped. Matches
the `Other` key in the default mapping and PowerGraphics' color palette."""
const UNMAPPED_GENERATOR_CATEGORY = "Other"
