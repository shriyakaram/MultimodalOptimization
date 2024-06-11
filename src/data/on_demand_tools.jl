"""
    Round numbers according to the time step
"""
function round_time_step(number::Float64, time_step::Int)
    rounded_value = ceil(number / time_step) * time_step
    return rounded_value
end

"""
    Calculate the driving time between an origin and destination 
"""
function driving_time(origin::Tuple{Float64, Float64}, destination::Tuple{Float64, Float64}, on_demand_time_step::Int)
    distance = haversine(origin, destination)
    return round_time_step((((distance*0.000621371)/40)*60), on_demand_time_step)
    #return ((distance*0.000621371)/40)*60
end

"""
    For a passenger type ID, access the origin and destination lon/lat
"""
function extract_passenger_data(passenger_id::Int, ond_locations_data::DataFrame)
    row = ond_locations_data[passenger_id, :]
    origin_lon = row.origin_lon
    origin_lat = row.origin_lat
    dest_lon = row.dest_lon
    dest_lat = row.dest_lat
    departure_time = row.departure_time
    return (origin_lat, origin_lon), (dest_lat, dest_lon), departure_time 
end

"""
    For a passenger ID, access the origin zone
"""
function extract_origin_zone(passenger_id::Int, ond_locations_data::DataFrame)
    row = ond_locations_data[passenger_id, :]
    return row.origin_zone
end

"""
    For a passenger type ID, access the destination zone
"""
function extract_destination_zone(passenger_id::Int, ond_locations_data::DataFrame)
    row = ond_locations_data[passenger_id, :]
    return row.dest_zone
end

"""
    Helper function to convert num_passenger_dict to vectors for origin and destinations
"""
function convert_num_dict_list(num_passenger_dict::Dict{Int, Int}, origin_order::Vector{Int}, destination_order::Vector{Int})
    origin_num_passenger_order = Int[]
    destination_num_passenger_order = Int[]
    for p in origin_order
        push!(origin_num_passenger_order, num_passenger_dict[p])
    end

    for p in destination_order
        push!(destination_num_passenger_order, num_passenger_dict[p])
    end

    return origin_num_passenger_order, destination_num_passenger_order
end

"""
    Return possible start times for a route beginning with passenger p
"""
function calc_route_start_times(max_first_waiting_time::Float64, passenger_id::Int, ond_locations_data::DataFrame, 
    on_demand_time_step::Int)
    _, _, departure_time = extract_passenger_data(passenger_id, ond_locations_data)
    return collect(departure_time:on_demand_time_step:departure_time+max_first_waiting_time)
end

"""
    Helper function to convert num_passenger_dict to vectors for origin
"""
function convert_num_dict_list_order(num_passenger_dict::Dict{Int, Int}, passenger_order::Vector{Int})
    num_passenger_order = Int[]
    for p in passenger_order
        push!(num_passenger_order, num_passenger_dict[p])
    end
    return num_passenger_order
end
