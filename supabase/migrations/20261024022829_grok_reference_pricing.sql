-- Preserve existing reservations, balances and ledger. Old RPCs remain valid.
-- New server-only entry snapshots actual validated reference count and unit cost.
alter table public.apimart_image_jobs
  add column reference_count integer not null default 0 check (reference_count between 0 and 8),
  add column unit_credit_cost integer not null default 1 check (unit_credit_cost between 0 and 2);

-- Separate fixed-cost helper copies the reviewed current production validation
-- and atomic reservation path. Existing legacy image reservation stays unchanged.
CREATE OR REPLACE FUNCTION private.reserve_grok_reference_credits(p_user_id uuid, p_request_id uuid, p_count integer, p_provider text, p_model text, p_prompt text, p_user_daily_limit integer DEFAULT NULL::integer, p_platform_daily_limit integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.generation_jobs%rowtype;
  v_balance integer;
  v_status text;
  v_user_total integer;
  v_platform_total integer;
  v_job_id uuid;
  v_model_cost integer;
  v_reserved_credits integer;
begin
  if p_count < 1 or p_count > 4 then
    return jsonb_build_object('ok', false, 'code', 'PARAMETER_INVALID');
  end if;
  v_model_cost := case when p_model='grok-imagine-image-2.0' then 2 else 0 end;
  if v_model_cost = 0 then
    return jsonb_build_object('ok', false, 'code', 'MODEL_NOT_ALLOWED');
  end if;
  v_reserved_credits := p_count * v_model_cost;

  perform public.ensure_signup_bonus(p_user_id);
  select status into v_status from public.profiles where id = p_user_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'AUTH_USER_NOT_FOUND');
  end if;
  if v_status <> 'active' then
    return jsonb_build_object('ok', false, 'code', 'ACCOUNT_FROZEN');
  end if;
  if not exists (select 1 from auth.users where id = p_user_id and email_confirmed_at is not null) then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_UNVERIFIED');
  end if;

  select * into v_existing from public.generation_jobs where request_id = p_request_id for update;
  if found then
    if v_existing.user_id <> p_user_id then
      return jsonb_build_object('ok', false, 'code', 'REQUEST_ID_CONFLICT');
    end if;
    return jsonb_build_object(
      'ok', true,
      'existing', true,
      'job_id', v_existing.id,
      'status', v_existing.status,
      'images', v_existing.image_keys,
      'balance', (select balance from public.credit_accounts where user_id = p_user_id)
    );
  end if;

  if p_user_daily_limit is not null and p_user_daily_limit > 0 then
    select coalesce(sum(requested_count), 0) into v_user_total
    from public.generation_jobs
    where user_id = p_user_id and billing_mode = 'platform' and created_at >= date_trunc('day', now());
    if v_user_total + p_count > p_user_daily_limit then
      return jsonb_build_object('ok', false, 'code', 'USER_DAILY_LIMIT');
    end if;
  end if;
  if p_platform_daily_limit is not null and p_platform_daily_limit > 0 then
    select coalesce(sum(requested_count), 0) into v_platform_total
    from public.generation_jobs
    where billing_mode = 'platform' and created_at >= date_trunc('day', now());
    if v_platform_total + p_count > p_platform_daily_limit then
      return jsonb_build_object('ok', false, 'code', 'PLATFORM_DAILY_LIMIT');
    end if;
  end if;

  select balance into v_balance from public.credit_accounts where user_id = p_user_id for update;
  if coalesce(v_balance, 0) < v_reserved_credits then
    return jsonb_build_object('ok', false, 'code', 'CREDITS_INSUFFICIENT', 'balance', coalesce(v_balance, 0), 'required', v_reserved_credits);
  end if;

  insert into public.generation_jobs (
    user_id, request_id, billing_mode, provider, model, status, requested_count,
    reserved_credits, prompt, metadata
  ) values (
    p_user_id, p_request_id, 'platform', p_provider, p_model, 'running', p_count,
    v_reserved_credits, left(p_prompt, 6000), jsonb_build_object('model_cost', v_model_cost)
  ) returning id into v_job_id;

  update public.credit_accounts
  set balance = balance - v_reserved_credits, updated_at = now()
  where user_id = p_user_id;
  insert into public.credit_transactions (user_id, job_id, type, delta, idempotency_key, metadata)
  values (p_user_id, v_job_id, 'reserve', -v_reserved_credits, 'reserve:' || p_request_id::text,
    jsonb_build_object('count', p_count, 'model', p_model, 'model_cost', v_model_cost));

  select balance into v_balance from public.credit_accounts where user_id = p_user_id;
  return jsonb_build_object('ok', true, 'existing', false, 'job_id', v_job_id, 'status', 'running', 'balance', v_balance, 'reserved', v_reserved_credits);
end;
$function$;


CREATE OR REPLACE FUNCTION private.begin_apimart_image_job_v2(p_owner text, p_user uuid, p_request uuid, p_mode text, p_model text, p_count integer, p_fingerprint text, p_prompt text, p_reference_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j public.apimart_image_jobs; r jsonb; gid uuid; b integer; v_cost integer;
begin
  if p_reference_count is null or p_reference_count<0 or p_reference_count>8
    or (p_model='grok-imagine-image-2.0' and p_reference_count>3)
    or (p_model='grok-imagine-2.0-ext' and p_reference_count<>0)
    or p_model='nano-banana-pro' then
    return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK');
  end if;
  v_cost:=case when p_mode='own_key' then 0 when p_model='grok-imagine-image-2.0' and p_reference_count>0 then 2 else 1 end;
  if p_mode not in ('platform','own_key') or p_model not in ('gemini-nano-banana-2.1','nano-banana-pro','grok-imagine-image-2.0','grok-imagine-2.0-ext')
    or p_count not between 1 and 4 or (p_model='nano-banana-pro' and p_count<>1)
    or p_fingerprint !~ '^[a-f0-9]{64}$' or length(p_prompt) not between 1 and 6000
    or (p_mode='platform' and (p_user is null or p_owner<>'user-'||p_user::text)) then
    return jsonb_build_object('ok',false,'code','INVALID_IMAGE_TASK');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('apimart-image:'||p_owner||p_request::text,0));
  select * into j from public.apimart_image_jobs where owner_scope=p_owner and request_id=p_request for update;
  if found then
    if j.request_fingerprint<>p_fingerprint or j.model<>p_model or j.billing_mode<>p_mode or j.user_id is distinct from p_user or j.reference_count<>p_reference_count then
      return jsonb_build_object('ok',false,'code','IMAGE_REQUEST_CONFLICT');
    end if;
    select balance into b from public.credit_accounts where user_id=p_user;
    return jsonb_build_object('ok',true,'existing',true,'job',to_jsonb(j),'balance',b);
  end if;
  if exists(select 1 from public.generation_jobs where request_id=p_request) then
    return jsonb_build_object('ok',false,'code','IMAGE_REQUEST_CONFLICT');
  end if;
  if p_mode='platform' then
    if v_cost=2 then
      r:=private.reserve_grok_reference_credits(p_user,p_request,p_count,'api.apimart.ai',p_model,p_prompt,null,null);
    else
      r:=public.reserve_platform_credits(p_user,p_request,p_count,'api.apimart.ai',p_model,p_prompt,null,null);
    end if;
    if not coalesce((r->>'ok')::boolean,false) then return r; end if;
    gid:=(r->>'job_id')::uuid;
    b:=(r->>'balance')::integer;
  elsif p_user is not null then
    insert into public.generation_jobs(user_id,request_id,billing_mode,provider,model,status,requested_count,reserved_credits,prompt)
    values(p_user,p_request,'own_key','api.apimart.ai',p_model,'running',p_count,0,p_prompt) returning id into gid;
  end if;
  insert into public.apimart_image_jobs(owner_scope,user_id,request_id,billing_mode,model,requested_count,request_fingerprint,generation_job_id,reference_count,unit_credit_cost)
  values(p_owner,p_user,p_request,p_mode,p_model,p_count,p_fingerprint,gid,p_reference_count,v_cost) returning * into j;
  return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(j),'balance',b);
end;
$function$;


create function public.begin_apimart_image_job_v2(p_owner text,p_user uuid,p_request uuid,p_mode text,p_model text,p_count integer,p_fingerprint text,p_prompt text,p_reference_count integer)
returns jsonb language sql security invoker set search_path='' as $$
 select private.begin_apimart_image_job_v2(p_owner,p_user,p_request,p_mode,p_model,p_count,p_fingerprint,p_prompt,p_reference_count);
$$;
revoke all on function private.reserve_grok_reference_credits(uuid,uuid,integer,text,text,text,integer,integer),
  private.begin_apimart_image_job_v2(text,uuid,uuid,text,text,integer,text,text,integer),
  public.begin_apimart_image_job_v2(text,uuid,uuid,text,text,integer,text,text,integer) from public,anon,authenticated;
grant execute on function private.reserve_grok_reference_credits(uuid,uuid,integer,text,text,text,integer,integer),
  private.begin_apimart_image_job_v2(text,uuid,uuid,text,text,integer,text,text,integer),
  public.begin_apimart_image_job_v2(text,uuid,uuid,text,text,integer,text,text,integer) to service_role;
