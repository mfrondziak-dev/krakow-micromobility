{{ config(location='data/silver/fct_vehicle_snapshots') }}

-- Vehicle telemetry at each poll: position, battery, availability.

select
    vehicle_id,
    vehicle_type_id,
    pricing_plan_id,
    reported_at_local as measured_at,
    dt,
    lat,
    lon,
    current_range_meters,
    current_fuel_percent,
    is_disabled,
    is_reserved
from {{ ref('bronze_vehicle_status') }}
