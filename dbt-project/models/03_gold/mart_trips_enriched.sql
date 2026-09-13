{{ config(location='data/gold/mart_trips_enriched') }}

-- Trips enriched with the operator's real pricing plan (unlock + per-minute
-- rate), straight from the GBFS system_pricing_plans feed.

with trips as (

    select * from {{ ref('fct_vehicle_trips') }}

),

plans as (

    select
        plan_id,
        unlock_price,
        unnest(per_min_pricing) as tier
    from {{ ref('bronze_pricing_plans') }}

),

fare as (

    select
        plan_id,
        any_value(unlock_price) as unlock_price,
        sum(
            -- charge for each full interval covered by the trip duration
            greatest(
                ceil(
                    (60 - coalesce(tier.start, 1)) / greatest(tier.interval, 1)
                ) * tier.rate,
                0
            )
        ) as per_minute_rate
    from plans
    group by plan_id

)

select
    t.vehicle_id,
    t.start_lat,
    t.start_lon,
    t.end_lat,
    t.end_lon,
    t.departed_at,
    t.arrived_at,
    t.duration_min,
    t.distance_m,
    t.distance_m / 1000.0 / nullif(t.duration_min / 60.0, 0) as speed_kmh,
    f.unlock_price + t.duration_min * f.per_minute_rate as fare_pln
from trips t
left join {{ ref('fct_vehicle_snapshots') }} vs
    on vs.vehicle_id = t.vehicle_id
   and vs.measured_at = t.departed_at
left join fare f
    on f.plan_id = vs.pricing_plan_id
