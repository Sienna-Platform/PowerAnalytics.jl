module PowerAnalytics

# EXPORTS
export ComponentSelector, SingularComponentSelector, PluralComponentSelector
export make_selector, get_name, get_subselectors
export Metric, TimedMetric, TimelessMetric, ComponentSelectorTimedMetric,
    ComponentTimedMetric,
    SystemTimedMetric, OutputsTimelessMetric, CustomTimedMetric
export DATETIME_COL, META_COL_KEY, SYSTEM_COL, OUTPUTS_COL, AGG_META_KEY
export is_col_meta, set_col_meta, set_col_meta!, get_time_df, get_time_vec, get_data_cols,
    get_data_df, get_data_vec, get_data_mat, get_description, get_component_agg_fn,
    get_time_agg_fn, with_component_agg_fn, with_time_agg_fn, metric_selector_to_string,
    get_agg_meta, set_agg_meta!, rebuild_metric
export compute, compute_all, hcat_timed_dfs, aggregate_time, compose_metrics
export NoOutputError, read_component_output, read_system_indexed_output
export load_outputs
export realized_timestamps, read_realized_key_wide
export parse_generator_mapping_file, parse_injector_categories, parse_generator_categories
export mean, weighted_mean, unweighted_sum

# IMPORTS
import Base: @kwdef
import Dates
import Dates: DateTime
import TimeSeries
import Statistics
import Statistics: mean
import DataFrames
import DataFrames: DataFrame, metadata, metadata!, colmetadata, colmetadata!
import YAML
import DataStructures: SortedDict
import PowerSystems
import PowerSystems:
    Component,
    ComponentSelector,
    make_selector, get_name,
    get_available,
    COMPONENT_NAME_DELIMITER,
    rebuild_selector

import InfrastructureSystems
# These three resolve against both `System` and `IS.Outputs`; PowerSystems' own versions are
# pure `System`-typed forwarders and would MethodError against outputs.
import InfrastructureSystems: get_groups, get_component, get_components
import InfrastructureOptimizationModels
import InteractiveUtils

# ALIASES
const PSY = PowerSystems
const IS = InfrastructureSystems
const IOM = InfrastructureOptimizationModels

# DOCUMENTATION CONFIG
using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

# INCLUDES
include("load_outputs.jl")
include("input_utils.jl")
include("realized_outputs.jl")
include("output_utils.jl")
include("metrics.jl")
include("builtin_component_selectors.jl")
include("builtin_metrics.jl")

# SUBMODULES
using .Selectors
using .Metrics

end # module PowerAnalytics
