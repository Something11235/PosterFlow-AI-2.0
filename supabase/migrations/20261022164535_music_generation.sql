-- Music has an independent lifecycle: never refunded by the image stale-job RPC.
-- No keys, prompts, lyrics, media URLs or image data are persisted here.
create table public.music_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  owner_scope text not null check (char_length(owner_scope) between 8 and 160),
  request_id uuid not null,
  billing_mode text not null check (billing_mode in ('platform','own_key')),
  model text not null check (model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'),
  version text not null,
  request_fingerprint text not null check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  provider_task_id text,
  status text not null default 'submitting' check (status in ('submitting','submitted','processing','submission_unknown','unknown','completed','failed')),
  billing_status text not null check (billing_status in ('reserved','settled','refunded','awaiting_balance','not_applicable')),
  credits_per_song integer not null default 2 check (credits_per_song = 2),
  reserved_credits integer not null default 0 check (reserved_credits >= 0),
  charged_credits integer not null default 0 check (charged_credits >= 0),
  generated_count integer not null default 0 check (generated_count between 0 and 64),
  error_code text,
  created_at timestamptz not null default now(),
  last_checked_at timestamptz,
  settled_at timestamptz,
  unique(owner_scope,request_id),
  unique(owner_scope,provider_task_id),
  check (billing_mode <> 'platform' or user_id is not null)
);
create index music_jobs_owner_created_idx on public.music_jobs(owner_scope,created_at desc,request_id desc);
create index music_jobs_reconcile_idx on public.music_jobs(last_checked_at nulls first)
  where billing_mode = 'platform' and billing_status in ('reserved','awaiting_balance') and provider_task_id is not null;
alter table public.music_jobs enable row level security;
revoke all on public.music_jobs from public,anon,authenticated;
grant select,insert,update,delete on public.music_jobs to service_role;
alter table public.credit_transactions add column music_job_id uuid references public.music_jobs(id) on delete set null;
create index credit_transactions_music_job_idx on public.credit_transactions(music_job_id) where music_job_id is not null;

-- The private transaction functions need to read authoritative auth.users and
-- atomically update the shared credit account. Existing application roles have
-- SELECT-only credit access; keep privileged writes behind this narrow API.
create schema if not exists private;
grant usage on schema private to service_role;
create function private.begin_music_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_model text,p_version text,p_fingerprint text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_job public.music_jobs;
  v_balance integer;
begin
  if p_mode not in ('platform','own_key') or p_model is null or p_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'
     or p_owner is null or p_request_id is null or p_fingerprint is null
     or p_fingerprint !~ '^[a-f0-9]{64}$' then
    return jsonb_build_object('ok',false,'code','INVALID_MUSIC_INPUT');
  end if;
  if p_version is null or char_length(p_version)>128 or (p_mode='platform' and (
       p_model not in ('suno','flowmusic')
       or (p_model='suno' and p_version not in ('v6','v6-wild','v6-mini'))
       or (p_model='flowmusic' and p_version not in ('lyria-3-pro','lyria-3.5')))) then
    return jsonb_build_object('ok',false,'code','INVALID_MUSIC_VERSION');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_owner || ':' || p_request_id::text,0));
  select * into v_job from public.music_jobs where owner_scope=p_owner and request_id=p_request_id for update;
  if found then
    if v_job.request_fingerprint <> p_fingerprint or v_job.billing_mode <> p_mode then
      return jsonb_build_object('ok',false,'code','MUSIC_REQUEST_CONFLICT');
    end if;
    return jsonb_build_object('ok',true,'existing',true,'job',to_jsonb(v_job));
  end if;
  if p_mode='platform' then
    if p_user_id is null or p_owner <> 'user-' || p_user_id::text then
      return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');
    end if;
    if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then
      return jsonb_build_object('ok',false,'code','EMAIL_UNVERIFIED');
    end if;
    if not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null) then
      return jsonb_build_object('ok',false,'code','ACCOUNT_FROZEN');
    end if;
    select balance into v_balance from public.credit_accounts where user_id=p_user_id for update;
    if v_balance is null or v_balance < 2 then
      return jsonb_build_object('ok',false,'code','INSUFFICIENT_CREDITS');
    end if;
    update public.credit_accounts set balance=balance-2,updated_at=now() where user_id=p_user_id returning balance into v_balance;
  end if;
  insert into public.music_jobs(user_id,owner_scope,request_id,billing_mode,model,version,request_fingerprint,billing_status,reserved_credits)
  values(p_user_id,p_owner,p_request_id,p_mode,p_model,p_version,p_fingerprint,
         case when p_mode='platform' then 'reserved' else 'not_applicable' end,
         case when p_mode='platform' then 2 else 0 end)
  returning * into v_job;
  if p_mode='platform' then
    insert into public.credit_transactions(user_id,music_job_id,type,delta,idempotency_key,metadata)
    values(p_user_id,v_job.id,'reserve',-2,'music-reserve:' || v_job.id::text,jsonb_build_object('media_type','music','model',p_model,'credits_per_song',2));
  end if;
  return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(v_job),'balance',v_balance);
end;
$$;

create function private.apply_music_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_count integer default 0,p_error_code text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_job public.music_jobs;
  v_balance integer;
  v_charge integer;
  v_extra integer;
begin
  select * into v_job from public.music_jobs where owner_scope=p_owner and request_id=p_request_id for update;
  if not found then return jsonb_build_object('ok',false,'code','MUSIC_NOT_FOUND'); end if;
  if p_event not in ('submitted','submission_unknown','rejected','processing','unknown','completed','failed') or p_count is null or p_count < 0 or p_count > 64 then
    return jsonb_build_object('ok',false,'code','INVALID_MUSIC_EVENT');
  end if;
  -- Terminal billing never regresses or repeats even under concurrent polling.
  if v_job.billing_status in ('settled','refunded') or (v_job.billing_mode='own_key' and v_job.status in ('completed','failed')) then
    return jsonb_build_object('ok',true,'job',to_jsonb(v_job));
  end if;
  if p_event='submitted' then
    if p_task_id is null or p_task_id !~ '^[A-Za-z0-9_-]{8,160}$' then
      return jsonb_build_object('ok',false,'code','INVALID_MUSIC_TASK');
    end if;
    if v_job.provider_task_id is not null and v_job.provider_task_id <> p_task_id then
      return jsonb_build_object('ok',false,'code','MUSIC_REQUEST_CONFLICT');
    end if;
    update public.music_jobs set provider_task_id=p_task_id,status='submitted',last_checked_at=now() where id=v_job.id;
  elsif p_event='completed' or v_job.status='completed' then
    -- Freeze the first trusted result count, including when awaiting top-up.
    if v_job.status <> 'completed' then
      if p_count < 1 then return jsonb_build_object('ok',false,'code','MUSIC_EMPTY_RESULT'); end if;
      v_job.generated_count := p_count;
    end if;
    v_charge := v_job.generated_count * v_job.credits_per_song;
    if v_job.billing_mode='platform' then
      select balance into v_balance from public.credit_accounts where user_id=v_job.user_id for update;
      v_extra := v_charge-v_job.reserved_credits;
      if v_balance < v_extra then
        update public.music_jobs set status='completed',generated_count=v_job.generated_count,billing_status='awaiting_balance',last_checked_at=now() where id=v_job.id returning * into v_job;
        return jsonb_build_object('ok',true,'job',to_jsonb(v_job),'balance',v_balance);
      end if;
      update public.credit_accounts set balance=balance-v_extra,total_spent=total_spent+v_charge,updated_at=now() where user_id=v_job.user_id returning balance into v_balance;
      insert into public.credit_transactions(user_id,music_job_id,type,delta,idempotency_key,metadata)
      values(v_job.user_id,v_job.id,'spend',-v_extra,'music-spend:' || v_job.id::text,
             jsonb_build_object('media_type','music','model',v_job.model,'song_count',v_job.generated_count,'charged_credits',v_charge,'reserved_credits',v_job.reserved_credits));
    end if;
    update public.music_jobs set status='completed',generated_count=v_job.generated_count,
      charged_credits=case when billing_mode='platform' then v_charge else 0 end,
      billing_status=case when billing_mode='platform' then 'settled' else 'not_applicable' end,
      settled_at=now(),last_checked_at=now() where id=v_job.id;
  elsif p_event in ('failed','rejected') then
    if v_job.billing_mode='platform' then
      update public.credit_accounts set balance=balance+v_job.reserved_credits,total_refunded=total_refunded+v_job.reserved_credits,updated_at=now()
      where user_id=v_job.user_id returning balance into v_balance;
      insert into public.credit_transactions(user_id,music_job_id,type,delta,idempotency_key,metadata)
      values(v_job.user_id,v_job.id,'refund',v_job.reserved_credits,'music-refund:' || v_job.id::text,jsonb_build_object('media_type','music'));
    end if;
    update public.music_jobs set status='failed',billing_status=case when billing_mode='platform' then 'refunded' else 'not_applicable' end,
      error_code=left(p_error_code,100),settled_at=now(),last_checked_at=now() where id=v_job.id;
  else
    update public.music_jobs set status=p_event,error_code=left(p_error_code,100),last_checked_at=now() where id=v_job.id;
  end if;
  select * into v_job from public.music_jobs where id=v_job.id;
  return jsonb_build_object('ok',true,'job',to_jsonb(v_job),'balance',v_balance);
end;
$$;
revoke all on function private.begin_music_job(text,uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function private.apply_music_job(text,uuid,text,text,integer,text) from public,anon,authenticated;
grant execute on function private.begin_music_job(text,uuid,uuid,text,text,text,text) to service_role;
grant execute on function private.apply_music_job(text,uuid,text,text,integer,text) to service_role;
create function public.begin_music_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_model text,p_version text,p_fingerprint text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.begin_music_job(p_owner,p_user_id,p_request_id,p_mode,p_model,p_version,p_fingerprint);
$$;
create function public.apply_music_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_count integer default 0,p_error_code text default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.apply_music_job(p_owner,p_request_id,p_event,p_task_id,p_count,p_error_code);
$$;
revoke all on function public.begin_music_job(text,uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke all on function public.apply_music_job(text,uuid,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.begin_music_job(text,uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.apply_music_job(text,uuid,text,text,integer,text) to service_role;
