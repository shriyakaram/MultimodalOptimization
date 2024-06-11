"""
    Add fleet assignment constraints
"""
function add_fleet_assignment_constraints!(model::Model, data::OnDemandTransitData, F::Int)
    veh_tr = model[:veh_tr] 
    veh_od_zone = model[:veh_od_zone]
    veh_mm_zone = model[:veh_mm_zone] 
    zones = zone_id_list(data)

    @constraint(model, fleet_assignment, veh_tr + sum(veh_od_zone[i] for i in zones) + sum(veh_mm_zone[i] for i in zones) == F)
    
    return nothing
end

"""
    Add transit vehicle constraints
"""
function add_transit_vehicle_constraints!(transit_times::Vector{Float64}, transit_time_step::Int, model::Model, data::OnDemandTransitData)
    x = model[:x]
    veh_tr = model[:veh_tr] 
    veh_tr_time = model[:veh_tr_time] 
    
    #one frequency for each line 
    line_frequencies = data.line_frequencies
    lines, frequencies = line_frequency_pairs(line_frequencies)
    @constraint(model, one_frequency[l = lines], sum(x[l,f] for f in frequencies) <= 1)

    #initial transit vehicles
    @constraint(model, initial_transit_vehicles, veh_tr_time[0] == 0)

    #transit vehicles at time t
    @constraint(model, transit_vehicles_time[t in setdiff(transit_times, [0])], veh_tr_time[t] == veh_tr_time[t-transit_time_step] + 
        sum(x[l,f] for f in frequencies for l in lines if t in line_frequency_start_times(l, f, data)) - 
        sum(x[l,f] for f in frequencies for l in lines if t in line_frequency_end_times(l, f, data)))

    #flow balance over time
    @constraint(model, transit_vehicle_flow[t in transit_times], veh_tr_time[t] <= veh_tr)

    return nothing
end

"""
    Add on-demand vehicle constraints
"""
function add_ondemand_vehicle_constraints!(ondemand_times::Vector{Float64}, on_demand_time_step::Int, extra_veh_od::Int,
        extra_veh_mm::Int, model::Model, data::OnDemandTransitData)

    veh_od_zone = model[:veh_od_zone] 
    veh_od_zone_time = model[:veh_od_zone_time] 
    veh_mm_zone = model[:veh_mm_zone] 
    veh_mm_zone_time = model[:veh_mm_zone_time] 

    y_od = model[:y_od] 
    y_pickup = model[:y_pickup] 
    y_dropoff = model[:y_dropoff] 
    zones = zone_id_list(data)

    #initial od vehicles
    @constraint(model, initial_od_vehicles[i = zones], veh_od_zone_time[0, i] == 0)

    #od vehicles at time t
    @constraint(model, od_vehicles_time[t = setdiff(ondemand_times, [0]), i = zones], 
        veh_od_zone_time[t, i] == veh_od_zone_time[t-on_demand_time_step, i] + 
        sum(od_route_enter(t, i, data.OnD_routes[g], on_demand_time_step) * y_od[g] for g in eachindex(data.OnD_routes)) -
        sum(od_route_exit(t, i, data.OnD_routes[g], on_demand_time_step) * y_od[g] for g in eachindex(data.OnD_routes)))

    #od flow balance over time 
    @constraint(model, od_vehicle_flow[t = ondemand_times, i = zones], veh_od_zone_time[t,i] <= veh_od_zone[i] + extra_veh_od)

    #initial first/last mile vehicles
    @constraint(model, initial_mm_vehicles[i = zones], veh_mm_zone_time[0, i] == 0)

    #first/last mile vehicles at time t
    @constraint(model, mm_vehicles_time[t = setdiff(ondemand_times, [0]), i = zones], 
        veh_mm_zone_time[t, i] == veh_mm_zone_time[t-on_demand_time_step, i] + 
        sum(y_pickup[g] for g in eachindex(data.pickup_routes) if ((data.pickup_routes[g].start_time == t) && (data.pickup_routes[g].zone == i))) +
        sum(y_dropoff[g] for g in eachindex(data.dropoff_routes) if ((data.dropoff_routes[g].start_time == t) && (data.dropoff_routes[g].zone == i))) -
        sum(y_pickup[g] for g in eachindex(data.pickup_routes) if ((data.pickup_routes[g].end_time == t) && (data.pickup_routes[g].zone == i))) -
        sum(y_dropoff[g] for g in eachindex(data.dropoff_routes) if ((data.dropoff_routes[g].end_time == t) && (data.dropoff_routes[g].zone == i))))

    #first/last mile vehicle flow balance over time
    @constraint(model, mm_vehicle_flow[t = ondemand_times, i = zones], veh_mm_zone_time[t,i] <= veh_mm_zone[i] + extra_veh_mm)

    return nothing
end

"""
    Add mode assignment constraints
"""
function add_mode_assignment_constraints!(model::Model, data::OnDemandTransitData)
    m = model[:m]
    @constraint(model, mode_assignment[i = data.zone_pairs], sum(m[i,k] for k in 1:3) == 1)
    #@constraint(model, check[i = data.zone_pairs], m[i,3] == 1)
    return nothing
end

"""
    Add transit passenger assignment constraints
"""
function add_transit_passenger_constraints!(model::Model, data::OnDemandTransitData)
    z_tr = model[:z_tr]
    x = model[:x]
    m = model[:m]

    #select transit route if corresponding transit line/frequency opened
    @constraint(model, select_transit_link[p = eachindex(data.passengers), l = lines_passenger(p, data), f = freq_passenger(p, l, data), 
    r = routes_passenger(p, l, f, data)], z_tr[p, l, f, r] <= x[l, f])

    #assign transit route if transit selected for a passenger
    @constraint(model, transit_routes[p = eachindex(data.passengers)],
        sum(z_tr[p, l, f, r] for l in lines_passenger(p, data) for f in freq_passenger(p, l, data) for r in routes_passenger(p, l, f, data)) ==  
        m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 2])

    return nothing
end

"""
    Add od passenger assignment constraints
"""
function add_od_passenger_constraints!(model::Model, data::OnDemandTransitData)
    y_od = model[:y_od]
    m = model[:m]

    #select an on-demand route only if on-demand selected for a passenger 
    for g in eachindex(data.OnD_routes)
        for p in eachindex(data.passengers)
            if p in data.OnD_routes[g].origin_order
                @constraint(model, num_passengers_type_od(data.passengers[p].passenger_id, data.OnD_routes[g])*y_od[g] <= 
                (data.passengers[p].demand * m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 1]))
            end
        end
    end

    #select the number of on-demand routes if on-demand selected for a passenger
    @constraint(model, num_ondemand_routes[p = eachindex(data.passengers)],
        sum(y_od[g]*num_passengers_type_od(data.passengers[p].passenger_id, data.OnD_routes[g]) for g in eachindex(data.OnD_routes) 
        if p in data.OnD_routes[g].origin_order) == (data.passengers[p].demand * 
            m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 1]))
    
    return nothing
end

"""
    Add multimodal passenger assignment constraints
"""
function add_multimodal_passenger_constraints!(max_waiting::Int, transit_times::Vector{Float64}, model::Model, data::OnDemandTransitData)
    
    z_mm = model[:z_mm]
    x = model[:x]
    y_pickup = model[:y_pickup] 
    y_dropoff = model[:y_dropoff] 
    m = model[:m]

    #select transit route if corresponding transit line/frequency opened
    @constraint(model, select_transit_link_feeder[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), 
        f = freq_passenger_feeder(p, l, data), r = routes_passenger_feeder(p, l, f, data)], z_mm[p, l, f, r] <= x[l, f])

    #assign transit route if transit selected for a passenger
    @constraint(model, transit_routes_feeder[p = eachindex(data.passengers)],
        sum(z_mm[p, l, f, r] for l in lines_passenger_feeder(p, data) for f in freq_passenger_feeder(p, l, data) 
        for r in routes_passenger_feeder(p, l, f, data)) == m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 3])
    
    #select a pick-up route only if multimodal selected for a passenger 
    for g in eachindex(data.pickup_routes)
        for p in eachindex(data.passengers)
            if p in data.pickup_routes[g].passenger_order
                @constraint(model, num_passengers_type_route(data.passengers[p].passenger_id, data.pickup_routes[g]) * y_pickup[g] <= 
                (data.passengers[p].demand * m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 3]))
            end
        end
    end

    #select a drop-off route only if multimodal selected for a passenger 
    for g in eachindex(data.dropoff_routes)
        for p in eachindex(data.passengers)
            if p in data.dropoff_routes[g].passenger_order
                @constraint(model, num_passengers_type_route(data.passengers[p].passenger_id, data.dropoff_routes[g]) * y_dropoff[g] <= 
                (data.passengers[p].demand * m[(data.passengers[p].origin_zone, data.passengers[p].destination_zone), 3]))
            end
        end
    end

    #flow balance for pick-up routes
    @constraint(model, pickups_flow[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), s = line_stations(l, data), 
        t in transit_times], sum(y_pickup[g]*num_passengers_type_route(data.passengers[p].passenger_id, data.pickup_routes[g]) 
        for g in eachindex(data.pickup_routes) if ((p in data.pickup_routes[g].passenger_order) && (data.pickup_routes[g].line == l) && 
        (data.pickup_routes[g].transit_station == s) && (t >= data.pickup_routes[g].end_time) && 
        (t <= max_waiting + data.pickup_routes[g].end_time))) >= data.passengers[p].demand * sum(z_mm[p, l, f, r] for f in freq_passenger_feeder(p, l, data) 
        for r in outgoing_transit_nodes(p, l, f, s, t, data)))
    
    #flow balance for drop-off routes
    @constraint(model, dropoffs_flow[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), s = line_stations(l, data),
        t in transit_times], sum(y_dropoff[g]*num_passengers_type_route(data.passengers[p].passenger_id, data.dropoff_routes[g]) 
        for g in eachindex(data.dropoff_routes) if ((p in data.dropoff_routes[g].passenger_order) && 
        (data.dropoff_routes[g].line == l) && (data.dropoff_routes[g].transit_station == s) && 
        (t <= data.dropoff_routes[g].start_time) && (t >= data.dropoff_routes[g].start_time - max_waiting))) >= 
        data.passengers[p].demand * sum(z_mm[p, l, f, r] for f in freq_passenger_feeder(p, l, data) for r in incoming_transit_nodes(p, l, f, s, t, data)))

    return nothing
end