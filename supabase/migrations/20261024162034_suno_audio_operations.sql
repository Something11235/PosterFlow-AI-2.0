-- Apply with the approved Suno audio release; preserve existing task and money fields.
set local lock_timeout='5s';
-- Uses the already-merged music_jobs history fields; does not create a history table.
alter table public.music_jobs
 add column operation text not null default 'generate' check(operation in ('generate','inspo','upload_cover')),
 add column reference_count integer not null default 0 check(reference_count between 0 and 4);
alter table public.music_jobs drop constraint music_jobs_history_parameters_check;
alter table public.music_jobs add constraint music_jobs_history_parameters_check check(
 jsonb_typeof(history_parameters)='object' and
 history_parameters-array['model','version','parameter_format','custom','instrumental','prompt','sound_prompt','lyrics','title','style','negative_tags','operation']='{}'::jsonb);

create function private.begin_music_audio_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_version text,p_fingerprint text,p_prompt text,p_parameters jsonb,p_operation text,p_reference_count integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;j public.music_jobs;
begin
 if p_operation is null or p_operation not in ('inspo','upload_cover') or p_reference_count is null
   or p_reference_count not between 1 and 4 or (p_operation='upload_cover' and p_reference_count<>1)
   or p_parameters->>'operation' is distinct from p_operation or p_user_id is null
   or not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null)
   or not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null)
   or (p_mode='own_key' and p_owner !~ ('^user-'||p_user_id::text||'-[a-f0-9]{64}$')) then
   return jsonb_build_object('ok',false,'code','INVALID_MUSIC_INPUT');
 end if;
 r:=public.begin_music_job_with_history(p_owner,p_user_id,p_request_id,p_mode,'suno',p_version,p_fingerprint,p_prompt,p_parameters-'operation');
 if not coalesce((r->>'ok')::boolean,false) then return r;end if;
 select * into j from public.music_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if coalesce((r->>'existing')::boolean,false) then
  if j.operation<>p_operation or j.reference_count<>p_reference_count then
   return jsonb_build_object('ok',false,'code','MUSIC_REQUEST_CONFLICT');
  end if;
 else
  update public.music_jobs set operation=p_operation,reference_count=p_reference_count,
   history_parameters=case when history_created_at is null then null else history_parameters||jsonb_build_object('operation',p_operation) end
   where id=j.id returning * into j;
 end if;
 return r||jsonb_build_object('job',to_jsonb(j));
end;
$$;
create function public.begin_music_audio_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_version text,p_fingerprint text,p_prompt text,p_parameters jsonb,p_operation text,p_reference_count integer)
returns jsonb language sql security invoker set search_path='' as $$
 select private.begin_music_audio_job(p_owner,p_user_id,p_request_id,p_mode,p_version,p_fingerprint,p_prompt,p_parameters,p_operation,p_reference_count);
$$;
revoke all on function private.begin_music_audio_job(text,uuid,uuid,text,text,text,text,jsonb,text,integer),
 public.begin_music_audio_job(text,uuid,uuid,text,text,text,text,jsonb,text,integer) from public,anon,authenticated;
grant execute on function private.begin_music_audio_job(text,uuid,uuid,text,text,text,text,jsonb,text,integer),
 public.begin_music_audio_job(text,uuid,uuid,text,text,text,text,jsonb,text,integer) to service_role;

-- Admin usage shows the creation method without changing its DAU definition.
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
), active_days as (
  select (a.created_at at time zone 'Asia/Shanghai')::date as stat_date,
    count(distinct a.user_id) as active_users,
    count(distinct a.user_id) filter(where a.kind='image') as image_active_users,
    count(distinct a.user_id) filter(where a.kind='music') as music_active_users
  from activity a group by 1
), days as (
  select d::date as stat_date,coalesce(a.active_users,0) as active_users,
    coalesce(a.image_active_users,0) as image_active_users,coalesce(a.music_active_users,0) as music_active_users
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
  'timezone','Asia/Shanghai'
);
$$;
revoke all on function private.get_admin_music_overview(date,date,text,integer) from public,anon,authenticated;
grant execute on function private.get_admin_music_overview(date,date,text,integer) to service_role;

-- Audio material cleanup uses the existing private bucket and Vault configuration.
create or replace function private.prune_music_reference_audio(p_dry_run boolean default true)
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
    if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('posterflow.music_reference_retention.run')) then
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
       and name ~ '^posterflow/music-[a-f0-9]{64}/audio-references/[0-9]{10}-[a-f0-9]{32}[.](mp3|wav)$'
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
                 and name ~ '^posterflow/music-[a-f0-9]{64}/audio-references/[0-9]{10}-[a-f0-9]{32}[.](mp3|wav)$'
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
revoke all on function private.prune_music_reference_audio(boolean) from public, anon, authenticated, service_role;



select cron.schedule('posterflow-music-reference-retention-12h','37 * * * *','select private.prune_music_reference_audio(false);');
