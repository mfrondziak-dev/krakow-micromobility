{{ config(location='data/gold/mart_fleet_health_hourly') }}

-- Fleet health: battery state, range and availability of the dockless fleet.

select
    date_trunc('hour', measured_at) as hour,
    vehicle_type_id,
    count(*) as observations,
    count(distinct vehicle_id) as distinct_vehicles,
    avg(current_fuel_percent) as avg_battery_pct,
    min(current_fuel_percent) as min_battery_pct,
    avg(case when current_fuel_percent < 0.2 then 1.0 else 0.0 end) as low_battery_share,
    avg(current_range_meters) as avg_range_m,
    avg(case when is_disabled then 1.0 else 0.0 end) as disabled_share,
    avg(case when is_reserved then 1.0 else 0.0 end) as reserved_share
from {{ ref('fct_vehicle_snapshots') }}
group by 1, 2
