"""
    For a particular transit route start time, return a vector of (station, time) pairs
"""
function start_time(start_time::Float64, time_horizon::Float64, transit_stops_line::DataFrame)
    node_list = TransitNode[]
    line_total_time = sum(transit_stops_line.time_prev_stop)

    if start_time+line_total_time > time_horizon
        return node_list    

    else
        cumul_trip_time = 0
        for row in eachrow(transit_stops_line)
            cumul_trip_time += row.time_prev_stop
            node = TransitNode(row.stop_sequence, cumul_trip_time + start_time)
            push!(node_list, node)
        end
        return node_list
    end 
end

"""
    For a frequency f, return the (station, time) pairs
"""
function frequency_nodes(frequency::Int, time_horizon::Float64, transit_stops_line::DataFrame)
    result = TransitNode[]
    for i in 0:frequency:time_horizon
        node_list_st_i = start_time(i, time_horizon, transit_stops_line)
        append!(result, node_list_st_i)
    end        
    return result
end

"""
    Helper function to return a lat/lon tuple for a transit station
"""
function station_lat_lon(station::Int, transit_stops_line::DataFrame)
    row_index = findfirst(transit_stops_line.stop_sequence .== station)
    station_lon = transit_stops_line[row_index, :stop_lon]
    station_lat = transit_stops_line[row_index, :stop_lat]
    return (station_lat, station_lon)
end

"""
    Calculate the walking time between a passenger location and transit station
"""
function walking_time_station(passenger_location::Tuple{Float64, Float64}, station::Tuple{Float64, Float64}, transit_time_step::Int)
    distance = haversine(passenger_location, station)
    #return round_time_step(((distance/1.3)/60), transit_time_step)
    return (distance/1.3)/60
end

"""
    Compute actual transit travel time between two stations
"""
function station_travel_time(first_station::Int, second_station::Int, transit_stops_line::DataFrame)
    filtered_transit_stops = filter(row -> row[:stop_sequence] > first_station && row[:stop_sequence] <= second_station, transit_stops_line)
    return sum(filtered_transit_stops.time_prev_stop)
end