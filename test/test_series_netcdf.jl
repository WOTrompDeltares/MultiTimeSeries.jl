# test_series_netcdf.jl

using Dates

function test_netcdf_timeseries()
    filename = joinpath(@__DIR__, "..", "test_data", "estuary_his.nc")
    series = NetCDFTimeSeries(filename,"waterlevel")
    
    @test typeof(series) == NetCDFTimeSeries

    # test getters
    values = get_values(series)
    @test size(values) == (3, 34561) # 3 locations, 34561 time steps
    @test typeof(values) == Array{Float64, 2}
    times = get_times(series)
    @test length(times) == 34561 # 10 time steps
    @test times[1] == DateTime(1991, 1, 1) # check first time step
    @test times[end] == DateTime(1991, 8, 29)
    names = get_names(series)
    @test length(names) == 3 # 3 locations
    @test names == ["station01", "station02", "station03"]
    longitudes = get_longitudes(series)
    @test length(longitudes) == 3 # 3 locations
    latitudes = get_latitudes(series)
    quantity = get_quantity(series)
    source = get_source(series)
    @test source=="NetCDF file: $(filename)"

    # test selection by location index
    selected_series = select_location_by_id(series, 1)
    @test get_names(selected_series) == ["station01"]
    @test size(get_values(selected_series)) == (1, 34561) # 1 location, 34561 time steps
    @test get_times(selected_series) == times
    @test get_longitudes(selected_series) == [longitudes[1]]
    @test get_latitudes(selected_series) == [latitudes[1]]
    @test get_quantity(selected_series) == quantity
    @test get_source(selected_series) == source
    # test selection by multiple location indices
    selected_series_multi = select_locations_by_ids(series, [1, 2])
    @test get_names(selected_series_multi) == ["station01", "station02"]
    @test size(get_values(selected_series_multi)) == (2, 34561) # 2 locations, 34561 time steps
    @test get_times(selected_series_multi) == times
    @test get_longitudes(selected_series_multi) == longitudes[1:2]
    @test get_latitudes(selected_series_multi) == latitudes[1:2]

    # test selection by names
    selected_series_names = select_locations_by_names(series, ["station01", "station03"])
    @test get_names(selected_series_names) == ["station01", "station03"]
    @test size(get_values(selected_series_names)) == (2, 34561) # 2 locations, 34561 time steps
    @test get_times(selected_series_names) == times
    @test get_longitudes(selected_series_names) == longitudes[[1,3]]
    @test get_latitudes(selected_series_names) == latitudes[[1,3]]
    @test get_quantity(selected_series_names) == quantity
    @test get_source(selected_series_names) == source
    # test select single location by name
    selected_single = select_location_by_name(series, "station02")
    @test get_names(selected_single) == ["station02"]
    @test size(get_values(selected_single)) == (1, 34561) # 1 location, 34561 time steps
    @test get_times(selected_single) == times
    @test get_longitudes(selected_single) == [longitudes[2]]
    @test get_latitudes(selected_single) == [latitudes[2]]

    # test selection by timespan
    start_date = DateTime(1991, 1, 1, 12, 0, 0)
    end_date = DateTime(1991, 1, 2, 12, 0, 0)
    series_timespan = select_timespan(series, start_date, end_date)
    @test length(get_times(series_timespan)) == 145 # 145 hours in the range
    selected_times = get_times(series_timespan)
    @test selected_times[1] == DateTime(1991, 1, 1, 12, 0, 0) # check first time step in timespan
    @test selected_times[end] == DateTime(1991, 1, 2, 12, 0, 0) # check last time step in timespan
    @test size(get_values(series_timespan)) == (3, 145) # 3 locations, 145 time steps
    @test get_names(series_timespan) == names
    @test get_longitudes(series_timespan) == longitudes
    @test get_latitudes(series_timespan) == latitudes
    @test get_quantity(series_timespan) == quantity
    @test get_source(series_timespan) == source

    # Test showing the series
    io = IOBuffer()
    show(io, series)
    output_str = String(take!(io))
    @test occursin("station01", output_str)
    @test occursin("Number of locations: 3", output_str)
    @test occursin("NetCDFTimeSeries", output_str)
end

function test_netcdf_writer()
    # create a TimeSeries object
    times = collect(DateTime(2020, 1, 1):Minute(60):DateTime(2020, 1, 3))
    longitudes = [4.0, 5.0, 6.0]
    latitudes = [52.0, 53.0, 54.0]
    names = ["Station A", "Station B", "Station C"]
    values = randn(length(longitudes), length(times)) # random values for testing
    quantity = "waterlevel"
    source = "Test Source"
    series = TimeSeries(values, times, names, longitudes, latitudes, quantity, source)

    # write to NetCDF file
    output_filename = joinpath(temp_dir, "test_output.nc")
    write_to_netcdf(series, output_filename)

    # read back the NetCDF file
    read_series = NetCDFTimeSeries(output_filename, "waterlevel")
    @test typeof(read_series) == NetCDFTimeSeries
    read_stations = get_names(read_series)
    @test read_stations == names
    read_longitudes = get_longitudes(read_series)
    @test read_longitudes == longitudes
    read_latitudes = get_latitudes(read_series)
    @test read_latitudes == latitudes
    read_source = get_source(read_series)
    @test read_source == "NetCDF file: $(output_filename)"
    read_quantity = get_quantity(read_series)
    @test read_quantity == quantity
    read_values = get_values(read_series)
    @test size(read_values) == (length(read_stations), length(times)) # 3 locations,
end

# run the test
test_netcdf_timeseries()
test_netcdf_writer()
