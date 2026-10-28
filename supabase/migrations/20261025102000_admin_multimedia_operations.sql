-- Read-only administrator summaries; no user, task or ledger rows are changed.
-- Keep the existing public service-only wrapper and fixed private search_path.
create or replace function private.get_admin_music_overview(p_from date,p_to date,p_search text default '',p_limit integer default 100)
returns jsonb language sql security definer set search_path = '' as $$
with bounds as (
  select p_from::timestamp at time zone 'Asia/Shanghai' as start_at,
    (p_to+1)::timestamp at time zone 'Asia/Shanghai' as end_at,
    date_trunc('day',now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai' as today_at,
    date_trunc('month',now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai' as month_at
), music as (
  select j.* from public.music_jobs j,bounds b where j.created_at>=b.start_at and j.created_at<b.end_at
), activity as (
  select g.user_id,g.created_at,'image'::text as kind from public.generation_jobs g,bounds b
    where g.user_id is not null and g.created_at>=least(b.start_at,b.month_at) and g.created_at<greatest(b.end_at,b.today_at+interval '1 day')
  union all
  select m.user_id,m.created_at,'music'::text from public.music_jobs m,bounds b
    where m.user_id is not null and m.created_at>=least(b.start_at,b.month_at) and m.created_at<greatest(b.end_at,b.today_at+interval '1 day')
  union all
  select v.user_id,v.created_at,'video'::text from public.video_jobs v,bounds b
    where v.operation='generate' and v.created_at>=least(b.start_at,b.month_at) and v.created_at<greatest(b.end_at,b.today_at+interval '1 day')
), active_days as (
  select (a.created_at at time zone 'Asia/Shanghai')::date as stat_date,
    count(distinct a.user_id) as active_users,
    count(distinct a.user_id) filter(where a.kind='image') as image_active_users,
    count(distinct a.user_id) filter(where a.kind='music') as music_active_users,
    count(distinct a.user_id) filter(where a.kind='video') as video_active_users
  from activity a group by 1
), days as (
  select d::date as stat_date,coalesce(a.active_users,0) as active_users,
    coalesce(a.image_active_users,0) as image_active_users,coalesce(a.music_active_users,0) as music_active_users,coalesce(a.video_active_users,0) as video_active_users
  from generate_series(p_from::timestamp,p_to::timestamp,interval '1 day') d
  left join active_days a on a.stat_date=d::date
), models as (
  select model,count(*) as requests,coalesce(sum(generated_count),0) as tracks,
    coalesce(sum(charged_credits),0) as credits from music group by model order by count(*) desc,model limit 12
), jobs as (
  select m.request_id,m.user_id,p.username,a.email,m.model,m.version,m.status,m.billing_mode,
    m.operation,m.reference_count,m.billing_unit,m.billing_status,m.generated_count,m.charged_credits,m.reserved_credits,m.error_code,m.created_at
  from music m left join public.profiles p on p.id=m.user_id left join auth.users a on a.id=m.user_id
  where coalesce(p_search,'')='' or p.username ilike '%'||left(p_search,160)||'%' or a.email ilike '%'||left(p_search,160)||'%'
  order by m.created_at desc,m.id desc limit least(greatest(p_limit,1),100)
)
select jsonb_build_object(
  'metrics',jsonb_build_object(
    'requests',(select count(*) from music),
    'completed_requests',(select count(*) from music where status='completed'),
    'failed',(select count(*) from music where status='failed'),
    'unknown',(select count(*) from music where status in ('unknown','submission_unknown')),
    'awaiting_balance',(select count(*) from music where billing_status='awaiting_balance'),
    'tracks',(select coalesce(sum(generated_count),0) from music),
    'credits',(select coalesce(sum(charged_credits),0) from music),
    'pending',(select count(*) from music where status not in ('completed','failed') or billing_status='awaiting_balance'),
    'reserved',(select coalesce(sum(reserved_credits),0) from music where billing_status in ('reserved','awaiting_balance')),
    'success_rate',(select coalesce(round(100.0*count(*) filter(where status='completed')/nullif(count(*) filter(where status in ('completed','failed')),0),1),0) from music)),
  'activity',jsonb_build_object(
    'daily_active_users',(select count(distinct a.user_id) from activity a,bounds b where a.created_at>=b.today_at and a.created_at<b.today_at+interval '1 day'),
    'monthly_active_users',(select count(distinct a.user_id) from activity a,bounds b where a.created_at>=b.month_at and a.created_at<b.today_at+interval '1 day')),
  'days',coalesce((select jsonb_agg(to_jsonb(d) order by d.stat_date) from days d),'[]'::jsonb),
  'models',coalesce((select jsonb_agg(to_jsonb(m) order by m.requests desc,m.model) from models m),'[]'::jsonb),
  'jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc,j.request_id desc) from jobs j),'[]'::jsonb),
  'image_jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc,j.id desc) from (
    select g.id,g.request_id,g.user_id,p.username,a.email,g.billing_mode,g.model,g.status,
      g.requested_count,g.generated_count,g.reserved_credits,g.charged_credits,g.error_code,g.created_at
    from public.generation_jobs g left join public.profiles p on p.id=g.user_id left join auth.users a on a.id=g.user_id,bounds b
    where g.created_at>=b.start_at and g.created_at<b.end_at
      and (coalesce(p_search,'')='' or p.username ilike '%'||left(p_search,160)||'%' or a.email ilike '%'||left(p_search,160)||'%')
    order by g.created_at desc,g.id desc limit least(greatest(p_limit,1),100)
  ) j),'[]'::jsonb),
  'video_metrics',(select jsonb_build_object('requests',count(*),'completed',count(*) filter(where v.status='completed'),
    'failed',count(*) filter(where v.status='failed'),
    'credits',coalesce(sum(v.charged_credits),0),
    'reserved',coalesce(sum(v.reserved_credits) filter(where v.billing_status in ('reserved','awaiting_balance','awaiting_provider')),0),
    'pending',count(*) filter(where v.status not in ('completed','failed') or v.billing_status in ('awaiting_balance','awaiting_provider')),
    'unknown',count(*) filter(where v.status in ('unknown','submission_unknown')),
    'awaiting_balance',count(*) filter(where v.billing_status='awaiting_balance'),
    'awaiting_provider',count(*) filter(where v.billing_status='awaiting_provider'),
    'success_rate',coalesce(round(100.0*count(*) filter(where v.status='completed')/nullif(count(*) filter(where v.status in ('completed','failed')),0),1),0))
    from public.video_jobs v,bounds b where v.operation='generate' and v.created_at>=b.start_at and v.created_at<b.end_at),
  'video_jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc,j.id desc) from (
    select v.id,v.request_id,v.user_id,p.username,a.email,v.billing_mode,v.model,v.status,v.billing_status,v.resolution,
      v.requested_duration,v.reference_duration_ms,v.is_draft,(v.draft_source_id is not null) as is_final,
      case when v.model='seedance-2.5' then 'actual_cost' else 'second' end as billing_unit,
      v.provider_cost_usd,v.completion_tokens,v.generated_count,v.reserved_credits,v.charged_credits,v.error_code,v.created_at
    from public.video_jobs v left join public.profiles p on p.id=v.user_id left join auth.users a on a.id=v.user_id,bounds b
    where v.operation='generate' and v.created_at>=b.start_at and v.created_at<b.end_at
      and (coalesce(p_search,'')='' or p.username ilike '%'||left(p_search,160)||'%' or a.email ilike '%'||left(p_search,160)||'%')
    order by v.created_at desc,v.id desc limit least(greatest(p_limit,1),100)
  ) j),'[]'::jsonb),
  'video_models',coalesce((select jsonb_agg(to_jsonb(m) order by m.requests desc,m.model) from (
    select v.model,count(*) as requests,coalesce(sum(v.generated_count),0) as clips,
      coalesce(sum(v.charged_credits),0) as credits
    from public.video_jobs v,bounds b where v.operation='generate' and v.created_at>=b.start_at and v.created_at<b.end_at group by v.model
  ) m),'[]'::jsonb),
  'failure_counts',coalesce((select jsonb_agg(to_jsonb(f) order by f.count desc,f.kind,f.error_code) from (
    select kind,error_code,count(*) as count from (
      select 'image'::text as kind,g.error_code from public.generation_jobs g,bounds b
        where g.created_at>=b.start_at and g.created_at<b.end_at and g.status in ('failed','refunded')
      union all select 'music',m.error_code from music m where m.status='failed'
      union all select 'video',v.error_code from public.video_jobs v,bounds b
        where v.operation='generate' and v.created_at>=b.start_at and v.created_at<b.end_at and v.status='failed'
    ) failures group by kind,error_code order by count(*) desc,kind,error_code limit 32
  ) f),'[]'::jsonb),
  'overview_version',2,
  'timezone','Asia/Shanghai'
);
$$;
revoke all on function private.get_admin_music_overview(date,date,text,integer) from public,anon,authenticated;
grant execute on function private.get_admin_music_overview(date,date,text,integer) to service_role;
