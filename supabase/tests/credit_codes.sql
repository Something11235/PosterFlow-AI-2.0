begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('cc000000-0000-4000-8000-000000000001','codes-admin@example.invalid',now()),
 ('cc000000-0000-4000-8000-000000000002','codes-user@example.invalid',now()),
 ('cc000000-0000-4000-8000-000000000003','codes-other@example.invalid',now()),
 ('cc000000-0000-4000-8000-000000000004','codes-unverified@example.invalid',null);
select public.ensure_signup_bonus(id) from auth.users where id::text like 'cc000000%';
update public.profiles set role='admin' where id='cc000000-0000-4000-8000-000000000001';
do $$
declare a uuid:='cc000000-0000-4000-8000-000000000001';u uuid:='cc000000-0000-4000-8000-000000000002';o uuid:='cc000000-0000-4000-8000-000000000003';
 batch uuid:=gen_random_uuid();b2 uuid;r jsonb;before_balance numeric;before_granted numeric;before_tx bigint;i integer;credits integer;package text;hash text;
begin
 select balance,total_granted into before_balance,before_granted from public.credit_accounts where user_id=u;
 r:=public.create_credit_code_batch(a,batch,'pf20',2,'fixture',repeat('a',64),'encrypted-placeholder',jsonb_build_array(jsonb_build_object('hash',repeat('1',64),'suffix','AAAA'),jsonb_build_object('hash',repeat('2',64),'suffix','BBBB')));
 assert (r->>'ok')::boolean and r#>>'{batch,credits}'='20.0000' and r#>>'{batch,ready}'='2',r::text;
 assert not (r->'batch'?'encrypted_export') and not(r->'batch'?'code_hash');
 assert (select balance from public.credit_accounts where user_id=u)=before_balance;
 r:=public.create_credit_code_batch(a,batch,'pf20',2,'fixture',repeat('a',64),'different-random-encryption','[]');assert (r->>'existing')::boolean;
 assert (select count(*) from public.credit_codes where batch_id=batch)=2;
 r:=public.create_credit_code_batch(a,batch,'pf70',2,'changed',repeat('b',64),'x','[]');assert r->>'code'='CREDIT_BATCH_CONFLICT';
 r:=public.export_credit_code_batch(a,batch);assert jsonb_array_length(r->'ready_hashes')=2 and r->>'encrypted_export'='encrypted-placeholder';
 r:=public.redeem_credit_code(u,repeat('1',64));assert (r->>'ok')::boolean and not(r->>'idempotent')::boolean and (r->>'credits')::numeric=20;
 assert (select balance from public.credit_accounts where user_id=u)=before_balance+20;
 assert (select total_granted from public.credit_accounts where user_id=u)=before_granted+20;
 assert (select count(*) from public.credit_transactions where user_id=u and metadata->>'source'='credit_code')=1;
 before_tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.redeem_credit_code(u,repeat('1',64));assert (r->>'idempotent')::boolean;
 assert (select count(*) from public.credit_transactions where user_id=u)=before_tx;
 r:=public.redeem_credit_code(o,repeat('1',64));assert r->>'code'='CREDIT_CODE_UNAVAILABLE';
 r:=public.credit_code_history(u);assert jsonb_array_length(r->'entries')=1 and r#>>'{entries,0,suffix}'='AAAA';
 assert not(r#>'{entries,0}'?'code_hash') and not(r#>'{entries,0}'?'redeemed_by');
 r:=public.credit_code_history(o);assert jsonb_array_length(r->'entries')=0;
 r:=public.admin_credit_code_batches(a);assert jsonb_array_length(r->'redemptions')=1 and not(r::text like '%encrypted-placeholder%');
 r:=public.export_credit_code_batch(a,batch);assert jsonb_array_length(r->'ready_hashes')=1;
 r:=public.void_credit_code(a,repeat('1',64),'used cannot void');assert r->>'code'='CREDIT_CODE_ALREADY_REDEEMED';
 r:=public.void_credit_code(a,repeat('2',64),'single refund');assert (r->>'voided')::int=1;
 r:=public.void_credit_code(a,repeat('2',64),'single retry');assert (r->>'voided')::int=0;
 r:=public.void_credit_code_batch(a,batch,'fixture void');assert (r->>'voided')::int=0;
 r:=public.void_credit_code_batch(a,batch,'retry');assert (r->>'voided')::int=0;
 r:=public.redeem_credit_code(u,repeat('2',64));assert r->>'code'='CREDIT_CODE_UNAVAILABLE';
 r:=public.redeem_credit_code(u,repeat('1',64));assert (r->>'idempotent')::boolean;
 assert (select balance from public.credit_accounts where user_id=u)=before_balance+20;
 assert (select encrypted_export from public.credit_code_batches where id=batch) is null;
 -- Every fixed denomination is computed by the database, never caller credit input.
 for i in 1..5 loop
  package:=(array['pf20','pf70','pf120','pf200','pf260'])[i];credits:=(array[20,70,120,200,260])[i];b2:=gen_random_uuid();hash:=md5(i::text)||md5((i+10)::text);
  r:=public.create_credit_code_batch(a,b2,package,1,'denomination',repeat('c',64),'encrypted',jsonb_build_array(jsonb_build_object('hash',hash,'suffix','CCCC')));
  assert (r#>>'{batch,credits}')::numeric=credits;
  r:=public.redeem_credit_code(u,hash);assert (r->>'credits')::numeric=credits;
 end loop;
 -- Frozen/unverified users and malformed proofs cannot change money or cards.
 update public.profiles set status='frozen' where id=o;
 r:=public.redeem_credit_code(o,repeat('1',64));assert r->>'code'='ACCOUNT_FROZEN';
 r:=public.redeem_credit_code('cc000000-0000-4000-8000-000000000004',repeat('1',64));assert r->>'code'='EMAIL_UNVERIFIED';
 r:=public.create_credit_code_batch(o,gen_random_uuid(),'pf20',1,'frozen',repeat('a',64),'encrypted','[]');assert r->>'code'='ADMIN_REQUIRED';
 before_tx:=(select count(*) from public.credit_transactions where user_id=u);
 for i in 1..15 loop r:=public.redeem_credit_code(u,'');end loop;
 assert r->>'code'='CREDIT_CODE_RATE_LIMIT' and(select count(*) from public.credit_transactions where user_id=u)=before_tx;
 update private.credit_code_attempts set window_start=now()-interval '11 minutes' where user_id=u;
 r:=public.redeem_credit_code(u,'');assert r->>'code'='CREDIT_CODE_UNAVAILABLE';
 assert (select attempts from private.credit_code_attempts where user_id=u)=1;
 assert not has_table_privilege('anon','public.credit_codes','SELECT');
 assert not has_table_privilege('authenticated','public.credit_code_batches','SELECT');
 assert not has_function_privilege('authenticated','public.redeem_credit_code(uuid,text)','EXECUTE');
 assert not has_function_privilege('anon','public.export_credit_code_batch(uuid,uuid)','EXECUTE');
 assert has_function_privilege('service_role','public.redeem_credit_code(uuid,text)','EXECUTE');
 assert(select relrowsecurity from pg_class where oid='public.credit_codes'::regclass);
end $$;
-- Deliberate ledger failure proves the transaction cannot mark a card used
-- without granting its matching balance and purchase ledger row.
create function pg_temp.reject_credit_code_ledger() returns trigger language plpgsql as $$begin if new.metadata->>'source'='credit_code' then raise exception 'fixture rollback';end if;return new;end;$$;
create trigger fixture_reject_code before insert on public.credit_transactions for each row execute function pg_temp.reject_credit_code_ledger();
do $$
declare a uuid:='cc000000-0000-4000-8000-000000000001';u uuid:='cc000000-0000-4000-8000-000000000002';b uuid:=gen_random_uuid();r jsonb;bal numeric;
begin
 r:=public.create_credit_code_batch(a,b,'pf20',1,'rollback',repeat('d',64),'encrypted','[{"hash":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","suffix":"DDDD"}]');assert (r->>'ok')::boolean;
 select balance into bal from public.credit_accounts where user_id=u;
 begin perform public.redeem_credit_code(u,repeat('f',64));raise exception 'expected failure';exception when others then assert sqlerrm='fixture rollback',sqlerrm;end;
 assert (select balance from public.credit_accounts where user_id=u)=bal;
 assert (select status from public.credit_codes where batch_id=b)='ready';
end $$;
drop trigger fixture_reject_code on public.credit_transactions;
rollback;
