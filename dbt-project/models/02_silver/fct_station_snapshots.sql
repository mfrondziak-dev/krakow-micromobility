{{ config(location='data/silver/fct_station_snapshots') }}

-- Station availability at each poll, with fleet composition summed
-- directly from the vehicle_types_available structs.

select
    station_id,
    reported_at_local as measured_at,
    dt,
    is_installed,
    is_renting,
    is_returning,
    num_bikes_available,
    coalesce(
        list_sum(
            list_transform(vehicle_types_available, v -> v.count)
        ),
        0
    ) as vehicles_parked
from {{ ref('bronze_station_status') }}
