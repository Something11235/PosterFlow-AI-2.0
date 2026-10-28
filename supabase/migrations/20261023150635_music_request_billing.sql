-- New and uncharged music requests cost two credits total, regardless of tracks.
-- Preserve existing settled/refunded monetary records and old RPC signatures.
alter table public.music_jobs
  add column billing_unit text not null default 'request' check (billing_unit in ('request','song')),
  add column credits_per_request integer not null default 2 check (credits_per_request=2);
update public.music_jobs set billing_unit='song' where billing_status in ('settled','refunded');
comment on column public.music_jobs.credits_per_song is 'Legacy per-track pricing snapshot; retained for historical settled jobs only.';
comment on column public.music_jobs.credits_per_request is 'Fixed website credits for a successful music request, independent of generated_count.';

create or replace function private.begin_music_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_model text,p_version text,p_fingerprint text)
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
    values(p_user_id,v_job.id,'reserve',-2,'music-reserve:' || v_job.id::text,jsonb_build_object('media_type','music','model',p_model,'billing_unit','request','credits_per_request',2));
  end if;
  return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(v_job),'balance',v_balance);
end;
$$;

create or replace function private.apply_music_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_count integer default 0,p_error_code text default null)
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
    v_charge := case when v_job.billing_unit='request' then v_job.credits_per_request
                     else v_job.generated_count * v_job.credits_per_song end;
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
             jsonb_build_object('media_type','music','model',v_job.model,'song_count',v_job.generated_count,'billing_unit',v_job.billing_unit,'credits_per_request',v_job.credits_per_request,'charged_credits',v_charge,'reserved_credits',v_job.reserved_credits));
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
