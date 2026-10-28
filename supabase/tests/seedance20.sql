begin;
insert into auth.users(id,email,email_confirmed_at) values('ce000000-0000-4000-8000-000000000001','seedance20-fixture@example.invalid',now());
select public.ensure_signup_bonus('ce000000-0000-4000-8000-000000000001');
update public.credit_accounts set balance=1000,total_spent=0,total_refunded=0 where user_id='ce000000-0000-4000-8000-000000000001';
do $$
declare u uuid:='ce000000-0000-4000-8000-000000000001';o text:='user-'||u::text;
 rid uuid:=gen_random_uuid();r jsonb;before_balance numeric;before_tx bigint;
 p jsonb:='{"model":"seedance-2.0","prompt":"fixture","duration":5,"resolution":"480p","size":"16:9","generate_audio":true,"return_last_frame":false,"nsfw_check":false}';
 refs jsonb:='[{"id":"v","kind":"video","duration_ms":3000,"width":854,"height":480},{"id":"a","kind":"audio","duration_ms":3000}]';
begin
 assert private.seedance20_charge(0.33)=7.5;
 assert private.seedance20_charge(0.71)=16;
 assert private.seedance20_charge(1)=22.5;
 assert private.seedance25_charge(0.48)=11; -- Existing 2.5 20% markup is unchanged.
 r:=public.begin_seedance20_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');
 assert (r->>'ok')::boolean and (r#>>'{job,estimated_credits}')::numeric=7.5 and (r#>>'{job,reserved_credits}')::numeric=12,r::text;
 assert r#>>'{job,pricing_profile,markup}'='1.2';
 assert (r->>'balance')::numeric=988;
 r:=public.begin_seedance20_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');assert (r->>'existing')::boolean;
 assert (select balance from public.credit_accounts where user_id=u)=988;
 r:=public.begin_seedance20_job(o,u,rid,'platform','generate',repeat('b',64),p,'[]');assert r->>'code'='VIDEO_REQUEST_CONFLICT';
 r:=public.apply_seedance20_job('user-other',rid,'completed',null,null,'[]',.33);assert r->>'code'='VIDEO_NOT_FOUND';
 r:=public.apply_seedance20_job(o,rid,'submitted','task_standard_fixture_0001');
 r:=public.apply_seedance20_job(o,rid,'completed');assert r#>>'{job,billing_status}'='awaiting_provider';
 assert (select total_spent from public.credit_accounts where user_id=u)=0;
 r:=public.apply_seedance20_job(o,rid,'completed',null,null,'[]',.33);assert (r#>>'{job,charged_credits}')::numeric=7.5;
 assert (r->>'balance')::numeric=992.5;
 before_tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.apply_seedance20_job(o,rid,'completed',null,null,'[]',.99);
 r:=public.apply_seedance20_job(o,rid,'failed');
 assert (r#>>'{job,charged_credits}')::numeric=7.5;
 assert (select count(*) from public.credit_transactions where user_id=u)=before_tx;
 -- References use the lower video-input rate and add video seconds only.
 rid:=gen_random_uuid();r:=public.begin_seedance20_job(o,u,rid,'platform','generate',repeat('c',64),p,refs);
 assert (r#>>'{job,estimated_credits}')::numeric=7.5 and (r#>>'{job,reserved_credits}')::numeric=11.5,r::text;
 assert (r#>>'{job,reference_duration_ms}')::int=3000;
 before_balance:=(select balance+11.5 from public.credit_accounts where user_id=u);
 r:=public.apply_seedance20_job(o,rid,'failed',null,'VIDEO_REFERENCE_DURATION');
 assert (r->>'balance')::numeric=before_balance;
 before_tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.apply_seedance20_job(o,rid,'failed');assert (select count(*) from public.credit_transactions where user_id=u)=before_tx;
 -- All documented output resolutions; upfront reserve is not the final charge.
 foreach p in array array[p||'{"resolution":"720p"}',p||'{"resolution":"1080p"}',p||'{"resolution":"4k"}'] loop
  rid:=gen_random_uuid();r:=public.begin_seedance20_job(o,u,rid,'platform','generate',repeat('d',64),p,'[]');assert (r->>'ok')::boolean,r::text;
  assert (r#>>'{job,reserved_credits}')::numeric=case p->>'resolution' when '720p' then 25.5 when '1080p' then 63 else 128 end;
  r:=public.apply_seedance20_job(o,rid,'failed');
 end loop;
 p:=p||'{"resolution":"480p"}';
 -- Cost greater than reserve: withhold delivery and settle the same job after topup.
 rid:=gen_random_uuid();r:=public.begin_seedance20_job(o,u,rid,'platform','generate',repeat('e',64),p,'[]');
 update public.credit_accounts set balance=0 where user_id=u;
 r:=public.apply_seedance20_job(o,rid,'completed',null,null,'[]',1);assert r#>>'{job,billing_status}'='awaiting_balance';
 assert (r#>>'{job,charged_credits}')::numeric=0 and (r->>'required_credits')::numeric=10.5;
 r:=public.begin_seedance20_job(o,u,gen_random_uuid(),'platform','generate',repeat('f',64),p,'[]');assert r->>'code'='VIDEO_UNSETTLED_BALANCE';
 update public.credit_accounts set balance=10.5 where user_id=u;
 r:=public.apply_seedance20_job(o,rid,'completed',null,null,'[]',.1); -- Stored actual cost stays 1 USD.
 assert r#>>'{job,billing_status}'='settled' and (r#>>'{job,charged_credits}')::numeric=22.5,r::text;
 assert (select balance from public.credit_accounts where user_id=u)=0;
 rid:=gen_random_uuid();r:=public.begin_seedance20_job(o,u,rid,'own_key','generate',repeat('a',64),p,'[]');assert (r->>'ok')::boolean;
 r:=public.apply_seedance20_job(o,rid,'completed');assert r#>>'{job,billing_status}'='not_applicable' and (r#>>'{job,charged_credits}')::numeric=0;
 -- Invalid inputs never reserve.
 before_tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.begin_seedance20_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),p||'{"prompt":""}','[]');assert not (r->>'ok')::boolean;
 r:=public.begin_seedance20_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),p,'[{"id":"short","kind":"audio","duration_ms":1000}]');assert r->>'code'='VIDEO_REFERENCE_DURATION';
 assert (select count(*) from public.credit_transactions where user_id=u)=before_tx;
 assert not has_function_privilege('anon','public.begin_seedance20_job(text,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE');
 assert not has_function_privilege('authenticated','private.apply_seedance20_job(text,uuid,text,text,text,jsonb,numeric,bigint)','EXECUTE');
 assert has_function_privilege('service_role','public.apply_seedance20_job(text,uuid,text,text,text,jsonb,numeric,bigint)','EXECUTE');
end $$;
rollback;
