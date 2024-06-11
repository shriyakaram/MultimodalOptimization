"""
    For a line/station pair, find the list of passengers it can serve for pick-ups
"""
function passengers_line_station_pickups(line::Int, station::Int, ond_locations_data::DataFrame, transit_stops::DataFrame)
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    row_index = findfirst(transit_stops_line.stop_sequence .== station)
    zone = transit_stops_line[row_index, :zone_id]
    filtered_df = ond_locations_data[ond_locations_data.origin_zone .== zone, :]
    return filtered_df.passenger_id
end

"""
    Compute travel times between passengers for pick-ups
"""
function compute_travel_times_pickups(num_passenger_types::Int, origin_order::Vector{Int}, line::Int, station::Int,
    ond_locations_data::DataFrame, transit_stops::DataFrame, on_demand_time_step::Int)

    #find coordinates for line/station
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    station_location = station_lat_lon(station, transit_stops_line)

    if num_passenger_types == 1
        passenger_origin, _, _ = extract_passenger_data(origin_order[1], ond_locations_data)
        return [driving_time(passenger_origin, station_location, on_demand_time_step)]
    end

    #Passenger travel times for pick-ups/origins
    passenger_travel_times = Float64[]
    for p in 1:(num_passenger_types-1)
        current_passenger_origin, _, _ = extract_passenger_data(origin_order[p], ond_locations_data)
        next_passenger_origin, _, _ = extract_passenger_data(origin_order[p+1], ond_locations_data)
        origin_travel_time = driving_time(current_passenger_origin, next_passenger_origin, on_demand_time_step)
        push!(passenger_travel_times, origin_travel_time)
    end

    last_passenger_origin, _, _ = extract_passenger_data(origin_order[num_passenger_types], ond_locations_data)
    push!(passenger_travel_times, driving_time(last_passenger_origin, station_location, on_demand_time_step))

    return passenger_travel_times
end

"""
    Computes waiting time between passengers
"""
function compute_waiting_time_pick_ups(start_time::Float64, num_passenger_types::Int, origin_order::Vector{Int}, 
    passenger_travel_times::Vector{Float64}, ond_locations_data::DataFrame)

    _, _, first_departure_time = extract_passenger_data(origin_order[1], ond_locations_data)
    waiting_time = start_time - first_departure_time

    if num_passenger_types == 1
        return [waiting_time]
    end

    waiting_times = zeros(Float64, num_passenger_types)
    waiting_times[1] = waiting_time
    for p in 2:num_passenger_types
        travel_time = passenger_travel_times[p-1]
        _, _, prev_departure_time =  extract_passenger_data(origin_order[p-1], ond_locations_data)
        _, _, current_departure_time =  extract_passenger_data(origin_order[p], ond_locations_data)
        waiting_times[p] = (prev_departure_time + waiting_times[p-1] + travel_time) - current_departure_time
    end
    return waiting_times
end

"""
    Compute cost associated with an on-demand route
"""
function compute_pickup_route_cost(num_passenger_types::Int, num_passenger_dict::Dict{Int, Int}, origin_order::Vector{Int}, 
    passenger_travel_times::Vector{Float64}, max_on_demand_time::Int, waiting_times::Vector{Float64})

    num_passenger_order = convert_num_dict_list_order(num_passenger_dict, origin_order)

    #intra-group latency
    copy_num_passenger_order = replace(num_passenger_order, 1 => 0)
    intragroup_latency = 0
    intragroup_latency = sum(copy_num_passenger_order .^ (3/2))

    #feasiblity condition, return negative cost 
    if any(x -> x < 0, waiting_times) #ok for now, fix later
        return -1
    end

    #maximum waiting time threshold of 15 minutes
    if any(x -> x > 15, (waiting_times .+ (copy_num_passenger_order .^ (3/2))))
        return -1
    end

    #cumulative origin driving times
    cumul_origin_time = 0
    for i in 1:num_passenger_types
        sum = 0
        for j in 1:i
            sum += num_passenger_order[j]
        end
        cumul_origin_time += sum * passenger_travel_times[i]
    end

    #total waiting time
    total_waiting_time = 0
    for i in 1:num_passenger_types
        total_waiting_time += num_passenger_order[i] * waiting_times[i]
    end

    total_route_cost = total_waiting_time + intragroup_latency + cumul_origin_time
    if (total_route_cost <= max_on_demand_time)
        return total_route_cost
    else
        return -1
    end
end

"""
    Create a pick-up route
"""
function create_pickup_route(start_time::Float64, num_passenger_types::Int, origin_order::Vector{Int}, num_passenger_dict::Dict{Int, Int}, 
    max_on_demand_time::Int, time_horizon::Float64, line::Int, station::Int, ond_locations_data::DataFrame, transit_stops::DataFrame,
    on_demand_time_step::Int)

    passenger_travel_times = compute_travel_times_pickups(num_passenger_types, origin_order, line, station, ond_locations_data, 
        transit_stops, on_demand_time_step)
    end_time = round_time_step(start_time + sum(passenger_travel_times), on_demand_time_step)
    waiting_times = compute_waiting_time_pick_ups(start_time, num_passenger_types, origin_order, passenger_travel_times, ond_locations_data)
    passenger_cost = compute_pickup_route_cost(num_passenger_types, num_passenger_dict, origin_order, passenger_travel_times, 
        max_on_demand_time, waiting_times)

    #zone of the route
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    row_index = findfirst(transit_stops_line.stop_sequence .== station)
    zone = transit_stops_line[row_index, :zone_id]
        
    return PickupRoute(num_passenger_types, origin_order, num_passenger_dict, passenger_travel_times, waiting_times, 
        passenger_cost, start_time, end_time, station, line, zone)
end

"""
    Build 1-string with kappa number of passengers
"""
function build_1_string_pickup(kappa::Int, passenger_id::Int, max_on_demand_time::Int, start_time::Float64,
    line::Int, station::Int, time_horizon::Float64, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{PickupRoute},
    on_demand_time_step::Int)

    for k in 1:kappa
        origin_order = [passenger_id]
        num_passenger_dict = Dict(passenger_id => k)
        route = create_pickup_route(start_time, 1, origin_order, num_passenger_dict, max_on_demand_time, time_horizon, line, station, 
            ond_locations_data, transit_stops, on_demand_time_step)
        if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
            push!(routes, route)
        end
    end
    return routes
end

"""
    Build k-string with 1 passenger each
"""
function build_k_pickup_route_1(k::Int, max_on_demand_time::Int, start_time::Float64, origin_order::Vector{Int}, 
    line::Int, station::Int, time_horizon::Float64, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{PickupRoute},
    on_demand_time_step::Int)

    num_passenger_dict = Dict{Int, Int}()  
    for p in origin_order
        num_passenger_dict[p] = 1
    end

    route = create_pickup_route(start_time, k, origin_order, num_passenger_dict, max_on_demand_time, time_horizon, line, station, 
        ond_locations_data, transit_stops, on_demand_time_step)
        
    bool_cost = (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
    if bool_cost
        push!(routes, route)
    end

    return bool_cost, routes
end

"""
    Build 2-strings with >1 number of passengers
"""
function build_2_string_pickup(kappa::Int, max_on_demand_time::Int, start_time::Float64, origin_order::Vector{Int}, 
    line::Int, station::Int, time_horizon::Float64, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{PickupRoute},
    on_demand_time_step::Int)
    for k in 3:kappa
        for j in 1:(k-1)
            num_passenger_dict = Dict{Int, Int}()  
            num_passenger_dict[origin_order[1]] = j
            num_passenger_dict[origin_order[2]] = k-j

            route = create_pickup_route(start_time, 2, origin_order, num_passenger_dict, max_on_demand_time, time_horizon, line, 
                station, ond_locations_data, transit_stops, on_demand_time_step)
            if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
                push!(routes, route)
            end
        end
    end
    return routes
end


"""
    Build 3-strings with >1 number of passengers
"""
function build_3_string_pickup(max_on_demand_time::Int, start_time::Float64, origin_order::Vector{Int}, line::Int, station::Int, 
    time_horizon::Float64, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{PickupRoute}, on_demand_time_step::Int)

    for num_passenger_order in unique(collect(permutations(([1,1,2]), 3)))
        num_passenger_dict = Dict{Int, Int}()  
        num_passenger_dict[origin_order[1]] = num_passenger_order[1]
        num_passenger_dict[origin_order[2]] = num_passenger_order[2]
        num_passenger_dict[origin_order[3]] = num_passenger_order[3]
        
        route = create_pickup_route(start_time, 3, origin_order, num_passenger_dict, max_on_demand_time, time_horizon, line, 
            station, ond_locations_data, transit_stops, on_demand_time_step)
        if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
            push!(routes, route)
        end
    end
    return routes
end

"""
    Create the vector of pick-up routes for a line/station
    Implemented for kappa = 4 
"""
function create_pickup_routes_line_station(kappa::Int, max_on_demand_time::Int, max_first_waiting_time::Float64, line::Int, station::Int,
        time_horizon::Float64, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{PickupRoute}, on_demand_time_step::Int)

    passenger_ids = passengers_line_station_pickups(line, station, ond_locations_data, transit_stops)

    for p in passenger_ids
        route_start_times = calc_route_start_times(max_first_waiting_time, p, ond_locations_data, on_demand_time_step)
        for start_time in route_start_times
            routes = build_1_string_pickup(kappa, p, max_on_demand_time, start_time, line, station, time_horizon, 
                ond_locations_data, transit_stops, routes, on_demand_time_step)
            if kappa >= 2
                passenger_list = filter(x -> !(x in Set(p)), passenger_ids)
                for l in passenger_list
                    bool_cost, routes = build_k_pickup_route_1(2, max_on_demand_time, start_time, [p,l], line, station, time_horizon,
                        ond_locations_data, transit_stops, routes, on_demand_time_step)
                    if bool_cost && kappa >= 3
                        for q in filter(x -> !(x in Set(l)), passenger_list)
                            bool_cost, routes = build_k_pickup_route_1(3, max_on_demand_time, start_time, [p,l,q], line, station, time_horizon,
                                ond_locations_data, transit_stops, routes, on_demand_time_step)
                            if bool_cost && kappa >= 4
                                for w in filter(x -> !(x in [l,q]), passenger_list)
                                    bool_cost, routes = build_k_pickup_route_1(4, max_on_demand_time, start_time, [p,l,q,w], line, station, 
                                        time_horizon, ond_locations_data, transit_stops, routes, on_demand_time_step)
                                end
                                routes = build_3_string_pickup(max_on_demand_time, start_time, [p,l,q], line, station, time_horizon, 
                                    ond_locations_data, transit_stops, routes, on_demand_time_step)
                            end
                        end
                        routes = build_2_string_pickup(kappa, max_on_demand_time, start_time, [p,l], line, station, time_horizon,
                            ond_locations_data, transit_stops, routes, on_demand_time_step)
                    end
                end
            end
        end
    end

    return routes
end

"""
    Compute cost associated with an on-demand route
"""
function post_compute_pickup_route_cost(pickup_route::PickupRoute) 

    if pickup_route.passenger_cost < 0
        return -1, -1, -1
    end

    num_passenger_types = pickup_route.num_passenger_types
    origin_order = pickup_route.passenger_order
    num_passenger_dict = pickup_route.num_passenger_dict
    passenger_travel_times = pickup_route.passenger_travel_times
    waiting_times =  pickup_route.passenger_waiting_times

    num_passenger_order = convert_num_dict_list_order(num_passenger_dict, origin_order)

    #intra-group latency
    copy_num_passenger_order = replace(num_passenger_order, 1 => 0)
    intragroup_latency = 0
    intragroup_latency = sum(copy_num_passenger_order .^ (3/2))

    #cumulative origin driving times
    cumul_origin_time = 0
    for i in 1:num_passenger_types
        sum = 0
        for j in 1:i
            sum += num_passenger_order[j]
        end
        cumul_origin_time += sum * passenger_travel_times[i]
    end

    #total waiting time
    total_waiting_time = 0
    for i in 1:num_passenger_types
        total_waiting_time += num_passenger_order[i] * waiting_times[i]
    end

    waiting = total_waiting_time + intragroup_latency
    return 0, waiting, cumul_origin_time
end
 