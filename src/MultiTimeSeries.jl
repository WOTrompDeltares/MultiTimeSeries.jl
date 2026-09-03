module MultiTimeSeries

# ── dependencies ──────────────────────────────────────────────────────────────
using Dates
using Printf
using JLD2
using Rasters, ZarrDatasets, NCDatasets
using Minio, AWS
using URIs
using Statistics
using DataFrames
import Plots

# ── abstract types (must precede includes) ────────────────────────────────────
abstract type AbstractTimeSeries end

# ── source files ──────────────────────────────────────────────────────────────
include("series.jl")
include("series_noos.jl")
include("series_donar.jl")
include("series_netcdf.jl")
include("series_zarr.jl")
include("series_jld2.jl")
include("statistics.jl")
include("plotting.jl")

# ── exports ───────────────────────────────────────────────────────────────────

# types
export AbstractTimeSeries
export TimeSeries
export NoosTimeSeriesCollection

# location helpers
export find_location_index

# getters
export get_values, get_times, get_names, get_longitudes, get_latitudes
export get_quantity, get_source

# selection
export select_location_by_id, select_locations_by_ids
export select_location_by_name, select_locations_by_names
export select_timespan, select_timerange_with_fill, select_times_by_ids

# merging
export merge_by_times, merge_by_locations

# NOOS I/O
export read_single_noos_file, read_muliple_noos_files, write_single_noos_file
export get_source_quantity_keys, get_sources, get_quantities, get_series_from_collection

# DONAR I/O
export read_donar_timeseries

# NetCDF I/O
export NetCDFTimeSeries, write_to_netcdf

# Zarr I/O
export ZarrTimeSeries, has_aws_credentials

# JLD2 I/O
export JLD2TimeSeries, write_to_jld2

# statistics
export compute_statistics

# plotting overlays (scatter/plot extend Plots and are used as Plots.scatter/plot)
export linear_fit!, qq!

end # module MultiTimeSeries
