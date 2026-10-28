-- Prepare locally; apply only with an explicitly approved video release.
set local lock_timeout='5s';
alter table public.credit_accounts
 alter column balance type numeric(18,4),
 alter column total_granted type numeric(18,4),
 alter column total_spent type numeric(18,4),
 alter column total_refunded type numeric(18,4),
 add constraint credit_accounts_finite check(balance<>'NaN'::numeric and total_granted<>'NaN'::numeric
  and total_spent<>'NaN'::numeric and total_refunded<>'NaN'::numeric);
alter table public.credit_transactions alter column delta type numeric(18,4),
 add constraint credit_transactions_delta_finite check(delta<>'NaN'::numeric);

-- Existing image/music/recharge prices stay integers. Their account snapshots
-- must nevertheless retain a fractional remainder after a video charge.
-- Change only balance locals/casts, preserving signatures, grants and prices.
do $$
declare r record;d text;changed integer:=0;
begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private') and p.prokind='f' and p.proname in (
   'ensure_signup_bonus','reserve_platform_credits','settle_generation','refund_generation',
   'admin_adjust_credits','complete_credit_order','begin_music_job','apply_music_job',
   'begin_apimart_image_job','apply_apimart_image_job','begin_apimart_image_job_v2','begin_apimart_image_job_v3',
   'reserve_grok_reference_credits','reserve_nano_4k_credits')
 loop
  d:=pg_get_functiondef(r.oid);
  d:=regexp_replace(d,'\mv_balance\s+integer\M','v_balance numeric','gi');
  d:=regexp_replace(d,'\mb\s+integer\M','b numeric','gi');
  d:=replace(d,$old$(r->>'balance')::integer$old$,$new$(r->>'balance')::numeric$new$);
  if d<>pg_get_functiondef(r.oid) then execute d;changed:=changed+1;end if;
 end loop;
 if changed<10 then raise exception 'Expected balance routines are missing';end if;
end;$$;

-- A distinct name avoids PostgREST ambiguity between numeric/int overloads.
create function private.admin_adjust_credit_amount(p_admin_user_id uuid,p_user_id uuid,p_delta numeric,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b numeric;t public.credit_transactions;
begin
 if not exists(select 1 from public.profiles where id=p_admin_user_id and status='active' and deleted_at is null) then
  return jsonb_build_object('ok',false,'code','ADMIN_REQUIRED');end if;
 if p_delta is null or p_delta='NaN'::numeric or abs(p_delta)>100000 or p_delta=0 or trunc(p_delta,4)<>p_delta then
  return jsonb_build_object('ok',false,'code','CREDIT_DELTA_INVALID');end if;
 if p_idempotency_key is null or length(trim(p_idempotency_key)) not between 8 and 200 then
  return jsonb_build_object('ok',false,'code','IDEMPOTENCY_KEY_INVALID');end if;
 if not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null) then
  return jsonb_build_object('ok',false,'code','USER_NOT_FOUND');end if;
 select balance into b from public.credit_accounts where user_id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'code','USER_NOT_FOUND');end if;
 select * into t from public.credit_transactions where user_id=p_user_id and idempotency_key=p_idempotency_key;
 if found then
  if t.type<>'admin_adjustment' or t.delta<>p_delta or t.metadata->>'admin_user_id' is distinct from p_admin_user_id::text then
   return jsonb_build_object('ok',false,'code','CREDIT_REQUEST_CONFLICT');end if;
  return jsonb_build_object('ok',true,'idempotent',true,'balance',b);
 end if;
 if b+p_delta<0 then return jsonb_build_object('ok',false,'code','CREDITS_BALANCE_INVALID');end if;
 update public.credit_accounts set balance=b+p_delta,total_granted=total_granted+greatest(p_delta,0),updated_at=now() where user_id=p_user_id;
 insert into public.credit_transactions(user_id,type,delta,idempotency_key,metadata)
 values(p_user_id,'admin_adjustment',p_delta,p_idempotency_key,
  jsonb_build_object('reason',coalesce(nullif(left(trim(p_reason),240),''),'管理员调整'),'admin_user_id',p_admin_user_id));
 return jsonb_build_object('ok',true,'idempotent',false,'balance',b+p_delta);
end;$$;
create function public.admin_adjust_credit_amount(p_admin_user_id uuid,p_user_id uuid,p_delta numeric,p_reason text,p_idempotency_key text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.admin_adjust_credit_amount(p_admin_user_id,p_user_id,p_delta,p_reason,p_idempotency_key);
$$;
revoke all on function private.admin_adjust_credit_amount(uuid,uuid,numeric,text,text),public.admin_adjust_credit_amount(uuid,uuid,numeric,text,text) from public,anon,authenticated;
grant execute on function private.admin_adjust_credit_amount(uuid,uuid,numeric,text,text),public.admin_adjust_credit_amount(uuid,uuid,numeric,text,text) to service_role;
