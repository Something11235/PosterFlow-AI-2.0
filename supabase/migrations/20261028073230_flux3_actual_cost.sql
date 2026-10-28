-- Local pending: FLUX 3 Video generation only; preserve existing jobs and accounting.
set local lock_timeout='5s';
alter table public.video_jobs
 drop constraint video_jobs_model_check,
 drop constraint video_jobs_resolution_check,
 drop constraint video_jobs_generation_shape,
 drop constraint video_jobs_history_fields,
 add constraint video_jobs_model_check check(model in ('seedance-2.0-mini','seedance-2.0','seedance-2.0-fast','seedance-2.5','gemini-omni-1.1-flash','MiniMax-H3','MiniMax-H3-Max','wan3.0-video','flux-3-video')),
 add constraint video_jobs_resolution_check check(resolution in ('360p','480p','720p','1080p','4k','768p','2k','hd','fhd')),
 add constraint video_jobs_generation_shape check(
  (operation='generate' and resolution is not null and
    ((model in ('seedance-2.0-mini','seedance-2.0-fast') and requested_duration between 4 and 15 and resolution in ('480p','720p'))
     or(model='seedance-2.0' and requested_duration between 4 and 15 and resolution in ('480p','720p','1080p','4k'))
     or(model='seedance-2.5' and resolution in ('480p','720p','1080p') and (requested_duration=-1 or requested_duration between 4 and 30))
     or(model='MiniMax-H3' and requested_duration between 4 and 15 and resolution in ('768p','2k','hd','fhd'))
     or(model='flux-3-video' and requested_duration between 5 and 20 and resolution in ('hd','fhd'))
     or(model='wan3.0-video' and (requested_duration=-1 or requested_duration between 2 and 30) and resolution in ('480p','720p','1080p'))
     or(model='MiniMax-H3-Max' and requested_duration between 5 and 15 and resolution in ('480p','768p','1080p'))
     or(model='gemini-omni-1.1-flash' and requested_duration=-1 and resolution in ('360p','720p','1080p','4k'))))
  or(operation='asset_review' and model not in ('gemini-omni-1.1-flash','MiniMax-H3','MiniMax-H3-Max','wan3.0-video','flux-3-video') and requested_duration=0 and resolution is null and unit_credit_cost=0 and estimated_credits=0)),
 add constraint video_jobs_history_fields check(history_parameters is null or (jsonb_typeof(history_parameters)='object' and
   history_parameters-array['model','prompt','duration','size','resolution','seed','generate_audio','return_last_frame','tools','nsfw_check',
     'draft','draft_request_id','output_format','watermark','omni_reference_task_type','aspect_ratio','task','continue_request_id','audio','safety_tolerance']='{}'::jsonb));



create function private.flux3_charge(p_usd numeric) returns numeric
language sql immutable security invoker set search_path='' as $$select ceil(p_usd*7/0.38*1.2*2)/2;$$;
create function private.begin_flux3_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_operation text,p_fingerprint text,p_parameters jsonb,p_references jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.video_jobs;s public.video_jobs;b numeric;res text;seconds integer;ref_ms integer:=0;usd numeric;estimate numeric;reserve numeric;
 final boolean;draft boolean:=false;continuation boolean:=false;source_id uuid;prompt text;
 profile jsonb:='{"version":"flux3-usd7-cny038-markup20-half-v1","usd_cny":"7","credit_cny":"0.38","markup":"1.2"}';
begin
 if p_user_id is null or p_request_id is null or p_mode is null or p_mode not in ('platform','own_key')
  or p_owner is null or(p_mode='platform' and p_owner<>'user-'||p_user_id::text)
  or(p_mode='own_key' and p_owner !~ ('^user-'||p_user_id::text||'-[a-f0-9]{64}$'))
  or p_operation is distinct from 'generate' or coalesce(p_fingerprint,'') !~ '^[a-f0-9]{64}$'
  or jsonb_typeof(p_parameters) is distinct from 'object' or p_parameters->>'model' is distinct from 'flux-3-video'
  or jsonb_typeof(p_references) is distinct from 'array' then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
 res:=p_parameters->>'resolution';final:=p_parameters?'draft_request_id';
 if res is null or res not in ('hd','fhd') then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner||':'||p_request_id::text,0));
 select * into j from public.video_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if found then
  if j.model<>'flux-3-video' or j.operation<>p_operation or j.request_fingerprint<>p_fingerprint then return jsonb_build_object('ok',false,'code','VIDEO_REQUEST_CONFLICT');end if;
  return jsonb_build_object('ok',true,'existing',true,'job',to_jsonb(j));end if;
 if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then return jsonb_build_object('ok',false,'code','EMAIL_UNVERIFIED');end if;
 if not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null) then return jsonb_build_object('ok',false,'code','ACCOUNT_FROZEN');end if;
 if final then
  if p_parameters-array['model','resolution','draft_request_id']<>'{}'::jsonb or jsonb_typeof(p_parameters->'draft_request_id') is distinct from 'string'
   or coalesce(p_parameters->>'draft_request_id','') !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
   or jsonb_array_length(p_references)<>0 then return jsonb_build_object('ok',false,'code','VIDEO_DRAFT_INVALID');end if;
  select * into s from public.video_jobs where owner_scope=p_owner and user_id=p_user_id and request_id=(p_parameters->>'draft_request_id')::uuid
   and model='flux-3-video' and is_draft and status='completed' and billing_status in ('settled','not_applicable') and provider_task_id ~ '^task_[A-Za-z0-9_-]+$';
  if not found then return jsonb_build_object('ok',false,'code','VIDEO_DRAFT_INVALID');end if;
  seconds:=s.requested_duration;source_id:=s.id;prompt:=s.history_prompt;continuation:=coalesce((s.pricing_profile->>'continuation')::boolean,false);
 else
  if p_parameters-array['model','prompt','duration','resolution','aspect_ratio','audio','draft','safety_tolerance','nsfw_check']<>'{}'::jsonb
   or jsonb_typeof(p_parameters->'prompt') is distinct from 'string' or btrim(p_parameters->>'prompt')='' or char_length(p_parameters->>'prompt')>32000
   or jsonb_typeof(p_parameters->'duration') is distinct from 'number' or coalesce(p_parameters->>'duration','') !~ '^[0-9]{1,2}$'
   or coalesce(p_parameters->>'aspect_ratio','') not in ('auto','21:9','2:1','16:9','4:3','1:1','3:4','9:16')
   or jsonb_typeof(p_parameters->'audio') is distinct from 'boolean' or jsonb_typeof(p_parameters->'draft') is distinct from 'boolean'
   or jsonb_typeof(p_parameters->'nsfw_check') is distinct from 'boolean' or jsonb_typeof(p_parameters->'safety_tolerance') is distinct from 'number'
   or coalesce(p_parameters->>'safety_tolerance','') !~ '^[0-4]$' then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
  seconds:=(p_parameters->>'duration')::integer;draft:=(p_parameters->>'draft')::boolean;prompt:=p_parameters->>'prompt';
  if seconds not between 5 and 20 or(draft and res<>'hd') then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
  if jsonb_array_length(p_references)>10 or exists(select 1 from jsonb_array_elements(p_references) r where jsonb_typeof(r)<>'object'
   or r-array['id','kind','sha256','width','height','size','duration_ms','fps','codec']<>'{}'::jsonb
   or jsonb_typeof(r->'id') is distinct from 'string' or coalesce(r->>'id','')=''
   or coalesce(r->>'kind','') not in ('image','video')
   or jsonb_typeof(r->'size') is distinct from 'number' or coalesce(r->>'size','') !~ '^[0-9]{1,9}$'
   or jsonb_typeof(r->'width') is distinct from 'number' or coalesce(r->>'width','') !~ '^[0-9]{1,7}$'
   or jsonb_typeof(r->'height') is distinct from 'number' or coalesce(r->>'height','') !~ '^[0-9]{1,7}$'
   or(r->>'kind'='video' and(jsonb_typeof(r->'duration_ms') is distinct from 'number' or coalesce(r->>'duration_ms','') !~ '^[0-9]{1,5}$' or r->>'id' !~ '[.]mp4$')))
   then return jsonb_build_object('ok',false,'code','VIDEO_REFERENCE_INVALID');end if;
  if exists(select 1 from jsonb_array_elements(p_references) r where (r->>'size')::integer<1 or (r->>'size')::integer>case when r->>'kind'='image' then 16777216 else 52428800 end
   or(r->>'width')::bigint<1 or(r->>'height')::bigint<1 or(r->>'width')::bigint*(r->>'height')::bigint>32000000
   or(r->>'kind'='video' and(r->>'duration_ms')::integer not between 1 and 30000))
   then return jsonb_build_object('ok',false,'code','VIDEO_REFERENCE_INVALID');end if;
  continuation:=exists(select 1 from jsonb_array_elements(p_references) r where r->>'kind'='video');
  if continuation and jsonb_array_length(p_references)<>1 then return jsonb_build_object('ok',false,'code','VIDEO_REFERENCE_INVALID');end if;
  select coalesce(sum((r->>'duration_ms')::integer),0) into ref_ms from jsonb_array_elements(p_references) r where r->>'kind'='video';
 end if;
 -- Continuation charges generated seconds at its own rate, not source+output seconds.
 usd:=seconds*(case when continuation then case when draft then .096 when res='hd' then .328 else .424 end else case when draft then .048 when res='hd' then .136 else .232 end end);
 estimate:=private.flux3_charge(usd);reserve:=private.flux3_charge(usd*1.6);
 profile:=profile||jsonb_build_object('continuation',continuation);
 select balance into b from public.credit_accounts where user_id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');end if;
 if p_mode='platform' and exists(select 1 from public.video_jobs where user_id=p_user_id and billing_status='awaiting_balance') then return jsonb_build_object('ok',false,'code','VIDEO_UNSETTLED_BALANCE');end if;
 if(select count(*) from public.video_jobs where user_id=p_user_id and operation='generate' and status not in ('completed','failed'))>=3 then return jsonb_build_object('ok',false,'code','VIDEO_QUEUE_FULL');end if;
 if p_mode='platform' and b<reserve then return jsonb_build_object('ok',false,'code','CREDITS_INSUFFICIENT','required',reserve,'balance',b);end if;
 if p_mode='platform' then update public.credit_accounts set balance=balance-reserve,updated_at=now() where user_id=p_user_id returning balance into b;end if;
 insert into public.video_jobs(user_id,owner_scope,request_id,billing_mode,operation,model,request_fingerprint,billing_status,resolution,
  requested_duration,reference_duration_ms,unit_credit_cost,estimated_credits,reserved_credits,reference_metadata,history_prompt,history_parameters,history_created_at,pricing_profile,is_draft,draft_source_id)
 values(p_user_id,p_owner,p_request_id,p_mode,p_operation,'flux-3-video',p_fingerprint,case when p_mode='platform' then 'reserved' else 'not_applicable' end,res,
  seconds,ref_ms,0,estimate,case when p_mode='platform' then reserve else 0 end,p_references,prompt,p_parameters,now(),profile,draft,source_id) returning * into j;
 if p_mode='platform' then
  insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
  values(p_user_id,j.id,'reserve',-reserve,'video-reserve:'||j.id::text,jsonb_build_object('media_type','video','model',j.model,'pricing_profile',profile));end if;
 return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(j),'balance',b);
end;$$;
create function public.begin_flux3_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_operation text,p_fingerprint text,p_parameters jsonb,p_references jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.begin_flux3_job(p_owner,p_user_id,p_request_id,p_mode,p_operation,p_fingerprint,p_parameters,p_references);$$;
revoke all on function private.flux3_charge(numeric) from public,anon,authenticated;
grant execute on function private.flux3_charge(numeric) to service_role;
revoke all on function private.begin_flux3_job(text,uuid,uuid,text,text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function private.begin_flux3_job(text,uuid,uuid,text,text,text,jsonb,jsonb) to service_role;
revoke all on function public.begin_flux3_job(text,uuid,uuid,text,text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.begin_flux3_job(text,uuid,uuid,text,text,text,jsonb,jsonb) to service_role;
create function private.apply_flux3_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_error_code text default null,
 p_assets jsonb default '[]',p_cost_usd numeric default null,p_tokens bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.video_jobs;b numeric;c numeric;gap numeric;usd numeric;r jsonb;
begin
 select * into j from public.video_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if not found or j.model<>'flux-3-video' then return jsonb_build_object('ok',false,'code','VIDEO_NOT_FOUND');end if;
 if j.status='failed' or (j.status='completed' and j.billing_status<>'awaiting_balance') then return jsonb_build_object('ok',true,'job',to_jsonb(j));end if;
 if p_event<>'completed' then
  if j.provider_cost_usd>0 and p_event in ('failed','rejected') then return jsonb_build_object('ok',false,'code','VIDEO_ALREADY_GENERATED');end if;
  return private.apply_video_job(p_owner,p_request_id,p_event,p_task_id,p_error_code,p_assets);
 end if;
 if j.billing_mode='own_key' then
  update public.video_jobs set status='completed',billing_status='not_applicable',generated_count=1,charged_credits=0,settled_at=now(),last_checked_at=now(),error_code=null where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j));
 end if;
 usd:=coalesce(j.provider_cost_usd,p_cost_usd);
 if usd is null or usd=0 then
  update public.video_jobs set status='processing',billing_status='awaiting_provider',last_checked_at=now() where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j),'billing_pending',true);
 end if;
 if usd='NaN'::numeric or usd<0 or usd>1000 or (p_tokens is not null and p_tokens<0) then return jsonb_build_object('ok',false,'code','VIDEO_BILLING_INVALID');end if;
 usd:=ceil(usd*100000000)/100000000;
 c:=ceil(usd*(j.pricing_profile->>'usd_cny')::numeric/(j.pricing_profile->>'credit_cny')::numeric*(j.pricing_profile->>'markup')::numeric*2)/2;gap:=c-j.reserved_credits;
 select balance into b from public.credit_accounts where user_id=j.user_id for update;
 if b<gap then
  update public.video_jobs set status='completed',billing_status='awaiting_balance',provider_cost_usd=usd,completion_tokens=p_tokens,generated_count=1,last_checked_at=now() where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j),'required_credits',gap-b,'final_credits',c);
 end if;
 update public.credit_accounts set balance=balance-gap,total_spent=total_spent+c,total_refunded=total_refunded+greatest(-gap,0),updated_at=now() where user_id=j.user_id returning balance into b;
 if gap<>0 then
  insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
  values(j.user_id,j.id,case when gap<0 then 'refund' else 'reserve' end,-gap,'video-flux-adjust:'||j.id::text,jsonb_build_object('media_type','video','settlement_difference',true));
 end if;
 insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
 values(j.user_id,j.id,'spend',0,'video-spend:'||j.id::text,jsonb_build_object('media_type','video','charged_credits',c,'provider_cost_usd',usd,'pricing_profile',j.pricing_profile));
 update public.video_jobs set status='completed',billing_status='settled',charged_credits=c,provider_cost_usd=usd,completion_tokens=p_tokens,generated_count=1,last_checked_at=now(),settled_at=now(),error_code=null where id=j.id returning * into j;
 return jsonb_build_object('ok',true,'job',to_jsonb(j),'balance',b);
end;$$;
create function public.apply_flux3_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_error_code text default null,
 p_assets jsonb default '[]',p_cost_usd numeric default null,p_tokens bigint default null)
returns jsonb language sql security invoker set search_path='' as $$select private.apply_flux3_job(p_owner,p_request_id,p_event,p_task_id,p_error_code,p_assets,p_cost_usd,p_tokens);$$;
revoke all on function private.apply_flux3_job(text,uuid,text,text,text,jsonb,numeric,bigint) from public,anon,authenticated;
grant execute on function private.apply_flux3_job(text,uuid,text,text,text,jsonb,numeric,bigint) to service_role;
revoke all on function public.apply_flux3_job(text,uuid,text,text,text,jsonb,numeric,bigint) from public,anon,authenticated;
grant execute on function public.apply_flux3_job(text,uuid,text,text,text,jsonb,numeric,bigint) to service_role;


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
      case when v.model in ('seedance-2.5','seedance-2.0','seedance-2.0-fast','gemini-omni-1.1-flash','MiniMax-H3','MiniMax-H3-Max','wan3.0-video','flux-3-video') then 'actual_cost' else 'second' end as billing_unit,
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
