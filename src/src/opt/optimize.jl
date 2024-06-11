"""
    Constructs an OnDemandTransitModel object
"""
function run_opt(num_transit_lines::Int, pp::PermanentParameters, F::Int, extra_veh_od::Int, extra_veh_mm::Int)

    max_waiting = pp.max_waiting
    transit_time_step = pp.transit_time_step
    on_demand_time_step = pp.on_demand_time_step
    ondemand_times = collect(0:on_demand_time_step:pp.time_horizon)
    transit_times = collect(0:transit_time_step:pp.time_horizon)

    #run(`python3 data_files/generate$num_transit_lines.py`)
    transit_file = "data_files/transit_stops$num_transit_lines.csv"
    on_demand_file = "data_files/ond_locations$num_transit_lines.csv"

    #run model
    t = time()
    data = OnDemandTransit.load_data(transit_file, on_demand_file, pp)

    @printf("%.2f pre-processing seconds\n", time() - t)
    t = time()
    model = Model(Gurobi.Optimizer)
    veh_tr, veh_tr_time, veh_od_zone, veh_od_zone_time, veh_mm_zone, 
        veh_mm_zone_time, m = OnDemandTransit.add_vehicle_zone_variables!(transit_times, ondemand_times, model, data)
    x, z_tr, z_mm = OnDemandTransit.add_transit_variables!(model, data)
    y_od, y_pickup, y_dropoff = OnDemandTransit.add_ondemand_variables!(model, data)
    @printf("%.2f variables seconds\n", time() - t)
    t = time()
    OnDemandTransit.add_objective(model, data)
    @printf("%.2f objective seconds\n", time() - t)
    t = time()
    OnDemandTransit.add_fleet_assignment_constraints!(model, data, F)
    OnDemandTransit.add_transit_vehicle_constraints!(transit_times, transit_time_step, model, data)
    OnDemandTransit.add_ondemand_vehicle_constraints!(ondemand_times, on_demand_time_step, extra_veh_od, extra_veh_mm, model, data)
    @printf("%.2f vehicle constraints seconds\n", time() - t)
    OnDemandTransit.add_mode_assignment_constraints!(model, data)
    t = time()
    OnDemandTransit.add_transit_passenger_constraints!(model, data)
    @printf("%.2f transit passenger constraints seconds\n", time() - t)
    t = time()
    OnDemandTransit.add_od_passenger_constraints!(model, data)
    @printf("%.2f on-demand passenger constraints seconds\n", time() - t)
    t = time()
    OnDemandTransit.add_multimodal_passenger_constraints!(max_waiting, transit_times, model, data)
    @printf("%.2f multimodal passenger constraints seconds\n", time() - t)
    t = time()
    optimize!(model)
    @printf("%.2f solution seconds\n", time() - t)
    return OnDemandTransitModel(model, data, pp, F)
end
