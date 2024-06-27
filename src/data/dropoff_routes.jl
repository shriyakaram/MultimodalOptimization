"""
    For a line/station pair, find the list of passengers it can serve for drop-offs
"""
function passengers_line_station_dropoffs(line::Int, station::Int, passengers::Vector{Passenger})
    passenger_ids = [p.passenger_id for p in passengers]
    passengers_ids_line_station = Int[]
    for p in passenger_ids
        routes_line = [ptr.transit_routes for ptr in passengers[p].passenger_feeder_routes if (ptr.line == line)]
        if !isempty(routes_line)
            routes = reduce(vcat, routes_line)
            routes_station = [r for r in routes if r.destination_node.station == station]
            if !isempty(routes_station)
                push!(passengers_ids_line_station, p)
            end
        end
    end
    return passengers_ids_line_station
end

"""
    Compute travel times between passengers for drop-offs
"""
function compute_travel_times_dropoffs(num_passenger_types::Int, destination_order::Vector{Int}, line::Int, station::Int,
    ond_locations_data::DataFrame, transit_stops::DataFrame, on_demand_time_step::Int)

    #find coordinates for line/station
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    station_location = station_lat_lon(station, transit_stops_line)

    if num_passenger_types == 1
        _, passenger_destination, _ = extract_passenger_data(destination_order[1], ond_locations_data)
        return [driving_time(station_location, passenger_destination, on_demand_time_step)]
    end

    #passenger travel times for drop-offs
    passenger_travel_times = Float64[]
    _, passenger_destination, _ = extract_passenger_data(destination_order[1], ond_locations_data)
    push!(passenger_travel_times, driving_time(passenger_destination, station_location, on_demand_time_step))

    for p in 1:(num_passenger_types-1)
        _, current_passenger_destination, _ = extract_passenger_data(destination_order[p], ond_locations_data)
        _, next_passenger_destination, _ = extract_passenger_data(destination_order[p+1], ond_locations_data)
        destination_travel_time = driving_time(current_passenger_destination, next_passenger_destination, on_demand_time_step)
        push!(passenger_travel_times, destination_travel_time)
    end

    return passenger_travel_times
end

"""
    Check if detours less than threshold for drop-off routes
"""
function check_detour_dropoffs(num_passenger_types::Int, destination_order::Vector{Int}, line::Int, station::Int, 
    passenger_travel_times::Vector{Float64}, ond_locations_data::DataFrame, transit_stops::DataFrame, on_demand_time_step::Int)

    #find coordinates for line/station
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    station_location = station_lat_lon(station, transit_stops_line)

    #cumulative destination driving times
    cumul_dest_time = Dict{Int, Float64}()
    for i in 1:num_passenger_types
        cumul_dest_time[destination_order[i]] = sum(passenger_travel_times[1:i])
    end

    #direct origin to station time 
    direct_time = Dict{Int, Float64}()
    for i in 1:num_passenger_types
        _, destination, _  = extract_passenger_data(destination_order[i], ond_locations_data)
        station_driving_time = driving_time(destination, station_location, on_demand_time_step)
        direct_time[destination_order[i]] = station_driving_time
    end

    #compute detours
    total_detours = Float64[]
    for p in destination_order
        detour = cumul_dest_time[p] - direct_time[p]
        push!(total_detours, detour)
    end

    return !any(x -> x > 10, total_detours)
end

"""
    Helper function to create a dictionary for each passenger p with the earliest and latest transit alighting time
"""
function transit_alight_times(line::Int, station::Int, passengers::Vector{Passenger}, max_waiting::Int, time_horizon::Float64)
    passenger_alight_dict = Dict{Int, Tuple{Float64, Float64}}()  
    passenger_ids = [p.passenger_id for p in passengers]

    for p in passenger_ids
        routes_line = [ptr.transit_routes for ptr in passengers[p].passenger_feeder_routes if (ptr.line == line)]
        if isempty(routes_line)
            passenger_alight_dict[p] = (0.0, 0.0)
        else 
            routes = reduce(vcat, routes_line)
            routes_station = [r for r in routes if r.destination_node.station == station]
            if isempty(routes_station)
                passenger_alight_dict[p] = (0.0, 0.0)
            else
                alighting_times = [r.destination_node.time for r in routes_station]
                min_val = minimum(alighting_times)
                max_val = maximum(alighting_times)
                end_time = min(max_val + max_waiting, time_horizon)
                passenger_alight_dict[p] = (min_val, end_time)
            end
        end
    end
    return passenger_alight_dict
end

"""
    Compute drop-off route start times for a route that begins with passenger p
"""
function dropoff_route_start_times(passenger_id::Int, passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}}, on_demand_time_step::Int)
    min_val = passenger_alight_dict[passenger_id][1]
    max_val = passenger_alight_dict[passenger_id][2]
    start_times = collect(min_val:on_demand_time_step:max_val)
    return start_times
end

"""
    Compute cost associated with a drop-off route
"""
function compute_dropoff_route_cost(num_passenger_types::Int, num_passenger_dict::Dict{Int, Int}, destination_order::Vector{Int}, 
    passenger_travel_times::Vector{Float64}, max_on_demand_time::Int, line::Int, station::Int, ond_locations_data::DataFrame, 
    transit_stops::DataFrame, on_demand_time_step::Int, start_time::Float64, passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}})

    num_passenger_order = convert_num_dict_list_order(num_passenger_dict, destination_order)

    #intra-group latency
    copy_num_passenger_order = replace(num_passenger_order, 1 => 0)
    intragroup_latency = 0
    intragroup_latency = sum(copy_num_passenger_order .^ (3/2))

    #cumulative destination driving times
    cumul_dest_time = 0
    for i in 1:num_passenger_types
        sum = 0
        for j in i:num_passenger_types
            sum += num_passenger_order[j]
        end
        cumul_dest_time += sum * passenger_travel_times[i]
    end

    total_route_cost = intragroup_latency + cumul_dest_time
    if (total_route_cost <= max_on_demand_time) && check_departure_window(passenger_alight_dict, destination_order, start_time) && 
        check_detour_dropoffs(num_passenger_types, destination_order, line, station, passenger_travel_times, 
        ond_locations_data, transit_stops, on_demand_time_step) 
        return total_route_cost
    else
        return -1
    end
end

"""
    Create a drop-off route
"""
function create_dropoff_route(start_time::Float64, num_passenger_types::Int, destination_order::Vector{Int}, 
    num_passenger_dict::Dict{Int, Int}, max_on_demand_time::Int, line::Int, station::Int, ond_locations_data::DataFrame, 
    transit_stops::DataFrame, on_demand_time_step::Int, passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}})

    passenger_travel_times = compute_travel_times_dropoffs(num_passenger_types, destination_order, line, station, ond_locations_data, 
        transit_stops, on_demand_time_step)
    end_time = round_time_step(start_time + sum(passenger_travel_times), on_demand_time_step)
    passenger_cost = compute_dropoff_route_cost(num_passenger_types, num_passenger_dict, destination_order, passenger_travel_times, 
        max_on_demand_time, line, station, ond_locations_data, transit_stops, on_demand_time_step, start_time, passenger_alight_dict)

    #zone of the route
    transit_stops_line = filter(row -> row.line == line, transit_stops)
    row_index = findfirst(transit_stops_line.stop_sequence .== station)
    zone = transit_stops_line[row_index, :zone_id]
        
    return DropoffRoute(num_passenger_types, destination_order, num_passenger_dict, passenger_travel_times, passenger_cost, 
        start_time, end_time, station, line, zone)
end


"""
    Build 1-string with kappa number of passengers
"""
function build_1_string_dropoff(kappa::Int, passenger_id::Int, max_on_demand_time::Int, line::Int, station::Int, time_horizon::Float64,
    ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{DropoffRoute}, on_demand_time_step::Int, start_time::Float64,
    passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}})

    for k in 1:kappa
        destination_order = [passenger_id]
        num_passenger_dict = Dict(passenger_id => k)

        route = create_dropoff_route(start_time, 1, destination_order, num_passenger_dict, max_on_demand_time, line, 
            station, ond_locations_data, transit_stops, on_demand_time_step, passenger_alight_dict)
        if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
            push!(routes, route)
        end
    end
    return routes
end

"""
    Build k-string with 1 passenger each
"""
function build_k_dropoff_route_1(k::Int, max_on_demand_time::Int, destination_order::Vector{Int}, time_horizon::Float64,
    line::Int, station::Int, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{DropoffRoute}, 
    on_demand_time_step::Int, start_time::Float64, passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}})

    num_passenger_dict = Dict{Int, Int}()  
    for p in destination_order
        num_passenger_dict[p] = 1
    end

    route = create_dropoff_route(start_time, k, destination_order, num_passenger_dict, max_on_demand_time, line, 
        station, ond_locations_data, transit_stops, on_demand_time_step, passenger_alight_dict)

    bool_cost = (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
    if bool_cost
        push!(routes, route)
    end

    return bool_cost, routes
end

"""
    Build 2-strings with >1 number of passengers
"""
function build_2_string_dropoff(kappa::Int, max_on_demand_time::Int, destination_order::Vector{Int}, time_horizon::Float64,
    line::Int, station::Int, ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{DropoffRoute},
    on_demand_time_step::Int, start_time::Float64, passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}})
    for k in 3:kappa
        for j in 1:(k-1)
            num_passenger_dict = Dict{Int, Int}()  
            num_passenger_dict[destination_order[1]] = j
            num_passenger_dict[destination_order[2]] = k-j

            route = create_dropoff_route(start_time, 2, destination_order, num_passenger_dict, max_on_demand_time, line, 
                station, ond_locations_data, transit_stops, on_demand_time_step, passenger_alight_dict)
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
function build_3_string_dropoff(kappa::Int, max_on_demand_time::Int, destination_order::Vector{Int}, time_horizon::Float64, line::Int, station::Int, 
    ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{DropoffRoute}, on_demand_time_step::Int, start_time::Float64,
    passenger_alight_dict::Dict{Int, Tuple{Float64, Float64}})

    for k in 4:kappa
        order_vectors = string3_helper(k)
        for num_passenger_order in order_vectors
            num_passenger_dict = Dict{Int, Int}()  
            num_passenger_dict[destination_order[1]] = num_passenger_order[1]
            num_passenger_dict[destination_order[2]] = num_passenger_order[2]
            num_passenger_dict[destination_order[3]] = num_passenger_order[3]
            
            route = create_dropoff_route(start_time, 3, destination_order, num_passenger_dict, max_on_demand_time, line, 
                station, ond_locations_data, transit_stops, on_demand_time_step, passenger_alight_dict)
            if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
                push!(routes, route)
            end
        end
    end
    return routes
end

"""
    Create the vector of dropoff routes for a line/station
    Implemented for kappa = 4 
"""
function create_dropoff_routes_line_station(kappa::Int, max_on_demand_time::Int, line::Int, station::Int, time_horizon::Float64,
        ond_locations_data::DataFrame, transit_stops::DataFrame, routes::Vector{DropoffRoute}, passengers::Vector{Passenger}, 
        on_demand_time_step::Int, max_waiting::Int)

    passenger_ids = passengers_line_station_dropoffs(line, station, passengers)
    if isempty(passenger_ids)
        return routes
    end

    passenger_alight_dict = transit_alight_times(line, station, passengers, max_waiting, time_horizon)
    for p in passenger_ids
        route_start_times = dropoff_route_start_times(p, passenger_alight_dict, on_demand_time_step)
        for start_time in route_start_times
            routes = build_1_string_dropoff(kappa, p, max_on_demand_time, line, station, time_horizon, ond_locations_data,
                transit_stops, routes, on_demand_time_step, start_time, passenger_alight_dict)
            passenger_list = filter(x -> !(x in Set(p)), passenger_ids)
            for l in passenger_list
                bool_cost, routes = build_k_dropoff_route_1(2, max_on_demand_time, [p,l], time_horizon, line, station,
                    ond_locations_data, transit_stops, routes, on_demand_time_step, start_time, passenger_alight_dict)
                if bool_cost 
                    for q in filter(x -> !(x in Set(l)), passenger_list)
                        bool_cost, routes = build_k_dropoff_route_1(3, max_on_demand_time, [p,l,q], time_horizon, line, station,
                            ond_locations_data, transit_stops, routes, on_demand_time_step, start_time, passenger_alight_dict)
                        if bool_cost 
                            #for w in filter(x -> !(x in [l,q]), passenger_list)
                            #    bool_cost, routes = build_k_dropoff_route_1(4, max_on_demand_time, [p,l,q,w], time_horizon, line, station,
                            #        ond_locations_data, transit_stops, routes, on_demand_time_step, start_time, passenger_alight_dict)
                            #end
                            routes = build_3_string_dropoff(kappa, max_on_demand_time, [p,l,q], time_horizon, line, station, 
                                ond_locations_data, transit_stops, routes, on_demand_time_step, start_time, passenger_alight_dict)
                        end
                    end
                    routes = build_2_string_dropoff(kappa, max_on_demand_time, [p,l], time_horizon, line, station,
                        ond_locations_data, transit_stops, routes, on_demand_time_step, start_time, passenger_alight_dict)
                end
            end
        end
    end

    return routes
end

"""
    Compute cost associated with an on-demand route
"""
function post_compute_dropoff_route_cost(dropoff_route::DropoffRoute) 

    if dropoff_route.passenger_cost < 0
        return -1, -1, -1
    end

    num_passenger_types = dropoff_route.num_passenger_types
    destination_order = dropoff_route.passenger_order
    num_passenger_dict = dropoff_route.num_passenger_dict
    passenger_travel_times = dropoff_route.passenger_travel_times

    num_passenger_order = convert_num_dict_list_order(num_passenger_dict, destination_order)

    #intra-group latency
    copy_num_passenger_order = replace(num_passenger_order, 1 => 0)
    intragroup_latency = 0
    intragroup_latency = sum(copy_num_passenger_order .^ (3/2))

    #cumulative destination driving times
    cumul_dest_time = 0
    for i in 1:num_passenger_types
        sum = 0
        for j in i:num_passenger_types
            sum += num_passenger_order[j]
        end
        cumul_dest_time += sum * passenger_travel_times[i]
    end

    walk = 0
    return walk, intragroup_latency, cumul_dest_time
end