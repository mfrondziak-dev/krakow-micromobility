{{ config(location='data/gold/mart_station_utilization_hourly') }}

-- Hourly station utilization: average availability, idle time and service
-- status. Stations reporting is_renting = false are excluded from supply.

select
    station_id,
    date_trunc('hour', measured_at) as hour,
    count(*) as polls,
    avg(num_bikes_available) as avg_bikes_available,
    min(num_bikes_available) as min_bikes_available,
    max(num_bikes_available) as max_bikes_available,
    avg(case when num_bikes_available = 0 then 1.0 else 0.0 end) as empty_share,
    avg(case when is_renting then 1.0 else 0.0 end) as renting_share
from {{ ref('fct_station_snapshots') }}
group by 1, 2
