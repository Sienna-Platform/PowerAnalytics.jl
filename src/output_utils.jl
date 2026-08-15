"""
Column metadata key whose value signifies whether the column is metadata. Metadata columns
are excluded from `get_data_cols` and similar and can be used to represent things like a
time aggregation.
"""
const META_COL_KEY = "meta_col"

"Name of a column that represents whole-of-`Outputs` data. Currently equal to `\"$OUTPUTS_COL\"`."
const OUTPUTS_COL = "Outputs"

"""
Column metadata key whose value, if any, is additional information to be passed to
aggregation functions. Values of `nothing` are equivalent to absence of the entry.
"""
const AGG_META_KEY = "agg_meta"

"Check whether a column is metadata."
is_col_meta(df, colname) = get(colmetadata(df, colname), META_COL_KEY, false)

"Mark a column as metadata."
set_col_meta!(df, colname, val = true) =
    colmetadata!(df, colname, META_COL_KEY, val; style = :note)

"Get the column's aggregation metadata; return `nothing` if there is none."
get_agg_meta(df, colname) = get(colmetadata(df, colname), AGG_META_KEY, nothing)

"Get the single data column's aggregation metadata; error on multiple data columns."
function get_agg_meta(df)
    my_data_cols = get_data_cols(df)
    (length(my_data_cols) == 1) && return get_agg_meta(df, first(my_data_cols))
    throw(
        ArgumentError(
            "DataFrame has $(length(my_data_cols)) columns of data, must specify a column name",
        ),
    )
end

"Set the column's aggregation metadata."
set_agg_meta!(df, colname, val) =
    colmetadata!(df, colname, AGG_META_KEY, val; style = :note)

"Set the single data column's aggregation metadata; error on multiple data columns."
function set_agg_meta!(df, val)
    my_data_cols = get_data_cols(df)
    (length(my_data_cols) == 1) && return set_agg_meta!(df, first(my_data_cols), val)
    throw(
        ArgumentError(
            "DataFrame has $(length(my_data_cols)) columns of data, must specify a column name",
        ),
    )
end

# TODO test that mutating the selection mutates the original
"Select the `$DATETIME_COL` column of the `DataFrame` as a one-column `DataFrame` without copying."
get_time_df(df::DataFrames.AbstractDataFrame) =
    DataFrames.select(df, DATETIME_COL; copycols = false)

"Select the `$DATETIME_COL` column of the `DataFrame` as a `Vector` without copying."
get_time_vec(df::DataFrames.AbstractDataFrame) = df[!, DATETIME_COL]

"""
Select the names of the data columns of the `DataFrame`, i.e., those that are not
`$DATETIME_COL` and not metadata.
"""
get_data_cols(df::DataFrames.AbstractDataFrame) =
    filter(
        (
            colname ->
                (colname != DATETIME_COL) &&
                    !is_col_meta(df, colname)
        ),
        names(df))

"Select the data columns of the `DataFrame` as a `DataFrame` without copying."
get_data_df(df::DataFrames.AbstractDataFrame) =
    DataFrames.select(df, get_data_cols(df); copycols = false)

"Select the data column of the `DataFrame` as a vector without copying, errors if more than one."
function get_data_vec(df::DataFrames.AbstractDataFrame)
    the_data = get_data_df(df)
    (size(the_data, 2) > 1) && throw(
        ArgumentError(
            "DataFrame has $(size(the_data, 2)) columns of data, consider using data_mat",
        ),
    )
    return the_data[!, 1]
end

"Select the data columns of the `DataFrame` as a `Matrix` with copying."
get_data_mat(df::DataFrames.AbstractDataFrame) = Matrix(get_data_df(df))

# TODO test allow_missing behavior
function _extract_common_time(dfs::DataFrames.AbstractDataFrame...;
    allow_missing = true, ex_fn::Function = get_time_vec)
    time_cols = ex_fn.(dfs)
    allow_missing || !any([any(ismissing.(ex_fn(tc))) for tc in time_cols]) ||
        throw(ErrorException("Missing time columns"))
    # Candidate time column is the one with the most non-missing values
    time_col = argmax(x -> count(!ismissing, Array(x)), time_cols)
    # Other time columns must either be the same or [nothing]
    # TODO come up with a more informative error here
    all([
        isequal(sub, time_col) ||
            (all(ismissing.(Array(sub))) && size(sub, 1) == 1) for sub in time_cols
    ]) ||
        throw(ErrorException("Mismatched time columns"))
    return time_col
end

# TODO test
function _broadcast_time(the_data_cols, time_col; allow_unitary = true)
    size(the_data_cols, 1) == size(time_col, 1) && return the_data_cols
    (allow_unitary && size(the_data_cols, 1) == 1) ||
        throw(ErrorException("Individual data column does not match aggregate time column"))
    return repeat(the_data_cols, size(time_col, 1))  # Preserves metadata
end

"""
If the time axes match across all the `DataFrames`, horizontally concatenate them and remove
the duplicate time axes. If not, throw an error.
"""
function hcat_timed_dfs(vals::DataFrame...)  # TODO incorporate allow_missing
    time_col = _extract_common_time(vals...; ex_fn = get_time_df)
    broadcasted_vals = [get_data_df(sub) for sub in _broadcast_time.(vals, Ref(time_col))]
    return hcat(time_col, broadcasted_vals...)
end

# Sometimes, to construct new column names, we need to construct strings that don't appear
# as/in any other column names
function _make_unique_col_name(col_names;
    allow_substring = false, initial_try = "newcol", suffix = "!")
    col_name = initial_try
    while allow_substring ? (col_name in col_names) : any(occursin.(col_name, col_names))
        col_name *= suffix
    end
    return col_name
end

# Fetch the time_agg_fn associated with the particular column's Metric; error if no agg_fn can be determined
function _find_time_agg_fn(df, col_name, default_agg_fn)
    my_agg_fn = default_agg_fn
    col_md = colmetadata(df, col_name)
    haskey(col_md, "metric") && (my_agg_fn = get_time_agg_fn(col_md["metric"]))
    (my_agg_fn === nothing) && throw(
        ArgumentError(
            "No time aggregation function found for $col_name; specify in metric or use agg_fn kwarg $(col_md)",
        ),
    )
    return my_agg_fn
end

# Construct a pipeline that can be passed to DataFrames.combine that represents the aggregation of the given column
function _construct_aggregation(df, agg_meta_colnames, col_name, default_agg_fn)
    agg_fn = _find_time_agg_fn(df, col_name, default_agg_fn)
    if haskey(agg_meta_colnames, col_name)
        return [col_name, agg_meta_colnames[col_name]] => agg_fn => col_name
    end
    return col_name => agg_fn => col_name
end

function _construct_meta_aggregation(df, col_name, meta_colname)
    agg_fn = get_time_meta_agg_fn(colmetadata(df, col_name)["metric"])
    return meta_colname => agg_fn => meta_colname
end

"""
Given a `DataFrame` like that produced by a [`TimedMetric`](@ref) or the timed version of
[`compute_all`](@ref), group by a function of the time axis, apply a reduction, and report
the resulting aggregation indexed by the first timestamp in each group.

# Arguments
 - `df::DataFrames.AbstractDataFrame`: the DataFrame to operate upon
 - `groupby_fn = nothing`: a function that can be passed a `DateTime`; two rows will be in
   the same group if their timestamps produce the same result under `groupby_fn`. Note that
   `groupby_fn = month` puts January 2024 and January 2025 into the same group whereas
   `groupby_fn = (x -> (year(x), month(x)))` does not. Passing `nothing` groups all rows in
   the `DataFrame` together.
 - `groupby_col::Union{Nothing, AbstractString, Symbol} = nothing`: specify a column name to
   report the result of `groupby_fn` in the output DataFrame, or `nothing` to not
 - `agg_fn = nothing`: by default, the aggregation function ([`sum`](@extref
   Base.sum)/[`mean`](@extref Statistics.mean)/etc.) is specified by the [`Metric`](@ref),
   which is read from the metadata of each column. If this metadata isn't found, one can
   specify a default aggregation function like [`sum`](@extref Base.sum) here; if nothing,
   an error will be thrown.

# Examples

```julia
using Dates
using PowerAnalytics.Metrics
# Setup: create a `DataFrame` to work with
my_computations = [
    (calc_active_power, make_selector(ThermalStandard; groupby = :all), "thermal_power"),
    (calc_curtailment, make_selector(RenewableDispatch; groupby = :all), "renewable_curtailment")
]
my_8760 = compute_all(results, my_computations...)
# Now (given a certain simulation setup) `my_8760` is an 8760x3 DataFrame
# with columns `$DATETIME_COL`, `thermal_power`, and `renewable_curtailment`

# Aggregate across the entire time period; result is 1x3:
aggregate_time(my_8760)

# Aggregate all January results together, all February results together, etc.; result is 12x3:
aggregate_time(my_8760; groupby_fn = Dates.month)

# Same as above but create a column 'month_n' with 1 for January, 2 for February, etc.; result is 12x4:
aggregate_time(my_8760; groupby_fn = Dates.month, groupby_col = "month_n")

# Custom `groupby_fn`: put all weekday timestamps together and all weekend timestamps together; result is 2x4:
aggregate_time(my_8760; groupby_fn = x -> (Dates.dayofweek(x) in [6, 7]) ? "weekend" : "weekday", groupby_col = "day_type")
```
"""
function aggregate_time(
    df::DataFrames.AbstractDataFrame;
    groupby_fn = nothing,
    groupby_col::Union{Nothing, AbstractString, Symbol} = nothing,
    agg_fn = nothing,
)
    keep_groupby_col = (groupby_col !== nothing)
    if groupby_fn === nothing && keep_groupby_col
        throw(ArgumentError("Cannot keep the groupby column if not specifying groupby_fn"))
    end

    # Everything goes into the same group by default
    (groupby_fn === nothing) && (groupby_fn = (_ -> 0))

    # Validate or create groupby column name
    if keep_groupby_col
        (groupby_col in names(df)) &&
            throw(ArgumentError("groupby_col cannot be an existing column name of df"))
    else
        groupby_col = _make_unique_col_name(
            names(df);
            allow_substring = true,
            initial_try = "grouped",
        )
    end

    # Find all aggregation metadata
    # TODO should metadata columns be allowed to have aggregation metadata? Probably.
    agg_metas = Dict(varname => get_agg_meta(df, varname) for varname in get_data_cols(df))

    # Create column names for non-nothing aggregation metadata
    existing_cols = vcat(names(df), groupby_col)
    agg_meta_colnames = Dict(
        varname =>
            _make_unique_col_name(existing_cols; initial_try = varname * "_meta")
        for varname in get_data_cols(df) if agg_metas[varname] !== nothing)
    cols_with_agg_meta = collect(keys(agg_meta_colnames))

    # TODO currently we can only handle Vector aggregation metadata (eventually we'll
    # probably need two optional aggregation metadata fields, one for per-column data and
    # one for per-element data)
    @assert all(typeof.([agg_metas[cn] for cn in cols_with_agg_meta]) .<: Vector)
    @assert all(
        length(agg_metas[orig_name]) == length(df[!, orig_name])
        for orig_name in cols_with_agg_meta
    )

    # Add the groupby column and aggregation metadata columns
    transformed = DataFrames.transform(
        df,
        DATETIME_COL => DataFrames.ByRow(groupby_fn) => groupby_col,
    )
    for orig_name in cols_with_agg_meta
        transformed[!, agg_meta_colnames[orig_name]] = agg_metas[orig_name]
    end

    grouped = DataFrames.groupby(transformed, groupby_col)
    # For all data columns and non-special metadata columns, find the agg_fn and handle aggregation metadata
    aggregations = [
        _construct_aggregation(df, agg_meta_colnames, col_name, agg_fn)
        for col_name in names(df) if !(col_name in (groupby_col, DATETIME_COL))
    ]
    meta_aggregations = [
        _construct_meta_aggregation(df, orig_name, agg_meta_colnames[orig_name])
        for orig_name in cols_with_agg_meta
    ]
    # Take the first DateTime in each group, reduce the other columns as specified in aggregations, preserve column names
    # TODO is it okay to always just take the first timestamp, or should there be a
    # reduce_time_fn kwarg to, for instance, allow users to specify that they want the
    # midpoint timestamp?
    combined = DataFrames.combine(grouped,
        DATETIME_COL => first => DATETIME_COL,
        aggregations..., meta_aggregations...)

    # Replace the aggregation metadata
    for orig_name in cols_with_agg_meta
        set_agg_meta!(combined, orig_name, combined[!, agg_meta_colnames[orig_name]])
    end

    # Drop agg_meta columns, reorder the columns for convention
    not_index = DataFrames.Not(groupby_col, DATETIME_COL, values(agg_meta_colnames)...)
    result = DataFrames.select(combined, DATETIME_COL, groupby_col, not_index)

    set_col_meta!(result, DATETIME_COL)
    set_col_meta!(result, groupby_col)
    keep_groupby_col || (result = DataFrames.select(result, DataFrames.Not(groupby_col)))
    return result
end
