# series_netcdf.jl

using Dates
using NCDatasets
const NAME_LEN_MAX = 256

# Define values structure for NetCDF time series
# use lazy loading for the values
struct NetCDFTimeSeries <: AbstractTimeSeries
    nc::NCDataset
    filename::String
    quantity::String
    source::String
end

# constructor for NetCDFTimeSeries from filename and quantity
"""
function NetCDFTimeSeries(filename::String, quantity::String, source::String="")
Creates a NetCDFTimeSeries object from a NetCDF file and a specified quantity.
use: ts = NetCDFTimeSeries("path/to/file.nc", "waterlevel")
where filename is the path to the NetCDF file and quantity is the variable name in the file.
Returns a NetCDFTimeSeries object that can be used with the series_ml interface.
The default source is "NetCDF file: <filename>".
"""
function NetCDFTimeSeries(filename::String, quantity::String, source::String="")
    if !isfile(filename)
        error("File $(filename) does not exist.")
    end
    nc = nothing
    try
        nc = NCDataset(filename)
    catch e
        error("Failed to open NetCDF file $(filename): $(e)")
    end
    if length(source)==0
        source = "NetCDF file: $(filename)" 
    end
    return NetCDFTimeSeries(nc, filename, quantity, source)
end

#
# getters for the fields
#

function get_values(ts::NetCDFTimeSeries)
    # Throws an error if any missing values
    return NCDatasets.nomissing(ts.nc[ts.quantity][:,:]) # Read the values now for all stations and times
end
    
function get_times(ts::NetCDFTimeSeries)
    return ts.nc["time"][:]
end

function get_names(ts::NetCDFTimeSeries)
    possible_names = ["station_id", "station_name"]
    for name in possible_names
        if name in keys(ts.nc)
            if ndims(ts.nc[name]) == 2
                # This implicitly loads data
                return replace.(String.(eachcol(ts.nc[name])), "\0"=>"") # Convert to array of strings
            else
                # need to explicitly load data here
                return ts.nc[name][:] # Convert to array of strings
            end
        end
    end
    error("No station name variable found in the NetCDF file. Expected one of: $(possible_names)")
end

function get_longitudes(ts::NetCDFTimeSeries)
    return ts.nc["station_x_coordinate"][:,1] # Test file has time-dependent longitudes
end

function get_latitudes(ts::NetCDFTimeSeries)
    return ts.nc["station_y_coordinate"][:,1] # Test file has time-dependent latitudes
end

function get_quantity(ts::NetCDFTimeSeries)
    return ts.quantity
end

function get_source(ts::NetCDFTimeSeries)
    return ts.source
end

#
# Selection methods
# These are the implemtentations for the NetCDFTimeSeries, that override the default implementations in series.jl.
# In this implementation, we read the values only for the selected locations and times, and store the result in memory.
#
function select_locations_by_ids(ts::NetCDFTimeSeries, location_indices::Vector{T} where T<:Integer)
    selected_names = get_names(ts)[location_indices]
    selected_longitudes = get_longitudes(ts)[location_indices]
    selected_latitudes = get_latitudes(ts)[location_indices]
    selected_times = get_times(ts)
    selected_quantity = get_quantity(ts)
    selected_source = get_source(ts)
    #selected_values = get_values(ts)[location_indices, :] # This would read all values before selection
    nc_values = ts.nc[ts.quantity]
    n_stations,n_times = size(nc_values)
    selected_values = zeros(Float32, length(location_indices), n_times) # Preallocate for selected values
    # copy station by station
    for (i, loc) in enumerate(location_indices)
        selected_values[i, :] .= nc_values[loc, :]
    end
    # Create a new TimeSeries object with the selected values
    return TimeSeries(selected_values, selected_times, selected_names, selected_longitudes, selected_latitudes,
                      selected_quantity, selected_source)
end

function select_timespan(ts::NetCDFTimeSeries, start_time::DateTime, end_time::DateTime)
    times = get_times(ts)
    time_indices = findall(t -> t >= start_time && t <= end_time, times)
    i_first = findfirst(t -> t>= start_time, times)
    i_last = findlast(t -> t<= end_time, times)
    if i_first>i_last
        error("Invalid timespan for selection: $(start_time) to $(end_time).")
    end
    # Copy values
    nc_values = ts.nc[ts.quantity][:, i_first:i_last] # Read only the values for the selected times
    n_stations,n_times = size(nc_values)
    selected_values = zeros(Float32, n_stations, n_times) # Preallocate for selected values
    @. selected_values = nc_values
    return TimeSeries(selected_values, times[i_first:i_last], get_names(ts), get_longitudes(ts), get_latitudes(ts),
                      get_quantity(ts), get_source(ts))
end

#
# Show function for NetCDFTimeSeries
#
function Base.show(io::IO, series::NetCDFTimeSeries)
    println(io, "NetCDFTimeSeries:")
    println(io, "   Filename: ", series.filename)
    println(io, "   Quantity: ", get_quantity(series))
    println(io, "   Source: ", get_source(series))
    println(io, "   Number of locations: ", length(get_names(series)))
    println(io, "   Number of time points: ", length(get_times(series)))
    println(io, "   Data shape: ", size(get_values(series)))
    println(io, "   Times: ", get_times(series)[1], " to ", get_times(series)[end])
    println(io, "   Locations: ", join(get_names(series), ", "))
    return nothing
end

function Base.show(io::IO, ::MIME"text/plain", series::NetCDFTimeSeries)
    println(io, "NetCDFTimeSeries: $(get_quantity(series)) from $(get_source(series)), with $(length(get_names(series))) locations, from $(get_times(series)[1]) until $(get_times(series)[end]).")
    #show(io, series)
    return nothing
end

#
# test_netcdf_writer
#
standard_names=Dict(
    "time" => "time",
    "station_x_coordinate" => "longitude",
    "station_y_coordinate" => "latitude",
    "waterlevel" => "sea_surface_height"
)
long_names=Dict(
    "time" => "Time",
    "station_x_coordinate" => "Station X Coordinate",
    "station_y_coordinate" => "Station Y Coordinate",
    "waterlevel" => "Sea level above geoid or Sea level above mean-sea-level"
)
units_dict=Dict(
    "time" => "seconds since 2000-01-01 00:00:00",
    "station_x_coordinate" => "degrees_east",
    "station_y_coordinate" => "degrees_north",
    "waterlevel"=>"m"
)

function write_to_netcdf(
    series::AbstractTimeSeries,
    output_filename::String,
)
    if isfile(output_filename)
        error("File $(output_filename) already exists. Please choose a different filename.")
    end

    times = get_times(series)
    times_sec_since = [t.value for t in times.-DateTime(2000,1,1,0,0,0) ]/1000.0 #robust_timedelta_sec(times,DateTime(2000,1,1))

    quantity = get_quantity(series)

    ds = NCDataset(output_filename, "c",
        attrib=Dict(
            "title"=>"Time series of $(quantity)",
            "institution"=>"Deltares",
            "source"=>"$(get_source(series))",
            "history"=>"Created by Julia : NetCDFTimeSeries.jl",
            "date_created"=>"$(Dates.now())",
            "conventions"=>"CF-1.5"
        )
    )


    defDim(ds, "time", length(times))
    defDim(ds, "station", length(get_names(series)))

    defVar(ds, "time", times_sec_since, ("time",), 
        attrib=Dict(
            "standard_name"=>standard_names["time"],
            "long_name"=>long_names["time"],
            "units"=>units_dict["time"]
        )
    )
    defVar(ds, "station_name", get_names(series), ("station",),
        attrib=Dict(
            "long_name"=>"Station Name",
            "cf_role"=>"timeseries_id"
        )
    )
    defVar(ds, "station_x_coordinate", get_longitudes(series), ("station",),
        attrib=Dict(
            "standard_name"=>standard_names["station_x_coordinate"],
            "long_name"=>long_names["station_x_coordinate"],
            "units"=>units_dict["station_x_coordinate"]
        )
    )
    defVar(ds, "station_y_coordinate", get_latitudes(series), ("station",),
        attrib=Dict(
            "standard_name"=>standard_names["station_y_coordinate"],
            "long_name"=>long_names["station_y_coordinate"],
            "units"=>units_dict["station_y_coordinate"]
        )
    )
    defVar(ds, quantity, Float32.(get_values(series)), ("station", "time"),
        attrib=Dict(
            "standard_name"=>standard_names[quantity],
            "long_name"=>long_names[quantity],
            "units"=>units_dict[quantity],
            "coordinates"=>"station_x_coordinate station_y_coordinate station_name",
            "_FillValue"=>-999.0f0,
            "missing_value"=>NaN
        )
    )

    close(ds)
end
