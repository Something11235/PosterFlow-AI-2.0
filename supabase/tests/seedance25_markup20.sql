-- Offline fixtures only; never execute this file on a cloud database.
begin;
insert into auth.users(id,email,email_confirmed_at) values('abababab-7777-4777-8777-777777777777','seedance25@example.invalid',now());
select public.ensure_signup_bonus('abababab-7777-4777-8777-777777777777');
update public.credit_accounts set balance=1000,total_spent=0,total_refunded=0 where user_id='abababab-7777-4777-8777-777777777777';
create function pg_temp.begin25(rid uuid,p jsonb,refs jsonb default '[]',own boolean default false) returns jsonb language sql as $$
 select public.begin_seedance25_job('user-abababab-7777-4777-8777-777777777777'||case when own then '-'||repeat('f',64) else '' end,
 'abababab-7777-4777-8777-777777777777',rid,case when own then 'own_key' else 'platform' end,'generate',repeat('a',64),p,refs);
$$;
do $$
declare u uuid:='abababab-7777-4777-8777-777777777777';o text:='user-'||u::text;rid uuid:=gen_random_uuid();draft uuid;
 p jsonb:='{"model":"seedance-2.5","prompt":"fixture","resolution":"480p","duration":5,"size":"adaptive","draft":false}';
 r jsonb;b numeric;before_balance numeric;refs jsonb:='[{"id":"v","kind":"video","duration_ms":3000,"width":854,"height":480,"fps":30,"codec":"avc1","size":3000},{"id":"a","kind":"audio","duration_ms":3000,"size":48044}]';
begin
 r:=pg_temp.begin25(rid,p);assert (r->>'ok')::boolean,r::text;
 assert (r#>>'{job,estimated_credits}')::numeric=11 and (r#>>'{job,reserved_credits}')::numeric=17;
 assert (r->>'balance')::numeric=983;
 r:=pg_temp.begin25(rid,p);assert (r->>'existing')::boolean;
 r:=public.apply_seedance25_job(o,rid,'submitted','task_seedance25_fixture_001');
 r:=public.apply_seedance25_job(o,rid,'completed');assert r#>>'{job,billing_status}'='awaiting_provider';
 assert (select balance from public.credit_accounts where user_id=u)=983;
 r:=public.apply_seedance25_job(o,rid,'completed',null,null,'[]',0.48,48000);
 assert r#>>'{job,billing_status}'='settled' and (r#>>'{job,charged_credits}')::numeric=11;
 assert (r->>'balance')::numeric=989;
 r:=public.apply_seedance25_job(o,rid,'completed',null,null,'[]',99,48000);
 assert (select balance from public.credit_accounts where user_id=u)=989;
 assert (select total_spent from public.credit_accounts where user_id=u)=11;
 assert (select total_refunded from public.credit_accounts where user_id=u)=6;
 rid:=gen_random_uuid();r:=pg_temp.begin25(rid,p,refs);assert (r#>>'{job,reserved_credits}')::numeric=16.5;
 assert (r#>>'{job,reference_duration_ms}')::integer=3000;
 r:=public.apply_seedance25_job(o,rid,'submission_unknown');assert r#>>'{job,billing_status}'='reserved';
 r:=public.apply_seedance25_job(o,rid,'failed');r:=public.apply_seedance25_job(o,rid,'failed');
 assert (select balance from public.credit_accounts where user_id=u)=989;
 -- A completed draft is charged separately; final inherits duration, not reference seconds.
 draft:=gen_random_uuid();r:=pg_temp.begin25(draft,p||'{"draft":true}',refs);
 r:=public.apply_seedance25_job(o,draft,'submitted','task_seedance25_draft_001');
 r:=public.apply_seedance25_job(o,draft,'completed',null,null,'[]',0.4,40000);assert (r#>>'{job,charged_credits}')::numeric=9;
 rid:=gen_random_uuid();r:=pg_temp.begin25(rid,jsonb_build_object('model','seedance-2.5','resolution','1080p','draft_request_id',draft));
 assert (r->>'ok')::boolean,r::text;assert (r#>>'{job,reference_duration_ms}')::integer=0;
 assert (r#>>'{job,requested_duration}')::integer=5 and (r#>>'{job,reserved_credits}')::numeric=95;
 r:=public.apply_seedance25_job(o,rid,'completed',null,null,'[]',2.67,242727);assert (r#>>'{job,charged_credits}')::numeric=59.5;
 update public.video_jobs set created_at=now()-interval '8 days' where request_id=draft;
 r:=pg_temp.begin25(gen_random_uuid(),jsonb_build_object('model','seedance-2.5','resolution','1080p','draft_request_id',draft));assert r->>'code'='VIDEO_DRAFT_INVALID';
 r:=pg_temp.begin25(gen_random_uuid(),jsonb_build_object('model','seedance-2.5','resolution','1080p','draft_request_id',draft),'[]',true);assert r->>'code'='VIDEO_DRAFT_INVALID';
 select balance into b from public.credit_accounts where user_id=u;
 rid:=gen_random_uuid();r:=pg_temp.begin25(rid,p,'[]',true);
 r:=public.apply_seedance25_job(o||'-'||repeat('f',64),rid,'completed');assert r#>>'{job,billing_status}'='not_applicable';
 assert (select balance from public.credit_accounts where user_id=u)=b;
 r:=pg_temp.begin25(gen_random_uuid(),p||'{"price":0}');assert r->>'code'='INVALID_VIDEO_INPUT';
 -- Unexpected cost over the reservation is held for settlement; no free output or duplicate debit.
 rid:=gen_random_uuid();r:=pg_temp.begin25(rid,p);
 update public.credit_accounts set balance=0 where user_id=u;
 r:=public.apply_seedance25_job(o,rid,'completed',null,null,'[]',2,200000);assert r#>>'{job,billing_status}'='awaiting_balance';
 assert (r->>'final_credits')::numeric=44.5;
 r:=pg_temp.begin25(gen_random_uuid(),p);assert r->>'code'='VIDEO_UNSETTLED_BALANCE';
 update public.credit_accounts set balance=30 where user_id=u;
 r:=public.apply_seedance25_job(o,rid,'completed',null,null,'[]',9,900000);
 assert (r#>>'{job,charged_credits}')::numeric=44.5 and (r->>'balance')::numeric=2.5;
 r:=public.apply_seedance25_job(o,rid,'completed',null,null,'[]',9,900000);assert (select balance from public.credit_accounts where user_id=u)=2.5;
 assert not has_function_privilege('anon','public.begin_seedance25_job(text,uuid,uuid,text,text,text,jsonb,jsonb)','execute');
 assert not has_function_privilege('authenticated','public.apply_seedance25_job(text,uuid,text,text,text,jsonb,numeric,bigint)','execute');
 assert has_function_privilege('service_role','public.apply_seedance25_job(text,uuid,text,text,text,jsonb,numeric,bigint)','execute');
end;$$;
rollback;
