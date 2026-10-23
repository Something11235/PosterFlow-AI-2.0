-- Durable asynchronous image tasks. Existing image RPC signatures/prices remain.
create table public.apimart_image_jobs (
  id uuid primary key default gen_random_uuid(),
  owner_scope text not null check (char_length(owner_scope) between 8 and 240),
  user_id uuid references public.profiles(id) on delete cascade,
  request_id uuid not null,
  billing_mode text not null check (billing_mode in ('platform','own_key')),
  model text not null check (model in ('gemini-nano-banana-2.1','nano-banana-pro','grok-imagine-image-2.0','grok-imagine-2.0-ext')),
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  requested_count integer not null check (requested_count between 1 and 4),
  generation_job_id uuid unique references public.generation_jobs(id) on delete set null,
  provider_task_id text,
  status text not null default 'submitting' check (status in ('submitting','submitted','processing','submission_unknown','unknown','saving','completed','failed')),
  image_keys jsonb not null default '[]'::jsonb check (jsonb_typeof(image_keys)='array'),
  error_code text,
  save_token uuid,
  save_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_scope,request_id),
  check (billing_mode <> 'platform' or user_id is not null),
  check (model <> 'nano-banana-pro' or requested_count=1)
);
create index apimart_image_owner_created_idx on public.apimart_image_jobs(owner_scope,created_at desc);
alter table public.apimart_image_jobs enable row level security;
revoke all on public.apimart_image_jobs from public,anon,authenticated;
grant select on public.apimart_image_jobs to service_role;
create schema if not exists private;
grant usage on schema private to service_role;

-- Extend the installed production implementation rather than replay old files.
do $patch$
declare d text; needle text := 'when ''gpt-image-2'' then 1';
begin
  d:=pg_get_functiondef('public.reserve_platform_credits(uuid,uuid,integer,text,text,text,integer,integer)'::regprocedure);
  if position(needle in d)=0 or position('gemini-nano-banana-2.1' in d)>0 then
    raise exception 'Unexpected installed image reservation function; review migration';
  end if;
  d:=replace(d,needle,needle || E'\n    when ''gemini-nano-banana-2.1'' then 1\n    when ''nano-banana-pro'' then 1\n    when ''grok-imagine-image-2.0'' then 1\n    when ''grok-imagine-2.0-ext'' then 1');
  execute d;
  d:=pg_get_functiondef('public.recover_stale_generation_jobs(uuid,integer)'::regprocedure);
  needle:='and billing_mode = ''platform''';
  if position(needle in d)=0 then raise exception 'Unexpected stale image recovery function'; end if;
  d:=replace(d,needle,needle || E'\n      and not exists (select 1 from public.apimart_image_jobs aj where aj.generation_job_id=generation_jobs.id)');
  execute d;
end;
$patch$;

create function private.begin_apimart_image_job(p_owner text,p_user uuid,p_request uuid,p_mode text,p_model text,p_count integer,p_fingerprint text,p_prompt text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.apimart_image_jobs; r jsonb; gid uuid; b integer;
begin
  if p_mode not in ('platform','own_key') or p_model not in ('gemini-nano-banana-2.1','nano-banana-pro','grok-imagine-image-2.0','grok-imagine-2.0-ext')
    or p_count not between 1 and 4 or (p_model='nano-banana-pro' and p_count<>1)
    or p_fingerprint !~ '^[a-f0-9]{64}$' or length(p_prompt) not between 1 and 6000
    or (p_mode='platform' and (p_user is null or p_owner<>'user-'||p_user::text)) then
    return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('apimart-image:'||p_owner||p_request::text,0));
  select * into j from public.apimart_image_jobs where owner_scope=p_owner and request_id=p_request for update;
  if found then
    if j.request_fingerprint<>p_fingerprint or j.model<>p_model or j.billing_mode<>p_mode or j.user_id is distinct from p_user then
      return jsonb_build_object('ok',false,'code','IMAGE_REQUEST_CONFLICT');
    end if;
    select balance into b from public.credit_accounts where user_id=p_user;
    return jsonb_build_object('ok',true,'existing',true,'job',to_jsonb(j),'balance',b);
  end if;
  if exists(select 1 from public.generation_jobs where request_id=p_request) then
    return jsonb_build_object('ok',false,'code','IMAGE_REQUEST_CONFLICT');
  end if;
  if p_mode='platform' then
    r:=public.reserve_platform_credits(p_user,p_request,p_count,'api.apimart.ai',p_model,p_prompt,null,null);
    if not coalesce((r->>'ok')::boolean,false) then return r; end if;
    gid:=(r->>'job_id')::uuid;
    b:=(r->>'balance')::integer;
  elsif p_user is not null then
    insert into public.generation_jobs(user_id,request_id,billing_mode,provider,model,status,requested_count,reserved_credits,prompt)
    values(p_user,p_request,'own_key','api.apimart.ai',p_model,'running',p_count,0,p_prompt) returning id into gid;
  end if;
  insert into public.apimart_image_jobs(owner_scope,user_id,request_id,billing_mode,model,requested_count,request_fingerprint,generation_job_id)
  values(p_owner,p_user,p_request,p_mode,p_model,p_count,p_fingerprint,gid) returning * into j;
  return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(j),'balance',b);
end;
$$;

create function private.apply_apimart_image_job(p_owner text,p_request uuid,p_event text,p_task text default null,p_images jsonb default '[]'::jsonb,p_token uuid default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.apimart_image_jobs; r jsonb; b integer; n integer;
begin
  select * into j from public.apimart_image_jobs where owner_scope=p_owner and request_id=p_request for update;
  if not found then return jsonb_build_object('ok',false,'code','IMAGE_TASK_NOT_FOUND'); end if;
  if j.status in ('completed','failed') then
    select balance into b from public.credit_accounts where user_id=j.user_id;
    return jsonb_build_object('ok',true,'job',to_jsonb(j),'balance',b,'claimed',false);
  end if;
  if p_event='submitted' then
    if p_task is null or p_task !~ '^[A-Za-z0-9_-]{8,160}$' or (j.provider_task_id is not null and j.provider_task_id<>p_task) then
      return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK');
    end if;
    update public.apimart_image_jobs set provider_task_id=p_task,status='submitted',updated_at=now() where id=j.id;
  elsif p_event='submission_unknown' and j.provider_task_id is null then
    update public.apimart_image_jobs set status='submission_unknown',error_code=left(p_error,100),updated_at=now() where id=j.id;
  elsif p_event='claim' then
    if j.provider_task_id is null or p_token is null or (j.status='saving' and j.save_until>now()) then
      return jsonb_build_object('ok',true,'job',to_jsonb(j),'claimed',false);
    end if;
    update public.apimart_image_jobs set status='saving',save_token=p_token,save_until=now()+interval '5 minutes',updated_at=now() where id=j.id;
  elsif p_event in ('completed','retry') then
    if p_token is null or j.save_token is distinct from p_token or j.status<>'saving' then
      return jsonb_build_object('ok',false,'code','IMAGE_SAVE_CONFLICT');
    end if;
    if p_event='retry' then
      update public.apimart_image_jobs set status='processing',save_token=null,save_until=null,error_code=left(p_error,100),updated_at=now() where id=j.id;
    else
      if jsonb_typeof(p_images)<>'array' then return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK'); end if;
      n:=jsonb_array_length(p_images);
      if n not between 1 and j.requested_count then return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK'); end if;
      if j.billing_mode='platform' then
        r:=public.settle_generation(j.generation_job_id,n,extract(epoch from (now()-j.created_at))::integer*1000,p_images);
        if not coalesce((r->>'ok')::boolean,false) then return r; end if;
        b:=(r->>'balance')::integer;
      elsif j.generation_job_id is not null then
        update public.generation_jobs set status='succeeded',generated_count=n,image_keys=p_images,settled_at=now(),duration_ms=extract(epoch from (now()-j.created_at))::integer*1000 where id=j.generation_job_id;
      end if;
      update public.apimart_image_jobs set status='completed',image_keys=p_images,save_token=null,save_until=null,error_code=null,updated_at=now() where id=j.id;
    end if;
  elsif p_event='failed' then
    -- Never let a stale failure callback race a worker currently saving results.
    if j.status='saving' and j.save_until>now() then return jsonb_build_object('ok',true,'job',to_jsonb(j),'claimed',false); end if;
    if j.billing_mode='platform' then
      r:=public.refund_generation(j.generation_job_id,coalesce(p_error,'APIMART_TASK_FAILED'));
      if not coalesce((r->>'ok')::boolean,false) then return r; end if;
      b:=(r->>'balance')::integer;
    elsif j.generation_job_id is not null then
      update public.generation_jobs set status='failed',error_code=left(p_error,100),settled_at=now() where id=j.generation_job_id;
    end if;
    update public.apimart_image_jobs set status='failed',error_code=left(p_error,100),updated_at=now() where id=j.id;
  elsif p_event not in ('processing','unknown') then
    return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK');
  elsif j.status<>'saving' then
    update public.apimart_image_jobs set status=p_event,updated_at=now() where id=j.id;
  end if;
  select * into j from public.apimart_image_jobs where id=j.id;
  if b is null then select balance into b from public.credit_accounts where user_id=j.user_id; end if;
  return jsonb_build_object('ok',true,'job',to_jsonb(j),'balance',b,'claimed',p_event='claim');
end;
$$;

create function public.begin_apimart_image_job(p_owner text,p_user uuid,p_request uuid,p_mode text,p_model text,p_count integer,p_fingerprint text,p_prompt text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.begin_apimart_image_job(p_owner,p_user,p_request,p_mode,p_model,p_count,p_fingerprint,p_prompt);
$$;
create function public.apply_apimart_image_job(p_owner text,p_request uuid,p_event text,p_task text default null,p_images jsonb default '[]'::jsonb,p_token uuid default null,p_error text default null)
returns jsonb language sql security invoker set search_path='' as $$
 select private.apply_apimart_image_job(p_owner,p_request,p_event,p_task,p_images,p_token,p_error);
$$;
revoke all on function private.begin_apimart_image_job(text,uuid,uuid,text,text,integer,text,text),public.begin_apimart_image_job(text,uuid,uuid,text,text,integer,text,text),private.apply_apimart_image_job(text,uuid,text,text,jsonb,uuid,text),public.apply_apimart_image_job(text,uuid,text,text,jsonb,uuid,text) from public,anon,authenticated;
grant execute on function private.begin_apimart_image_job(text,uuid,uuid,text,text,integer,text,text),public.begin_apimart_image_job(text,uuid,uuid,text,text,integer,text,text),private.apply_apimart_image_job(text,uuid,text,text,jsonb,uuid,text),public.apply_apimart_image_job(text,uuid,text,text,jsonb,uuid,text) to service_role;
