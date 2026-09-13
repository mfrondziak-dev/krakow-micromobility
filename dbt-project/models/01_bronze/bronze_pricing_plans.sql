{{ config(location='data/bronze/bronze_pricing_plans') }}

-- Real pricing plans published by the operator (static feed, refreshed daily).

with source as (

    select
        unnest(data.plans) as plan,
        filename
    from read_json_auto(
        'data/raw/gbfs/static/*/system_pricing_plans_*.json',
        filename = true,
        union_by_name = true
    )

)

select
    plan.plan_id,
    plan.name as plan_name,
    plan.currency,
    plan.price as unlock_price,
    plan.per_min_pricing as per_min_pricing,
    plan.description
from source
qualify row_number() over (partition by plan.plan_id order by filename desc) = 1
