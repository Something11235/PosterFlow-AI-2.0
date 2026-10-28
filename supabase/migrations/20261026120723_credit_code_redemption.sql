-- Single-use vouchers; additive only. No old account, order or RPC rewrites.
set local lock_timeout='5s';
create table public.credit_code_batches(
 id uuid primary key,created_by uuid references public.profiles(id) on delete set null,
 package_id text not null check(package_id in ('pf20','pf70','pf120','pf200','pf260')),
 credits numeric(18,4) not null check(credits in (20,70,120,200,260)),
 nominal_amount_fen integer not null check(nominal_amount_fen in (1000,3000,5000,8000,10000)),
 quantity integer not null check(quantity between 1 and 500),note text not null default '' check(length(note)<=240),
 request_fingerprint text not null check(request_fingerprint~'^[a-f0-9]{64}$'),
 encrypted_export text check(length(encrypted_export)<=100000),
 status text not null default 'active' check(status in ('active','voided')),
 created_at timestamptz not null default now(),voided_at timestamptz,void_reason text,
 export_count integer not null default 0,last_exported_at timestamptz,
 check((package_id='pf20' and credits=20 and nominal_amount_fen=1000)
    or(package_id='pf70' and credits=70 and nominal_amount_fen=3000)
    or(package_id='pf120' and credits=120 and nominal_amount_fen=5000)
    or(package_id='pf200' and credits=200 and nominal_amount_fen=8000)
    or(package_id='pf260' and credits=260 and nominal_amount_fen=10000))
);
create table public.credit_codes(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.credit_code_batches(id),
 code_hash text not null unique check(code_hash~'^[a-f0-9]{64}$'),suffix text not null check(suffix~'^[A-Z2-7]{4}$'),
 status text not null default 'ready' check(status in ('ready','redeemed','voided')),
 redeemed_by uuid references public.profiles(id) on delete set null,redeemed_at timestamptz,
 check((status='redeemed' and redeemed_at is not null) or(status<>'redeemed' and redeemed_at is null))
);
create index credit_codes_batch_idx on public.credit_codes(batch_id,status);
create index credit_codes_user_idx on public.credit_codes(redeemed_by,redeemed_at desc) where redeemed_by is not null;
create table public.credit_code_events(
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.credit_code_batches(id),
 code_id uuid references public.credit_codes(id),actor_id uuid references public.profiles(id) on delete set null,
 action text not null check(action in ('create','export','void','redeem')),reason text,
 created_at timestamptz not null default now()
);
create index credit_code_events_batch_idx on public.credit_code_events(batch_id,created_at desc);
create table private.credit_code_attempts(
 user_id uuid primary key references public.profiles(id) on delete cascade,window_start timestamptz not null,attempts integer not null
);
alter table public.credit_code_batches enable row level security;
alter table public.credit_codes enable row level security;
alter table public.credit_code_events enable row level security;
alter table private.credit_code_attempts enable row level security;
revoke all on public.credit_code_batches,public.credit_codes,public.credit_code_events,private.credit_code_attempts from public,anon,authenticated;
grant all on public.credit_code_batches,public.credit_codes,public.credit_code_events,private.credit_code_attempts to service_role;

-- Called exclusively behind the existing require_admin_user guard, which also
-- supports server ADMIN_USER_IDS. No direct browser RPC/table access is granted.
create function private.credit_code_admin_active(p_admin uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=p_admin and status='active' and deleted_at is null);
$$;
create function private.credit_code_batch_public(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',b.id,'package_id',b.package_id,'credits',b.credits,'nominal_amount_fen',b.nominal_amount_fen,
  'quantity',b.quantity,'note',b.note,'status',b.status,'created_at',b.created_at,'export_count',b.export_count,
  'ready',(select count(*) from public.credit_codes c where c.batch_id=b.id and c.status='ready'),
  'redeemed',(select count(*) from public.credit_codes c where c.batch_id=b.id and c.status='redeemed'),
  'voided',(select count(*) from public.credit_codes c where c.batch_id=b.id and c.status='voided'))
 from public.credit_code_batches b where b.id=p_id;
$$;
create function private.credit_code_catalog() returns jsonb
language sql stable security definer set search_path='' as $$select jsonb_build_object('ok',true,'ready',true);$$;

create function private.create_credit_code_batch(p_admin uuid,p_id uuid,p_package text,p_quantity integer,p_note text,p_fingerprint text,p_export text,p_codes jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.credit_code_batches;v_credits integer;v_fen integer;
begin
 if not private.credit_code_admin_active(p_admin) then return jsonb_build_object('ok',false,'code','ADMIN_REQUIRED');end if;
 if p_id is null or p_package is null or p_package not in ('pf20','pf70','pf120','pf200','pf260') or p_quantity is null or p_quantity not between 1 and 500
  or p_note is null or length(p_note)>240 or coalesce(p_fingerprint,'') !~ '^[a-f0-9]{64}$'
  then return jsonb_build_object('ok',false,'code','INVALID_CREDIT_CODE_INPUT');end if;
 perform pg_advisory_xact_lock(hashtextextended('credit-code-batch:'||p_id::text,0));
 select * into b from public.credit_code_batches where id=p_id;
 if found then
  if b.created_by is distinct from p_admin or b.request_fingerprint<>p_fingerprint then return jsonb_build_object('ok',false,'code','CREDIT_BATCH_CONFLICT');end if;
  return jsonb_build_object('ok',true,'existing',true,'batch',private.credit_code_batch_public(b.id));end if;
 if jsonb_typeof(p_codes) is distinct from 'array' or jsonb_array_length(p_codes)<>p_quantity or coalesce(p_export,'')='' or length(p_export)>100000
  then return jsonb_build_object('ok',false,'code','INVALID_CREDIT_CODE_INPUT');end if;
 if exists(select 1 from jsonb_array_elements(p_codes) c where jsonb_typeof(c)<>'object' or c-array['hash','suffix']<>'{}'::jsonb
  or coalesce(c->>'hash','') !~ '^[a-f0-9]{64}$' or coalesce(c->>'suffix','') !~ '^[A-Z2-7]{4}$')
  or(select count(distinct c->>'hash') from jsonb_array_elements(p_codes) c)<>p_quantity
  then return jsonb_build_object('ok',false,'code','INVALID_CREDIT_CODE_INPUT');end if;
 if exists(select 1 from public.credit_codes where code_hash in(select c->>'hash' from jsonb_array_elements(p_codes) c)) then return jsonb_build_object('ok',false,'code','CREDIT_BATCH_CONFLICT');end if;
 v_credits:=case p_package when 'pf20' then 20 when 'pf70' then 70 when 'pf120' then 120 when 'pf200' then 200 else 260 end;
 v_fen:=case p_package when 'pf20' then 1000 when 'pf70' then 3000 when 'pf120' then 5000 when 'pf200' then 8000 else 10000 end;
 insert into public.credit_code_batches(id,created_by,package_id,credits,nominal_amount_fen,quantity,note,request_fingerprint,encrypted_export)
 values(p_id,p_admin,p_package,v_credits,v_fen,p_quantity,p_note,p_fingerprint,p_export);
 insert into public.credit_codes(batch_id,code_hash,suffix) select p_id,c->>'hash',c->>'suffix' from jsonb_array_elements(p_codes) c;
 insert into public.credit_code_events(batch_id,actor_id,action) values(p_id,p_admin,'create');
 return jsonb_build_object('ok',true,'existing',false,'batch',private.credit_code_batch_public(p_id));
end;$$;

create function private.admin_credit_code_batches(p_admin uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not private.credit_code_admin_active(p_admin) then return jsonb_build_object('ok',false,'code','ADMIN_REQUIRED');end if;
 return jsonb_build_object('ok',true,'batches',coalesce((select jsonb_agg(private.credit_code_batch_public(b.id) order by b.created_at desc)
  from(select id,created_at from public.credit_code_batches order by created_at desc limit 100)b),'[]'::jsonb),
  'redemptions',coalesce((select jsonb_agg(to_jsonb(r) order by r.redeemed_at desc) from(
   select c.id,c.batch_id,c.suffix,c.redeemed_by as user_id,p.username,b.package_id,b.credits,c.redeemed_at
   from public.credit_codes c join public.credit_code_batches b on b.id=c.batch_id left join public.profiles p on p.id=c.redeemed_by
   where c.status='redeemed' order by c.redeemed_at desc limit 100)r),'[]'::jsonb));
end;$$;
create function private.export_credit_code_batch(p_admin uuid,p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b public.credit_code_batches;
begin
 if not private.credit_code_admin_active(p_admin) then return jsonb_build_object('ok',false,'code','ADMIN_REQUIRED');end if;
 select * into b from public.credit_code_batches where id=p_id for update;
 if not found or b.status<>'active' or b.encrypted_export is null then return jsonb_build_object('ok',false,'code','CREDIT_BATCH_NOT_FOUND');end if;
 update public.credit_code_batches set export_count=export_count+1,last_exported_at=now() where id=p_id;
 insert into public.credit_code_events(batch_id,actor_id,action) values(p_id,p_admin,'export');
 return jsonb_build_object('ok',true,'encrypted_export',b.encrypted_export,'package_id',b.package_id,
  'ready_hashes',coalesce((select jsonb_agg(code_hash) from public.credit_codes where batch_id=p_id and status='ready'),'[]'::jsonb));
end;$$;
create function private.void_credit_code_batch(p_admin uuid,p_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare b public.credit_code_batches;v_count integer;
begin
 if not private.credit_code_admin_active(p_admin) then return jsonb_build_object('ok',false,'code','ADMIN_REQUIRED');end if;
 if p_reason is null or length(trim(p_reason)) not between 2 and 240 then return jsonb_build_object('ok',false,'code','INVALID_CREDIT_CODE_INPUT');end if;
 select * into b from public.credit_code_batches where id=p_id for update;
 if not found then return jsonb_build_object('ok',false,'code','CREDIT_BATCH_NOT_FOUND');end if;
 if b.status='voided' then return jsonb_build_object('ok',true,'voided',0);end if;
 update public.credit_codes set status='voided' where batch_id=p_id and status='ready';get diagnostics v_count=row_count;
 update public.credit_code_batches set status='voided',voided_at=now(),void_reason=p_reason,encrypted_export=null where id=p_id;
 insert into public.credit_code_events(batch_id,actor_id,action,reason) values(p_id,p_admin,'void',p_reason);
 return jsonb_build_object('ok',true,'voided',v_count);
end;$$;

create function private.redeem_credit_code(p_user_id uuid,p_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.credit_codes;b public.credit_code_batches;v_balance numeric;v_attempt integer;v_batch uuid;
begin
 if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then return jsonb_build_object('ok',false,'code','EMAIL_UNVERIFIED');end if;
 if not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null) then return jsonb_build_object('ok',false,'code','ACCOUNT_FROZEN');end if;
 insert into private.credit_code_attempts(user_id,window_start,attempts) values(p_user_id,now(),1)
 on conflict(user_id) do update set window_start=case when private.credit_code_attempts.window_start<=now()-interval '10 minutes' then now() else private.credit_code_attempts.window_start end,
 attempts=case when private.credit_code_attempts.window_start<=now()-interval '10 minutes' then 1 else private.credit_code_attempts.attempts+1 end returning attempts into v_attempt;
 if v_attempt>12 then return jsonb_build_object('ok',false,'code','CREDIT_CODE_RATE_LIMIT');end if;
 if coalesce(p_hash,'') !~ '^[a-f0-9]{64}$' then return jsonb_build_object('ok',false,'code','CREDIT_CODE_UNAVAILABLE');end if;
 select batch_id into v_batch from public.credit_codes where code_hash=p_hash;
 if not found then return jsonb_build_object('ok',false,'code','CREDIT_CODE_UNAVAILABLE');end if;
 -- Same lock order for redeem/export/void: batch -> card -> account.
 select * into b from public.credit_code_batches where id=v_batch for update;
 select * into c from public.credit_codes where code_hash=p_hash for update;
 if c.status='redeemed' and c.redeemed_by=p_user_id then
  select balance into v_balance from public.credit_accounts where user_id=p_user_id;
  return jsonb_build_object('ok',true,'idempotent',true,'credits',b.credits,'balance',v_balance);end if;
 if b.status<>'active' or c.status<>'ready' then return jsonb_build_object('ok',false,'code','CREDIT_CODE_UNAVAILABLE');end if;
 select balance into v_balance from public.credit_accounts where user_id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'code','ACCOUNT_FROZEN');end if;
 insert into public.credit_transactions(user_id,type,delta,idempotency_key,metadata)
 values(p_user_id,'purchase',b.credits,'credit-code:'||c.id::text,
  jsonb_build_object('source','credit_code','batch_id',b.id,'code_id',c.id,'package_id',b.package_id,'nominal_amount_fen',b.nominal_amount_fen));
 update public.credit_accounts set balance=balance+b.credits,total_granted=total_granted+b.credits,updated_at=now()
  where user_id=p_user_id returning balance into v_balance;
 update public.credit_codes set status='redeemed',redeemed_by=p_user_id,redeemed_at=now() where id=c.id;
 insert into public.credit_code_events(batch_id,code_id,actor_id,action) values(b.id,c.id,p_user_id,'redeem');
 return jsonb_build_object('ok',true,'idempotent',false,'credits',b.credits,'balance',v_balance);
end;$$;
create function private.credit_code_history(p_user_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('ok',true,'entries',coalesce((select jsonb_agg(to_jsonb(r) order by r.redeemed_at desc) from(
  select c.id,c.suffix,b.credits,b.package_id,c.redeemed_at from public.credit_codes c join public.credit_code_batches b on b.id=c.batch_id
  where c.redeemed_by=p_user_id order by c.redeemed_at desc limit 30)r),'[]'::jsonb));
$$;

create function public.credit_code_catalog() returns jsonb language sql security invoker set search_path='' as $$select private.credit_code_catalog();$$;
revoke all on function private.credit_code_catalog() from public,anon,authenticated;
grant execute on function private.credit_code_catalog() to service_role;
revoke all on function public.credit_code_catalog() from public,anon,authenticated;
grant execute on function public.credit_code_catalog() to service_role;

create function public.create_credit_code_batch(p_admin uuid,p_id uuid,p_package text,p_quantity integer,p_note text,p_fingerprint text,p_export text,p_codes jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.create_credit_code_batch(p_admin,p_id,p_package,p_quantity,p_note,p_fingerprint,p_export,p_codes);$$;
revoke all on function private.create_credit_code_batch(uuid,uuid,text,integer,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function private.create_credit_code_batch(uuid,uuid,text,integer,text,text,text,jsonb) to service_role;
revoke all on function public.create_credit_code_batch(uuid,uuid,text,integer,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_credit_code_batch(uuid,uuid,text,integer,text,text,text,jsonb) to service_role;

create function public.admin_credit_code_batches(p_admin uuid) returns jsonb language sql security invoker set search_path='' as $$select private.admin_credit_code_batches(p_admin);$$;
revoke all on function private.admin_credit_code_batches(uuid) from public,anon,authenticated;
grant execute on function private.admin_credit_code_batches(uuid) to service_role;
revoke all on function public.admin_credit_code_batches(uuid) from public,anon,authenticated;
grant execute on function public.admin_credit_code_batches(uuid) to service_role;

create function public.export_credit_code_batch(p_admin uuid,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.export_credit_code_batch(p_admin,p_id);$$;
revoke all on function private.export_credit_code_batch(uuid,uuid) from public,anon,authenticated;
grant execute on function private.export_credit_code_batch(uuid,uuid) to service_role;
revoke all on function public.export_credit_code_batch(uuid,uuid) from public,anon,authenticated;
grant execute on function public.export_credit_code_batch(uuid,uuid) to service_role;

create function public.void_credit_code_batch(p_admin uuid,p_id uuid,p_reason text) returns jsonb language sql security invoker set search_path='' as $$select private.void_credit_code_batch(p_admin,p_id,p_reason);$$;
revoke all on function private.void_credit_code_batch(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.void_credit_code_batch(uuid,uuid,text) to service_role;
revoke all on function public.void_credit_code_batch(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.void_credit_code_batch(uuid,uuid,text) to service_role;

create function public.redeem_credit_code(p_user_id uuid,p_hash text) returns jsonb language sql security invoker set search_path='' as $$select private.redeem_credit_code(p_user_id,p_hash);$$;
revoke all on function private.redeem_credit_code(uuid,text) from public,anon,authenticated;
grant execute on function private.redeem_credit_code(uuid,text) to service_role;
revoke all on function public.redeem_credit_code(uuid,text) from public,anon,authenticated;
grant execute on function public.redeem_credit_code(uuid,text) to service_role;

create function public.credit_code_history(p_user_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.credit_code_history(p_user_id);$$;
revoke all on function private.credit_code_history(uuid) from public,anon,authenticated;
grant execute on function private.credit_code_history(uuid) to service_role;
revoke all on function public.credit_code_history(uuid) from public,anon,authenticated;
grant execute on function public.credit_code_history(uuid) to service_role;
revoke all on function private.credit_code_admin_active(uuid) from public,anon,authenticated;
grant execute on function private.credit_code_admin_active(uuid) to service_role;
revoke all on function private.credit_code_batch_public(uuid) from public,anon,authenticated;
grant execute on function private.credit_code_batch_public(uuid) to service_role;

create function private.void_credit_code(p_admin uuid,p_hash text,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.credit_codes;v_batch uuid;
begin
 if not private.credit_code_admin_active(p_admin) then return jsonb_build_object('ok',false,'code','ADMIN_REQUIRED');end if;
 if coalesce(p_hash,'') !~ '^[a-f0-9]{64}$' or p_reason is null or length(trim(p_reason)) not between 2 and 240 then return jsonb_build_object('ok',false,'code','INVALID_CREDIT_CODE_INPUT');end if;
 select batch_id into v_batch from public.credit_codes where code_hash=p_hash;
 if not found then return jsonb_build_object('ok',false,'code','CREDIT_CODE_UNAVAILABLE');end if;
 perform 1 from public.credit_code_batches where id=v_batch for update;
 select * into c from public.credit_codes where code_hash=p_hash for update;
 if c.status='redeemed' then return jsonb_build_object('ok',false,'code','CREDIT_CODE_ALREADY_REDEEMED');end if;
 if c.status='voided' then return jsonb_build_object('ok',true,'voided',0);end if;
 update public.credit_codes set status='voided' where id=c.id;
 insert into public.credit_code_events(batch_id,code_id,actor_id,action,reason) values(c.batch_id,c.id,p_admin,'void',p_reason);
 return jsonb_build_object('ok',true,'voided',1);
end;$$;
create function public.void_credit_code(p_admin uuid,p_hash text,p_reason text) returns jsonb
language sql security invoker set search_path='' as $$select private.void_credit_code(p_admin,p_hash,p_reason);$$;
revoke all on function private.void_credit_code(uuid,text,text),public.void_credit_code(uuid,text,text) from public,anon,authenticated;
grant execute on function private.void_credit_code(uuid,text,text),public.void_credit_code(uuid,text,text) to service_role;
