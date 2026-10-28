-- Requires fractional_credit_support. No production writes before release approval.
set local lock_timeout='5s';
create table public.video_jobs(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 owner_scope text not null,request_id uuid not null,
 billing_mode text not null check(billing_mode in ('platform','own_key')),
 operation text not null check(operation in ('generate','asset_review')),
 model text not null default 'seedance-2.0-mini' check(model='seedance-2.0-mini'),
 request_fingerprint text not null check(request_fingerprint~'^[a-f0-9]{64}$'),
 provider_task_id text check(provider_task_id~'^[A-Za-z0-9_-]{8,160}$'),
 status text not null default 'submitting' check(status in ('submitting','submitted','processing','submission_unknown','unknown','completed','failed')),
 billing_status text not null check(billing_status in ('reserved','settled','refunded','not_applicable')),
 resolution text check(resolution in ('480p','720p')),
 requested_duration integer not null default 0,
 reference_duration_ms integer not null default 0 check(reference_duration_ms between 0 and 15199),
 unit_credit_cost numeric(18,4) not null check(unit_credit_cost in (0,0.5,1)),
 estimated_credits numeric(18,4) not null check(estimated_credits between 0 and 31),
 reserved_credits numeric(18,4) not null default 0 check(reserved_credits between 0 and 31),
 charged_credits numeric(18,4) not null default 0 check(charged_credits between 0 and 31),
 generated_count integer not null default 0 check(generated_count in (0,1)),
 reference_metadata jsonb not null default '[]'::jsonb check(jsonb_typeof(reference_metadata)='array' and jsonb_array_length(reference_metadata)<=15),
 asset_results jsonb not null default '[]'::jsonb check(jsonb_typeof(asset_results)='array' and jsonb_array_length(asset_results)<=1),
 error_code text,
 history_prompt text not null default '',history_parameters jsonb,history_created_at timestamptz,
 created_at timestamptz not null default now(),last_checked_at timestamptz,settled_at timestamptz,
 unique(owner_scope,request_id),unique(owner_scope,provider_task_id),
 check((operation='generate' and requested_duration between 4 and 15 and resolution is not null)
   or (operation='asset_review' and requested_duration=0 and resolution is null and unit_credit_cost=0 and estimated_credits=0)),
 check((history_prompt='' and history_parameters is null and history_created_at is null)
   or(history_parameters is not null and history_created_at is not null)),
 check(history_parameters is null or (jsonb_typeof(history_parameters)='object' and
  history_parameters-array['model','prompt','duration','size','resolution','seed','generate_audio','return_last_frame','tools','nsfw_check']='{}'::jsonb))
);
create index video_jobs_owner_created_idx on public.video_jobs(owner_scope,created_at desc,id desc);
create index video_jobs_user_history_idx on public.video_jobs(user_id,history_created_at desc) where history_created_at is not null;
create index video_jobs_reconcile_idx on public.video_jobs(last_checked_at nulls first) where billing_mode='platform' and status in ('submitted','processing','unknown');
alter table public.video_jobs enable row level security;
revoke all on public.video_jobs from public,anon,authenticated;
grant select,insert,update,delete on public.video_jobs to service_role;
alter table public.credit_transactions add column video_job_id uuid references public.video_jobs(id) on delete set null;
create index credit_transactions_video_job_idx on public.credit_transactions(video_job_id) where video_job_id is not null;

create function private.begin_video_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_operation text,p_fingerprint text,p_parameters jsonb,p_references jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.video_jobs;b numeric;rate numeric:=0;cost numeric:=0;seconds integer:=0;ref_ms integer:=0;res text;r jsonb;
begin
 if p_user_id is null or p_mode is null or p_mode not in ('platform','own_key') or p_owner is null
  or (p_mode='platform' and p_owner<>'user-'||p_user_id::text)
  or (p_mode='own_key' and p_owner !~ ('^user-'||p_user_id::text||'-[a-f0-9]{64}$'))
  or p_request_id is null or p_operation is null or p_operation not in ('generate','asset_review')
  or p_fingerprint is null or p_fingerprint !~ '^[a-f0-9]{64}$'
  or p_references is null or jsonb_typeof(p_references)<>'array' or jsonb_array_length(p_references)>15
  or p_parameters is null or jsonb_typeof(p_parameters)<>'object' then
  return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
 if exists(select 1 from jsonb_array_elements(p_references) x where jsonb_typeof(x)<>'object'
  or x-array['id','kind','sha256','asset_url','role','duration_ms','width','height']<>'{}'::jsonb
  or x->>'kind' is null or x->>'kind' not in ('image','video','audio') or x->>'id' is null) then
  return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
 if p_operation='generate' then
  if p_parameters-array['model','prompt','duration','size','resolution','seed','generate_audio','return_last_frame','tools','nsfw_check']<>'{}'::jsonb
   or p_parameters->>'model' is distinct from 'seedance-2.0-mini'
   or p_parameters->>'resolution' is null or p_parameters->>'resolution' not in ('480p','720p')
   or coalesce(p_parameters->>'duration','') !~ '^(4|5|6|7|8|9|10|11|12|13|14|15)$'
   or jsonb_typeof(p_parameters->'prompt') is distinct from 'string' or char_length(p_parameters->>'prompt')>32000 then
   return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
  res:=p_parameters->>'resolution';seconds:=(p_parameters->>'duration')::integer;
  if exists(select 1 from jsonb_array_elements(p_references) x where x->>'kind' in ('video','audio')
   and coalesce(x->>'duration_ms','') !~ '^[0-9]{1,6}$') then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
  select coalesce(sum((x->>'duration_ms')::integer),0) into ref_ms from jsonb_array_elements(p_references) x where x->>'kind'='video';
  if ref_ms>15199 or (ref_ms>0 and ref_ms<=1800) then return jsonb_build_object('ok',false,'code','VIDEO_REFERENCE_DURATION');end if;
  rate:=case when res='480p' then 0.5 else 1 end;cost:=(ref_ms/1000.0+seconds)*rate;
 elsif p_parameters<>'{}'::jsonb or jsonb_array_length(p_references)<>1 then
  return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner||':'||p_request_id::text,0));
 select * into j from public.video_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if found then
  if j.request_fingerprint<>p_fingerprint or j.billing_mode<>p_mode or j.operation<>p_operation then
   return jsonb_build_object('ok',false,'code','VIDEO_REQUEST_CONFLICT');end if;
  return jsonb_build_object('ok',true,'existing',true,'job',to_jsonb(j));
 end if;
 if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then return jsonb_build_object('ok',false,'code','EMAIL_UNVERIFIED');end if;
 if not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null) then return jsonb_build_object('ok',false,'code','ACCOUNT_FROZEN');end if;
 -- Serialize the account's new intents before counting active tasks/charging.
 select balance into b from public.credit_accounts where user_id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');end if;
 if (select count(*) from public.video_jobs where user_id=p_user_id and operation=p_operation and status not in ('completed','failed'))>=3 then
  return jsonb_build_object('ok',false,'code','VIDEO_QUEUE_FULL');end if;
 if p_mode='platform' and b<cost then return jsonb_build_object('ok',false,'code','CREDITS_INSUFFICIENT','required',cost,'balance',b);end if;
 if p_mode='platform' and cost>0 then
  update public.credit_accounts set balance=balance-cost,updated_at=now() where user_id=p_user_id returning balance into b;
 end if;
 insert into public.video_jobs(user_id,owner_scope,request_id,billing_mode,operation,request_fingerprint,billing_status,
  resolution,requested_duration,reference_duration_ms,unit_credit_cost,estimated_credits,reserved_credits,reference_metadata,history_prompt,history_parameters,history_created_at)
 values(p_user_id,p_owner,p_request_id,p_mode,p_operation,p_fingerprint,case when p_mode='platform' and cost>0 then 'reserved' else 'not_applicable' end,
  res,seconds,ref_ms,rate,cost,case when p_mode='platform' then cost else 0 end,p_references,
  case when p_operation='generate' then p_parameters->>'prompt' else '' end,
  case when p_operation='generate' then p_parameters else null end,case when p_operation='generate' then now() else null end)
 returning * into j;
 if p_mode='platform' and cost>0 then
  insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
  values(p_user_id,j.id,'reserve',-cost,'video-reserve:'||j.id::text,
   jsonb_build_object('media_type','video','model',j.model,'resolution',res,'unit_credit_cost',rate,'reference_duration_ms',ref_ms,'generated_seconds',seconds));
 end if;
 return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(j),'balance',b);
end;$$;
create function public.begin_video_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_operation text,p_fingerprint text,p_parameters jsonb,p_references jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.begin_video_job(p_owner,p_user_id,p_request_id,p_mode,p_operation,p_fingerprint,p_parameters,p_references);
$$;

create function private.apply_video_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_error_code text default null,p_assets jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.video_jobs;b numeric;
begin
 select * into j from public.video_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if not found then return jsonb_build_object('ok',false,'code','VIDEO_NOT_FOUND');end if;
 if p_event is null or p_event not in ('submitted','submission_unknown','rejected','processing','unknown','completed','failed') then
  return jsonb_build_object('ok',false,'code','INVALID_VIDEO_EVENT');end if;
 if j.status in ('completed','failed') then return jsonb_build_object('ok',true,'job',to_jsonb(j));end if;
 if p_event='submitted' then
  if p_task_id is null or p_task_id !~ '^[A-Za-z0-9_-]{8,160}$' or (j.provider_task_id is not null and j.provider_task_id<>p_task_id) then
   return jsonb_build_object('ok',false,'code','VIDEO_REQUEST_CONFLICT');end if;
  update public.video_jobs set status='submitted',provider_task_id=p_task_id,last_checked_at=now() where id=j.id;
 elsif p_event='completed' then
  if j.operation='asset_review' then
   if p_assets is null or jsonb_typeof(p_assets)<>'array' or jsonb_array_length(p_assets)<>1
    or exists(select 1 from jsonb_array_elements(p_assets) a where a->>'asset_url' is null or a->>'asset_url' !~ '^asset://[A-Za-z0-9_-]{4,160}$'
     or a->>'status' is distinct from 'Active' or a-array['asset_id','asset_url','status','kind','id','duration_ms','width','height','sha256']<>'{}'::jsonb) then
    return jsonb_build_object('ok',false,'code','VIDEO_BAD_ASSET');end if;
  elsif j.billing_mode='platform' then
   update public.credit_accounts set total_spent=total_spent+j.reserved_credits,updated_at=now() where user_id=j.user_id returning balance into b;
   insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
   values(j.user_id,j.id,'spend',0,'video-spend:'||j.id::text,jsonb_build_object('media_type','video','charged_credits',j.reserved_credits,'generated_seconds',j.requested_duration,'reference_duration_ms',j.reference_duration_ms));
  end if;
  update public.video_jobs set status='completed',billing_status=case when operation='generate' and billing_mode='platform' then 'settled' else 'not_applicable' end,
   charged_credits=reserved_credits,generated_count=case when operation='generate' then 1 else 0 end,
   asset_results=case when operation='asset_review' then p_assets else '[]'::jsonb end,last_checked_at=now(),settled_at=now(),error_code=null where id=j.id;
 elsif p_event in ('failed','rejected') then
  if j.billing_mode='platform' and j.reserved_credits>0 then
   update public.credit_accounts set balance=balance+j.reserved_credits,total_refunded=total_refunded+j.reserved_credits,updated_at=now() where user_id=j.user_id returning balance into b;
   insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
   values(j.user_id,j.id,'refund',j.reserved_credits,'video-refund:'||j.id::text,jsonb_build_object('media_type','video'));
  end if;
  update public.video_jobs set status='failed',billing_status=case when reserved_credits>0 then 'refunded' else 'not_applicable' end,
   error_code=left(p_error_code,100),last_checked_at=now(),settled_at=now() where id=j.id;
 else
  update public.video_jobs set status=p_event,error_code=left(p_error_code,100),last_checked_at=now() where id=j.id;
 end if;
 select * into j from public.video_jobs where id=j.id;
 return jsonb_build_object('ok',true,'job',to_jsonb(j),'balance',b);
end;$$;
create function public.apply_video_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_error_code text default null,p_assets jsonb default '[]'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.apply_video_job(p_owner,p_request_id,p_event,p_task_id,p_error_code,p_assets);
$$;
revoke all on function private.begin_video_job(text,uuid,uuid,text,text,text,jsonb,jsonb),public.begin_video_job(text,uuid,uuid,text,text,text,jsonb,jsonb),
 private.apply_video_job(text,uuid,text,text,text,jsonb),public.apply_video_job(text,uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.begin_video_job(text,uuid,uuid,text,text,text,jsonb,jsonb),public.begin_video_job(text,uuid,uuid,text,text,text,jsonb,jsonb),
 private.apply_video_job(text,uuid,text,text,text,jsonb),public.apply_video_job(text,uuid,text,text,text,jsonb) to service_role;

-- Seven-day text only; media URLs and receipts never enter history.
create or replace function public.get_prompt_history(p_user_id uuid,p_cutoff timestamptz,p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 51)
returns table(id uuid,prompt text,created_at timestamptz,kind text,parameters jsonb)
language sql security invoker set search_path='' as $$
 select h.id,h.prompt,h.created_at,h.kind,h.parameters from (
   select g.id,g.prompt,g.created_at,'image'::text as kind,null::jsonb as parameters
    from public.generation_jobs g where g.user_id=p_user_id and g.prompt<>''
     and g.created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
   union all
   select m.id,m.history_prompt,m.history_created_at,'music'::text,m.history_parameters
    from public.music_jobs m where m.user_id=p_user_id and m.history_prompt<>''
     and m.history_created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
   union all
   select v.id,coalesce(nullif(v.history_prompt,''),'参考素材创作'),v.history_created_at,'video'::text,v.history_parameters
    from public.video_jobs v where v.user_id=p_user_id and v.history_created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
 ) h
 where p_before is null or (h.created_at,h.id)<(p_before,p_before_id)
 order by h.created_at desc,h.id desc limit least(greatest(p_limit,1),51);
$$;

create or replace function private.prune_prompt_text(p_dry_run boolean default true)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_cutoff timestamptz:=statement_timestamp()-interval '7 days';v_images integer;v_music integer;v_video integer;
begin
 if p_dry_run is null then raise exception 'Explicit cleanup mode required';end if;
 if p_dry_run then
  select count(*) into v_images from public.generation_jobs where created_at<=v_cutoff and prompt<>'';
  select count(*) into v_music from public.music_jobs where history_created_at<=v_cutoff;
  select count(*) into v_video from public.video_jobs where history_created_at<=v_cutoff;
  return jsonb_build_object('video_eligible',v_video,'dry_run',true,'eligible',v_images+v_music+v_video,'music_eligible',v_music,'cutoff',v_cutoff);
 end if;
 with expired as(select id from public.generation_jobs where created_at<=v_cutoff and prompt<>'' order by created_at,id limit 5000 for update skip locked)
  update public.generation_jobs g set prompt='' from expired where g.id=expired.id;
 get diagnostics v_images=row_count;
 with expired as(select id from public.music_jobs where history_created_at<=v_cutoff order by history_created_at,id limit 5000 for update skip locked)
  update public.music_jobs m set history_prompt='',history_parameters=null,history_created_at=null from expired where m.id=expired.id;
 get diagnostics v_music=row_count;
 with expired as(select id from public.video_jobs where history_created_at<=v_cutoff order by history_created_at,id limit 5000 for update skip locked)
  update public.video_jobs v set history_prompt='',history_parameters=null,history_created_at=null from expired where v.id=expired.id;
 get diagnostics v_video=row_count;
 return jsonb_build_object('video_cleared',v_video,'cleared',v_images+v_music+v_video,'music_cleared',v_music,'cutoff',v_cutoff,'max_rows_per_run',15000);
end;
$$;


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
    'credits',coalesce(sum(v.charged_credits),0),'pending',count(*) filter(where v.status not in ('completed','failed')))
    from public.video_jobs v,bounds b where v.operation='generate' and v.created_at>=b.start_at and v.created_at<b.end_at),
  'video_jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc,j.id desc) from (
    select v.id,v.request_id,v.user_id,p.username,a.email,v.billing_mode,v.model,v.status,v.billing_status,v.resolution,
      v.requested_duration,v.reference_duration_ms,v.generated_count,v.reserved_credits,v.charged_credits,v.error_code,v.created_at
    from public.video_jobs v left join public.profiles p on p.id=v.user_id left join auth.users a on a.id=v.user_id,bounds b
    where v.operation='generate' and v.created_at>=b.start_at and v.created_at<b.end_at
      and (coalesce(p_search,'')='' or p.username ilike '%'||left(p_search,160)||'%' or a.email ilike '%'||left(p_search,160)||'%')
    order by v.created_at desc,v.id desc limit least(greatest(p_limit,1),100)
  ) j),'[]'::jsonb),
  'timezone','Asia/Shanghai'
);
$$;
revoke all on function private.get_admin_music_overview(date,date,text,integer) from public,anon,authenticated;
grant execute on function private.get_admin_music_overview(date,date,text,integer) to service_role;


create or replace function private.prune_video_references(p_dry_run boolean default true)
returns jsonb
language plpgsql security invoker set search_path = ''
as $$
declare
    v_started timestamptz := pg_catalog.clock_timestamp();
    v_cutoff timestamptz := pg_catalog.statement_timestamp() - interval '12 hours';
    v_config jsonb;
    v_bucket text;
    v_key text;
    v_url text;
    v_headers extensions.http_header[];
    v_response extensions.http_response;
    v_paths text[];
    v_batch_bytes bigint;
    v_deleted integer := 0;
    v_deleted_bytes bigint := 0;
    v_candidates integer;
    v_candidate_bytes bigint;
    v_iteration integer;
begin
    if p_dry_run is null then
        raise exception 'Explicit cleanup mode required';
    end if;
    if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('posterflow.video_reference_retention.run')) then
        return pg_catalog.jsonb_build_object('skipped', true, 'reason', 'already_running');
    end if;
    select decrypted_secret::jsonb into v_config
      from vault.decrypted_secrets where name = 'posterflow_image_retention';
    if v_config is null then
        raise exception 'Image retention Vault configuration is missing';
    end if;
    v_bucket := v_config->>'bucket';
    v_key := v_config->>'storage_key';
    v_url := v_config->>'project_url';
    if v_url is null or v_url !~ '^https://[a-z0-9]+[.]supabase[.]co$'
       or v_bucket is null or v_bucket !~ '^[a-z0-9][a-z0-9_-]{0,62}$'
       or v_key is null or length(v_key) < 30 then
        raise exception 'Invalid image retention Vault configuration';
    end if;

    select count(*), coalesce(sum(coalesce((metadata->>'size')::bigint,0)),0)
      into v_candidates, v_candidate_bytes
      from storage.objects
     where bucket_id = v_bucket and created_at < v_cutoff
       and name ~ '^posterflow/video-[a-f0-9]{64}/references/[0-9]{10}-[a-f0-9]{32}[.](png|jpe?g|webp|mp3|wav|mp4|mov)$'
       and archived_at is null and not coalesce(is_delete_marker,false);
    if p_dry_run then
        return pg_catalog.jsonb_build_object('dry_run',true,'cutoff',v_cutoff,
            'eligible_objects',v_candidates,'eligible_bytes',v_candidate_bytes,'max_objects_per_run',1000);
    end if;

    v_headers := array[extensions.http_header('apikey',v_key)];
    if v_key not like 'sb_secret_%' then
        v_headers := pg_catalog.array_append(v_headers,extensions.http_header('Authorization','Bearer ' || v_key));
    end if;
    -- Bound network waits and total work. Never disable certificate validation
    -- or follow redirects with credentials to another host.
    perform pg_catalog.set_config('http.curlopt_timeout_ms','15000',true);
    perform pg_catalog.set_config('http.curlopt_connecttimeout_ms','5000',true);
    for v_iteration in 1..10 loop
        select array_agg(candidate.name order by candidate.created_at,candidate.name),
               coalesce(sum(candidate.bytes),0)
          into v_paths, v_batch_bytes
          from (
              select name, created_at, coalesce((metadata->>'size')::bigint,0) as bytes
                from storage.objects
               where bucket_id = v_bucket and created_at < v_cutoff
                 and name ~ '^posterflow/video-[a-f0-9]{64}/references/[0-9]{10}-[a-f0-9]{32}[.](png|jpe?g|webp|mp3|wav|mp4|mov)$'
                 and archived_at is null and not coalesce(is_delete_marker,false)
               order by created_at,name limit 100
          ) candidate;
        exit when v_paths is null;
        select * into v_response from extensions.http((
            'DELETE', v_url || '/storage/v1/object/' || v_bucket, v_headers,
            'application/json', pg_catalog.jsonb_build_object('prefixes',v_paths)::text
        )::extensions.http_request);
        if v_response.status < 200 or v_response.status >= 300 then
            -- Do not include response bodies, paths or credentials in errors.
            raise exception 'Storage cleanup request failed (HTTP %)', v_response.status;
        end if;
        if exists(select 1 from storage.objects where bucket_id=v_bucket and name=any(v_paths)
                  and archived_at is null and not coalesce(is_delete_marker,false)) then
            raise exception 'Storage cleanup could not verify the completed batch';
        end if;
        v_deleted := v_deleted + cardinality(v_paths);
        v_deleted_bytes := v_deleted_bytes + v_batch_bytes;
    end loop;

    return pg_catalog.jsonb_build_object('dry_run',false,'cutoff',v_cutoff,
        'deleted_objects',v_deleted,'deleted_bytes',v_deleted_bytes,
        'eligible_at_start',v_candidates,'remaining_from_start',greatest(v_candidates-v_deleted,0));
end;
$$;
revoke all on function private.prune_video_references(boolean) from public, anon, authenticated, service_role;



select cron.schedule('posterflow-video-reference-retention-12h','47 * * * *','select private.prune_video_references(false);');
