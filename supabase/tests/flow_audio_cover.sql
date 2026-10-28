begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('77777777-7777-4777-8777-777777777777','flow-fixture@example.invalid',now());
select public.ensure_signup_bonus('77777777-7777-4777-8777-777777777777');
update public.credit_accounts set balance=100 where user_id='77777777-7777-4777-8777-777777777777';
create function pg_temp.flow_request(n integer) returns uuid language sql as $$
 select ('77777777-7777-4777-8777-'||lpad(n::text,12,'0'))::uuid;
$$;
create function pg_temp.begin_flow_fixture(n integer,mode text default 'platform') returns jsonb language sql as $$
 select public.begin_flow_cover_job(
  'user-77777777-7777-4777-8777-777777777777'||case when mode='own_key' then '-'||repeat('e',64) else '' end,
  '77777777-7777-4777-8777-777777777777',pg_temp.flow_request(n),mode,'lyria-3.5',repeat('a',64),
  'Flow 音频改编：jazz','{"model":"flowmusic","version":"lyria-3.5","operation":"flow_cover","prompt":"jazz","strength":"0"}');
$$;
do $$
declare r jsonb; owner text:='user-77777777-7777-4777-8777-777777777777';req uuid;balance_before int;spent_before int;ledger_count int;
begin
 r:=pg_temp.begin_flow_fixture(1);req:=pg_temp.flow_request(1);
 assert (r->>'ok')::boolean and r#>>'{job,flow_stage}'='importing';
 assert (r->>'balance')::numeric=98 and r#>>'{job,reserved_credits}'='2';
 assert r#>>'{job,history_parameters,strength}'='0';
 r:=pg_temp.begin_flow_fixture(1);assert (r->>'existing')::boolean;
 perform public.apply_music_job(owner,req,'submitted','task_flow_import_0001');
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_0001','claim_cover');
 assert (r->>'claimed')::boolean and r#>>'{job,flow_stage}'='cover_submitting';
 assert r#>>'{job,provider_task_id}' is null and r#>>'{job,flow_import_task_id}'='task_flow_import_0001';
 assert (r#>>'{parameters,strength}')::numeric=0 and r#>>'{parameters,version}'='lyria-3.5';
 assert (r->'parameters')-array['model','version','instruction','strength']='{}'::jsonb;
 assert r#>>'{job,billing_status}'='reserved' and r#>>'{job,generated_count}'='0';
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_0001','claim_cover');assert not (r->>'claimed')::boolean;
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_0001','import_failed');assert r#>>'{job,billing_status}'='reserved';
 r:=public.advance_flow_cover_job('other-owner',req,'task_flow_import_0001','claim_cover');assert r->>'code'='MUSIC_NOT_FOUND';
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_0001','cover_submitted','task_flow_cover_0001');
 assert r#>>'{job,flow_stage}'='generating' and r#>>'{job,provider_task_id}'='task_flow_cover_0001';
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_0001','import_progress');assert r#>>'{job,provider_task_id}'='task_flow_cover_0001';
 r:=public.apply_music_job(owner,req,'completed',null,1);
 assert r#>>'{job,charged_credits}'='2' and r#>>'{job,generated_count}'='1' and (r->>'balance')::numeric=98;
 select count(*) into ledger_count from public.credit_transactions where user_id='77777777-7777-4777-8777-777777777777';
 perform public.apply_music_job(owner,req,'completed',null,2);
 perform public.advance_flow_cover_job(owner,req,'task_flow_import_0001','cover_rejected');
 assert ledger_count=(select count(*) from public.credit_transactions where user_id='77777777-7777-4777-8777-777777777777');

 -- Import failure and cover rejection refund the single reservation once.
 for n in 2..3 loop
  perform pg_temp.begin_flow_fixture(n);req:=pg_temp.flow_request(n);
  perform public.apply_music_job(owner,req,'submitted','task_flow_import_fixture_'||n::text);
  if n=2 then
   r:=public.advance_flow_cover_job(owner,req,'task_flow_import_fixture_'||n::text,'import_failed',null,'MUSIC_AUDIO_INVALID');
  else
   perform public.advance_flow_cover_job(owner,req,'task_flow_import_fixture_'||n::text,'claim_cover');
   r:=public.advance_flow_cover_job(owner,req,'task_flow_import_fixture_'||n::text,'cover_rejected',null,'MUSIC_CONTENT_REJECTED');
  end if;
  assert r#>>'{job,billing_status}'='refunded' and (r->>'balance')::numeric=98;
  perform public.advance_flow_cover_job(owner,req,'task_flow_import_fixture_'||n::text,'import_failed');
  assert (select balance from public.credit_accounts where user_id='77777777-7777-4777-8777-777777777777')=98;
 end loop;

 -- Unknown cover never reclaims, refunds or falls back to the import result.
 perform pg_temp.begin_flow_fixture(4);req:=pg_temp.flow_request(4);
 perform public.apply_music_job(owner,req,'submitted','task_flow_import_unknown');
 perform public.advance_flow_cover_job(owner,req,'task_flow_import_unknown','claim_cover');
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_unknown','cover_unknown');
 assert r#>>'{job,status}'='submission_unknown' and r#>>'{job,billing_status}'='reserved';
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_unknown','claim_cover');assert not (r->>'claimed')::boolean;

 -- Expired history fails before cover and refunds without retaining extra text.
 perform pg_temp.begin_flow_fixture(5);req:=pg_temp.flow_request(5);
 perform public.apply_music_job(owner,req,'submitted','task_flow_import_expired');
 update public.music_jobs set history_prompt='',history_parameters=null,history_created_at=null where request_id=req;
 r:=public.advance_flow_cover_job(owner,req,'task_flow_import_expired','claim_cover');
 assert r#>>'{job,status}'='failed' and r#>>'{job,error_code}'='MUSIC_FLOW_SOURCE_EXPIRED';
 assert not (r->>'claimed')::boolean and r#>>'{job,billing_status}'='refunded';

 -- Own-key flow records a task without modifying website money.
 select balance,total_spent into balance_before,spent_before from public.credit_accounts where user_id='77777777-7777-4777-8777-777777777777';
 r:=pg_temp.begin_flow_fixture(6,'own_key');assert r#>>'{job,reserved_credits}'='0';
 owner:=owner||'-'||repeat('e',64);req:=pg_temp.flow_request(6);
 perform public.apply_music_job(owner,req,'submitted','task_flow_import_ownkey');
 perform public.advance_flow_cover_job(owner,req,'task_flow_import_ownkey','claim_cover');
 perform public.advance_flow_cover_job(owner,req,'task_flow_import_ownkey','cover_submitted','task_flow_cover_ownkey');
 r:=public.apply_music_job(owner,req,'completed',null,1);assert r#>>'{job,charged_credits}'='0';
 assert (select balance=balance_before and total_spent=spent_before from public.credit_accounts where user_id='77777777-7777-4777-8777-777777777777');
 assert not has_function_privilege('anon','public.begin_flow_cover_job(text,uuid,uuid,text,text,text,text,jsonb)','execute');
 assert not has_function_privilege('authenticated','public.advance_flow_cover_job(text,uuid,text,text,text,text)','execute');
 assert has_function_privilege('service_role','public.advance_flow_cover_job(text,uuid,text,text,text,text)','execute');
 assert (select relrowsecurity from pg_class where oid='public.music_jobs'::regclass);
 assert not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.proname in ('begin_flow_cover_job','advance_flow_cover_job') and n.nspname in ('public','private')
  and (p.prosecdef is distinct from (n.nspname='private') or not ('search_path=""'=any(p.proconfig))));
end;
$$;
set local role anon;
do $$ begin
 perform public.advance_flow_cover_job('owner','77777777-7777-4777-8777-000000000001','task_flow_import_fixture','claim_cover');
 raise exception 'Anonymous RPC execution was unexpectedly allowed';
exception when insufficient_privilege then null;end;$$;
reset role;
set local role authenticated;
do $$ begin
 perform public.begin_flow_cover_job('owner',null,'77777777-7777-4777-8777-000000000001','own_key','lyria-3.5',repeat('a',64),'test','{}');
 raise exception 'Authenticated RPC execution was unexpectedly allowed';
exception when insufficient_privilege then null;end;$$;
reset role;
set local role service_role;
select public.begin_flow_cover_job('user-77777777-7777-4777-8777-777777777777',
 '77777777-7777-4777-8777-777777777777','77777777-7777-4777-8777-000000000007','platform','lyria-3.5',repeat('b',64),
 'Flow 音频改编：jazz','{"model":"flowmusic","version":"lyria-3.5","operation":"flow_cover","prompt":"jazz","strength":"0.5"}');
reset role;
rollback;
