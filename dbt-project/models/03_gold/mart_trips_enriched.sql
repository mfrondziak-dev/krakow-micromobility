-- Trips enriched with the operator's real pricing plan (unlock + per-minute
-- rate), straight from the GBFS system_pricing_plans feed.
--
-- GBFS per_min_pricing is a schedule of tiers: {start, interval, rate} means
-- "rate is charged for each interval of minutes, beginning at minute start".
-- Tiers can chain (e.g. 0.99/min for the first 20 min, then 0.49/min after),
-- so the fare is computed by evaluating each tier over the slice of the trip
-- duration it covers.

with trips as (

    select * from {{ ref('fct_vehicle_trips') }}

),

vehicle_plans as (

    select distinct
        vehicle_id,
        measured_at,
        pricing_plan_id
    from {{ ref('fct_vehicle_snapshots') }}

),

trip_plan as (

    select
        t.*,
        vp.pricing_plan_id
    from trips t
    left join vehicle_plans vp
        on vp.vehicle_id = t.vehicle_id
       and vp.measured_at = t.departed_at

),

tiers as (

    select
        plan_id,
        unlock_price,
        tier.start as tier_start,
        tier.interval as tier_interval,
        tier.rate as tier_rate,
        -- end of this tier = start of the next one (exclusive upper bound)
        lead(tier.start) over (
            partition by plan_id order by tier.start
        ) as tier_end
    from (
        select plan_id, unlock_price, unnest(per_min_pricing) as tier
        from {{ ref('bronze_pricing_plans') }}
    )

),

trip_fare as (

    select
        tp.vehicle_id,
        tp.departed_at,
        any_value(ti.unlock_price) as unlock_price,
        sum(
            case
                when tp.duration_min > ti.tier_start
                then ceil(
                        (least(tp.duration_min, coalesce(ti.tier_end - 1, tp.duration_min))
                         - ti.tier_start + 1)::double
                        / greatest(ti.tier_interval, 1)
                     ) * ti.tier_rate
                else 0.0
            end
        ) as fare
    from trip_plan tp
    join tiers ti on ti.plan_id = tp.pricing_plan_id
    group by tp.vehicle_id, tp.departed_at

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
    coalesce(f.unlock_price, 0.0) + coalesce(f.fare, 0.0) as fare_pln
from trip_plan t
left join trip_fare f
    on f.vehicle_id = t.vehicle_id
   and f.departed_at = t.departed_at
