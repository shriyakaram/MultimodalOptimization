"""
    Create vehicle and zone variables
"""
function add_vehicle_zone_variables!(transit_times::Vector{Float64}, ondemand_times::Vector{Float64}, model::Model, data::OnDemandTransitData)

    zones = zone_id_list(data)

    #number of transit vehicles
    @variable(model, veh_tr >= 0, Int)

    #number of transit vehicles at each time step
    @variable(model, veh_tr_time[t in transit_times] >= 0, Int)

    #number of od vehicles per zone
    @variable(model, veh_od_zone[i = zones] >= 0, Int)
    @variable(model, veh_od_zone_time[t = ondemand_times, i = zones] >= 0, Int)

    #number of multimodal vehicles per zone
    @variable(model, veh_mm_zone[i = zones] >= 0, Int)
    @variable(model, veh_mm_zone_time[t = ondemand_times, i = zones] >= 0, Int)

    #mode assignment
    @variable(model, m[i = data.zone_pairs, k = 1:3], Bin)

    return veh_tr, veh_tr_time, veh_od_zone, veh_od_zone_time, veh_mm_zone, veh_mm_zone_time, m
end

"""
    Create transit variables
"""
function add_transit_variables!(model::Model, data::OnDemandTransitData)

    lines, frequencies = line_frequency_pairs(data.line_frequencies)

    #select lines l and frequencies f
    @variable(model, x[l = lines, f = frequencies], Bin)
    
    #assign passengers p to transit routes for each line l and frequency f 
    @variable(model, z_tr[p = eachindex(data.passengers), l = lines_passenger(p, data), f = freq_passenger(p, l, data), 
        r = routes_passenger(p, l, f, data)], Bin)
        
    #assign passengers p to transit routes for each line l and frequency f (multimodal)
    @variable(model, z_mm[p = eachindex(data.passengers), l = lines_passenger_feeder(p, data), f = freq_passenger_feeder(p, l, data), 
        r = routes_passenger_feeder(p, l, f, data)], Bin)

    return x, z_tr, z_mm
end

"""
    Create on-demand variables
"""
function add_ondemand_variables!(model::Model, data::OnDemandTransitData)

    #number of od routes g selected
    @variable(model, y_od[g = eachindex(data.OnD_routes)] >= 0, Int)
    
    #number of pick-up routes g selected
    @variable(model, y_pickup[g = eachindex(data.pickup_routes)] >= 0, Int)

    #number of drop-off routes g selected
    @variable(model, y_dropoff[g = eachindex(data.dropoff_routes)] >= 0, Int)

    return y_od, y_pickup, y_dropoff
end


