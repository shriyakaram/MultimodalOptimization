"""
    Compute origin and destination travel times between passengers
"""
function compute_travel_times(num_passenger_types::Int, origin_order::Vector{Int}, destination_order::Vector{Int}, 
    ond_locations_data::DataFrame, on_demand_time_step::Int)
    if num_passenger_types == 1
        passenger_origin, passenger_destination, _ = extract_passenger_data(origin_order[1], ond_locations_data)
        return [driving_time(passenger_origin, passenger_destination, on_demand_time_step)], [0.0]
    end

    origin_passenger_travel_times = Float64[]
    destination_passenger_travel_times = Float64[]

    #Passenger travel times for pick-ups/origins, includes time from last passenger origin to first passenger destination
    for p in 1:(num_passenger_types-1)
        current_passenger_origin, _, _ = extract_passenger_data(origin_order[p], ond_locations_data)
        next_passenger_origin, _, _ = extract_passenger_data(origin_order[p+1], ond_locations_data)
        origin_travel_time = driving_time(current_passenger_origin, next_passenger_origin, on_demand_time_step)
        push!(origin_passenger_travel_times, origin_travel_time)
    end

    last_passenger_origin, _, _ = extract_passenger_data(origin_order[num_passenger_types], ond_locations_data)
    _, first_passenger_destination, _ = extract_passenger_data(destination_order[1], ond_locations_data)
    push!(origin_passenger_travel_times, driving_time(last_passenger_origin, first_passenger_destination, on_demand_time_step))

    #Passenger travel times for drop-offs/destinations
    for p in 1:(num_passenger_types-1)
        _, current_passenger_destination, _ = extract_passenger_data(destination_order[p], ond_locations_data)
        _, next_passenger_destination, _ = extract_passenger_data(destination_order[p+1], ond_locations_data)
        destination_travel_time = driving_time(current_passenger_destination, next_passenger_destination, on_demand_time_step)
        push!(destination_passenger_travel_times, destination_travel_time)
    end

    return origin_passenger_travel_times, destination_passenger_travel_times
end

"""
    Computes waiting time between passengers
"""
function compute_waiting_time(start_time::Float64, num_passenger_types::Int, origin_order::Vector{Int}, 
    origin_passenger_travel_times::Vector{Float64}, ond_locations_data::DataFrame)

    _, _, first_departure_time = extract_passenger_data(origin_order[1], ond_locations_data)
    waiting_time = start_time - first_departure_time

    if num_passenger_types == 1
        return [waiting_time]
    end

    waiting_times = zeros(Float64, num_passenger_types)
    waiting_times[1] = waiting_time
    for p in 2:num_passenger_types
        travel_time = origin_passenger_travel_times[p-1]
        _, _, prev_departure_time =  extract_passenger_data(origin_order[p-1], ond_locations_data)
        _, _, current_departure_time =  extract_passenger_data(origin_order[p], ond_locations_data)
        waiting_times[p] = (prev_departure_time + waiting_times[p-1] + travel_time) - current_departure_time
    end
    return waiting_times
end

"""
    Compute cost associated with an on-demand route
"""
function compute_route_cost(num_passenger_types::Int, num_passenger_dict::Dict{Int, Int}, origin_order::Vector{Int}, 
    destination_order::Vector{Int}, origin_passenger_travel_times::Vector{Float64}, destination_passenger_travel_times::Vector{Float64},
    max_on_demand_time::Int, waiting_times::Vector{Float64}, ond_locations_data::DataFrame, on_demand_time_step::Int) 

    origin_num_passenger_order, destination_num_passenger_order = convert_num_dict_list(num_passenger_dict, origin_order, destination_order)

    #intra-group latency
    copy_num_passenger_order = replace(origin_num_passenger_order, 1 => 0)
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
            sum += origin_num_passenger_order[j]
        end
        cumul_origin_time += sum * origin_passenger_travel_times[i]
    end

    #cumulative destination driving times
    cumul_dest_time = 0
    for i in 1:(num_passenger_types-1)
        sum = 0
        for j in (i+1):num_passenger_types
            sum += destination_num_passenger_order[j]
        end
        cumul_dest_time += sum * destination_passenger_travel_times[i]
    end

    #total waiting time
    total_waiting_time = 0
    for i in 1:num_passenger_types
        total_waiting_time += origin_num_passenger_order[i] * waiting_times[i]
    end

    total_route_cost = total_waiting_time + intragroup_latency + cumul_origin_time + cumul_dest_time
    if (total_route_cost <= max_on_demand_time) && (check_detour(num_passenger_types, origin_order, destination_order, 
        origin_passenger_travel_times, destination_passenger_travel_times, ond_locations_data, on_demand_time_step)) 
        return total_route_cost
    else
        return -1
    end
end

"""
    Check if detours less than threshold
"""
function check_detour(num_passenger_types::Int, origin_order::Vector{Int}, destination_order::Vector{Int}, 
    origin_passenger_travel_times::Vector{Float64}, destination_passenger_travel_times::Vector{Float64}, 
    ond_locations_data::DataFrame, on_demand_time_step::Int)

    #cumulative origin driving times
    cumul_origin_time = Dict{Int, Float64}()
    for i in 1:num_passenger_types
        cumul_origin_time[origin_order[i]] = sum(origin_passenger_travel_times[i:end])
    end

    #cumulative destination driving times
    cumul_dest_time = Dict{Int, Float64}()
    cumul_dest_time[destination_order[1]] = 0
    for i in 2:num_passenger_types
        cumul_dest_time[destination_order[i]] = sum(destination_passenger_travel_times[1:(i-1)])
    end

    #direct o-d time 
    direct_time = Dict{Int, Float64}()
    for i in 1:num_passenger_types
        origin, destination, _  = extract_passenger_data(origin_order[i], ond_locations_data)
        od_driving_time = driving_time(origin, destination, on_demand_time_step)
        direct_time[origin_order[i]] = od_driving_time
    end

    #compute detours
    total_detours = Float64[]
    for p in origin_order
        detour = cumul_origin_time[p] + cumul_dest_time[p] - direct_time[p]
        push!(total_detours, detour)
    end

    return !any(x -> x > 10, total_detours)
end

"""
    Create an on-demand route
"""
function create_one_route(start_time::Float64, num_passenger_types::Int, origin_order::Vector{Int}, destination_order::Vector{Int}, 
        num_passenger_dict::Dict{Int, Int}, ond_locations_data::DataFrame, max_on_demand_time::Int, on_demand_time_step::Int)

    origin_passenger_travel_times, destination_passenger_travel_times = compute_travel_times(num_passenger_types, origin_order, 
        destination_order, ond_locations_data, on_demand_time_step)
    end_time = round_time_step(start_time + sum(origin_passenger_travel_times) + sum(destination_passenger_travel_times), on_demand_time_step)
    #end_time = start_time + sum(origin_passenger_travel_times) + sum(destination_passenger_travel_times)
    waiting_times = compute_waiting_time(start_time, num_passenger_types, origin_order, origin_passenger_travel_times, ond_locations_data)
    passenger_cost = compute_route_cost(num_passenger_types, num_passenger_dict, origin_order, destination_order, origin_passenger_travel_times, 
        destination_passenger_travel_times, max_on_demand_time, waiting_times, ond_locations_data, on_demand_time_step)

    zone = extract_origin_zone(origin_order[1], ond_locations_data)
        
    return OnDRoute(num_passenger_types, origin_order, destination_order, num_passenger_dict, origin_passenger_travel_times, 
                    destination_passenger_travel_times, waiting_times, passenger_cost, start_time, end_time, zone)
end

"""
    Return dict[p] --> list of other passengers are compatible with passenger p 
"""
function compute_passenger_dict(ond_locations_data::DataFrame)
    passenger_dict = Dict{Int, Vector{Int}}()

    #Passengers with the same zone 
    ond_locations_filtered = ond_locations_data[ond_locations_data.origin_zone .== ond_locations_data.dest_zone, :]
    passenger_ids = ond_locations_filtered.passenger_id
    for p in passenger_ids
        p_list = Int[]
        origin_zone = extract_origin_zone(p, ond_locations_data)
        destination_zone = extract_destination_zone(p, ond_locations_data)
        for q in passenger_ids
            other_origin_zone = extract_origin_zone(q, ond_locations_data)
            other_destination_zone = extract_destination_zone(q, ond_locations_data)
            if (origin_zone == other_origin_zone) && (destination_zone == other_destination_zone)
                push!(p_list, q)
            end
        end
        passenger_dict[p] = filter(x -> x != p, p_list)
    end
    
    #=
    passenger_ids = ond_locations_data.passenger_id
    for p in passenger_ids
        passenger_dict[p] = filter(x -> x != p, passenger_ids)
    end
    =#
    return passenger_dict
end

"""
    Build 1-string with kappa number of passengers
"""
function build_1_string(kappa::Int, passenger_id::Int, max_on_demand_time::Int, start_time::Float64, ond_locations_data::DataFrame, 
    routes::Vector{OnDRoute}, time_horizon::Float64, on_demand_time_step::Int)

    for k in 1:kappa
        origin_order = [passenger_id]
        destination_order = [passenger_id]
        num_passenger_dict = Dict(passenger_id => k)
        route = create_one_route(start_time, 1, origin_order, destination_order, num_passenger_dict, ond_locations_data, 
            max_on_demand_time, on_demand_time_step)
        if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
            push!(routes, route)
        end
    end
    return routes
end

"""
    Build k-string with 1 passenger each
"""
function build_k_route_1(k::Int, max_on_demand_time::Int, start_time::Float64, ond_locations_data::DataFrame, 
    origin_order::Vector{Int}, routes::Vector{OnDRoute}, time_horizon::Float64, on_demand_time_step::Int)

    cost_route_dict = Dict{Float64, OnDRoute}()
    num_passenger_dict = Dict{Int, Int}()  
    for p in origin_order
        num_passenger_dict[p] = 1
    end

    feasible_list = []
    for destination_order in unique(collect(permutations(origin_order, k)))
        route = create_one_route(start_time, k, origin_order, destination_order, num_passenger_dict, ond_locations_data, 
            max_on_demand_time, on_demand_time_step)
        bool_cost = (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
        push!(feasible_list, bool_cost)
        if bool_cost
            push!(routes, route)
            #cost_route_dict[route.passenger_cost] = route
        end
    end
    #=
    if !isempty(cost_route_dict)
        min_key = minimum(keys(cost_route_dict))
        min_route = cost_route_dict[min_key]
        push!(routes, min_route)
    end
    =#
    return any(feasible_list), routes
end

"""
    Build 2-strings with >1 number of passengers
"""
function build_2_string(kappa::Int, max_on_demand_time::Int, start_time::Float64, ond_locations_data::DataFrame, 
    origin_order::Vector{Int}, routes::Vector{OnDRoute}, time_horizon::Float64, on_demand_time_step::Int)
    for k in 3:kappa
        for j in 1:(k-1)
            cost_route_dict = Dict{Float64, OnDRoute}()
            num_passenger_dict = Dict{Int, Int}()  
            num_passenger_dict[origin_order[1]] = j
            num_passenger_dict[origin_order[2]] = k-j

            for destination_order in unique(collect(permutations(origin_order, 2)))
                route = create_one_route(start_time, 2, origin_order, destination_order, num_passenger_dict, ond_locations_data, 
                    max_on_demand_time, on_demand_time_step)
                if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
                    push!(routes, route)
                    #cost_route_dict[route.passenger_cost] = route
                end
            end
            #=
            if !isempty(cost_route_dict)
                min_key = minimum(keys(cost_route_dict))
                min_route = cost_route_dict[min_key]
                push!(routes, min_route)
            end
            =#
        end
    end
    return routes
end

"""
    Build 3-strings with >1 number of passengers
"""
function build_3_string(kappa::Int, max_on_demand_time::Int, start_time::Float64, ond_locations_data::DataFrame, origin_order::Vector{Int}, 
    routes::Vector{OnDRoute}, time_horizon::Float64, on_demand_time_step::Int)

    for k in 4:kappa
        order_vectors = string3_helper(k)
        for num_passenger_order in order_vectors
            cost_route_dict = Dict{Float64, OnDRoute}()
            num_passenger_dict = Dict{Int, Int}()  
            num_passenger_dict[origin_order[1]] = num_passenger_order[1]
            num_passenger_dict[origin_order[2]] = num_passenger_order[2]
            num_passenger_dict[origin_order[3]] = num_passenger_order[3]
            
            for destination_order in unique(collect(permutations(origin_order, 3)))
                route = create_one_route(start_time, 3, origin_order, destination_order, num_passenger_dict, ond_locations_data, 
                    max_on_demand_time, on_demand_time_step)
                if (route.passenger_cost >= 0) && (route.end_time <= time_horizon)
                    push!(routes, route)
                    #cost_route_dict[route.passenger_cost] = route
                end
            end
            #=
            if !isempty(cost_route_dict)
                min_key = minimum(keys(cost_route_dict))
                min_route = cost_route_dict[min_key]
                push!(routes, min_route)
            end
            =#
        end
    end
    return routes
end

"""
    Compute cost associated with an on-demand route
"""
function post_compute_route_cost(ond_route::OnDRoute) 

    if ond_route.passenger_cost < 0
        return -1, -1, -1
    end

    num_passenger_types = ond_route.num_passenger_types
    origin_order = ond_route.origin_order
    destination_order = ond_route.destination_order
    num_passenger_dict = ond_route.num_passenger_dict
    origin_passenger_travel_times = ond_route.origin_passenger_travel_times
    destination_passenger_travel_times = ond_route.destination_passenger_travel_times
    waiting_times =  ond_route.passenger_waiting_times

    origin_num_passenger_order, destination_num_passenger_order = convert_num_dict_list(num_passenger_dict, origin_order, destination_order)

    #intra-group latency
    copy_num_passenger_order = replace(origin_num_passenger_order, 1 => 0)
    intragroup_latency = 0
    intragroup_latency = sum(copy_num_passenger_order .^ (3/2))

    #cumulative origin driving times
    cumul_origin_time = 0
    for i in 1:num_passenger_types
        sum = 0
        for j in 1:i
            sum += origin_num_passenger_order[j]
        end
        cumul_origin_time += sum * origin_passenger_travel_times[i]
    end

    #cumulative destination driving times
    cumul_dest_time = 0
    for i in 1:(num_passenger_types-1)
        sum = 0
        for j in (i+1):num_passenger_types
            sum += destination_num_passenger_order[j]
        end
        cumul_dest_time += sum * destination_passenger_travel_times[i]
    end
    
    total_waiting_time = 0
    for i in 1:num_passenger_types
        total_waiting_time += origin_num_passenger_order[i] * waiting_times[i]
    end

    waiting = total_waiting_time + intragroup_latency
    in_vehicle = cumul_origin_time + cumul_dest_time
    return 0, waiting, in_vehicle
end