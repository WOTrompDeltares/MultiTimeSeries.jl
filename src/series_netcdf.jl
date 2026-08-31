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
                return replace.(String.(eachcol(ts.nc[name])), "\0"=>"") # Convert to array of strings
            else
                return ts.nc[name] # Convert to array of strings
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
standard_names=Dict("waterlevel" => "sea_surface_height")
long_names=Dict("waterlevel" => "Sea level above geoid or Sea level above mean-sea-level")
units_dict=Dict("waterlevel"=>"m")


function write_to_netcdf(series, output_filename, standard_name="", long_name="")
    # check if the file already exists
    if isfile(output_filename)
        error("File $(output_filename) already exists. Please choose a different filename.")
    end
    # global attributes
    quantity=get_quantity(series)
    source=get_source(series)
    gatts = Dict("title"=>"Time series of $(quantity)",
                 "institution"=>"Deltares",
                 "source"=>"$(source)",
                 "history"=>"Created by Julia : NetCDFTimeSeries.jl",
                 "date_created"=>"$(Dates.now())",
                 "conventions"=>"CF-1.5")
    # create time dimension
    times=get_times(series)
    times_secs_since = [t.value for t in times.-DateTime(2000,1,1,0,0,0) ]/1000.0#robust_timedelta_sec(times,DateTime(2000,1,1))
    time_atts = Dict("standard_name"=>"time","long_name"=>"time","units"=>"seconds since 2000-01-01 00:00:00")
    time_dim = NcDim("time",times_secs_since,time_atts)
    # create station dimension
    station_names=get_names(series)
    station_dim = NcDim("stations",length(station_names))
    # create name_len dimension
    name_len_dim = NcDim("name_len",NAME_LEN_MAX)
    # create longitude variable
    station_x_atts = Dict("units"=>"degrees_east","long_name"=>"station x coordinate","standard_name"=>"longitude")
    station_x_var = NcVar("station_x_coordinate",[station_dim],atts=station_x_atts,t=Float64)
    # create latitude variable
    station_y_atts = Dict("units"=>"degrees_north","long_name"=>"station y coordinate","standard_name"=>"latitude")
    station_y_var = NcVar("station_y_coordinate",[station_dim],atts=station_y_atts,t=Float64)
    # create station name variable
    name_atts = Dict("long_name"=>"station name","cf_role"=>"timeseries_id")
    name_var = NcVar("station_name",[name_len_dim,station_dim],atts=name_atts,t=NC_CHAR)
    # create "quantity" variable
    standard_name=get(standard_names,quantity,"no_stdname_for_$(quantity)")
    if ~haskey(standard_names,quantity)
        println("Available long_names for: $(keys(standard_names))")
    end
    long_name=get(long_names,quantity,"No long_name for $(keys(standard_names))")
    if ~haskey(long_names,quantity)
        println("Available long_names for: $(keys(long_names))")
    end
    units=get(units_dict,quantity,"No units for $(quantity)")
    if ~haskey(units_dict,quantity)
        println("Available units for: $(keys(units_dict))")
    end
    variable_atts = Dict("standard_name"=>standard_name,
                           "long_name"=>long_name,
                           "units"=>"m",
                           "coordinates"=>"station_x_coordinate station_y_coordinate station_name",
                           "_FillValue"=>-999.0f0,
                           "missing_value"=>NaN)
    variable_var= NcVar(quantity,[station_dim,time_dim],atts=variable_atts, t=Float32) #t=Float32

    # create netcdf file and write variables
    NetCDF.create(output_filename, NcVar[variable_var,station_x_var,station_y_var,name_var],gatts=gatts,mode=NC_NETCDF4) do nc
        variable_data = get_values(series)
        NetCDF.putvar(nc, quantity, variable_data)
        station_x = get_longitudes(series)
        NetCDF.putvar(nc, "station_x_coordinate", station_x)
        station_y = get_latitudes(series)
        NetCDF.putvar(nc, "station_y_coordinate", station_y)
        NetCDF.putvar(nc, "station_name", nc_string2char(station_names))
    end
end