begin;
insert into auth.users(id,email,email_confirmed_at) values('cd000000-0000-4000-8000-000000000001','h3-fixture@example.invalid',now());
select public.ensure_signup_bonus('cd000000-0000-4000-8000-000000000001');
update public.credit_accounts set balance=1000,total_spent=0,total_refunded=0 where user_id='cd000000-0000-4000-8000-000000000001';
do $$
declare u uuid:='cd000000-0000-4000-8000-000000000001';o text:='user-'||u::text;rid uuid:=gen_random_uuid();r jsonb;tx bigint;b numeric;x jsonb;
 p jsonb:='{"model":"MiniMax-H3","prompt":"fixture","resolution":"2k","duration":5,"size":"16:9","watermark":false,"nsfw_check":false}';
 img jsonb:='{"id":"i","kind":"image","size":1024,"width":256,"height":384}';
 vid jsonb:='{"id":"v","kind":"video","size":1024,"width":854,"height":480,"duration_ms":3000,"fps":24,"codec":"avc1","audio_codecs":["mp4a"]}';
 refs jsonb;
begin
 assert private.minimax_h3_charge(.2856)=6.5 and private.minimax_h3_charge(.4572)=10.5;
 assert private.minimax_h3_charge(1)=22.5;
 r:=public.begin_minimax_h3_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');
 assert (r->>'ok')::boolean and (r#>>'{job,estimated_credits}')::numeric=10.5 and (r#>>'{job,reserved_credits}')::numeric=16.5,r::text;
 assert r#>>'{job,pricing_profile,markup}'='1.2' and (r->>'balance')::numeric=983.5;
 r:=public.begin_minimax_h3_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');assert (r->>'existing')::boolean;
 assert (select balance from public.credit_accounts where user_id=u)=983.5;
 r:=public.begin_minimax_h3_job(o,u,rid,'platform','generate',repeat('b',64),p,'[]');assert r->>'code'='VIDEO_REQUEST_CONFLICT';
 r:=public.apply_omni_flash_job(o,rid,'completed',null,null,'[]',.4572);assert r->>'code'='VIDEO_NOT_FOUND';
 r:=public.apply_minimax_h3_job('other-owner',rid,'completed',null,null,'[]',.4572);assert r->>'code'='VIDEO_NOT_FOUND';
 r:=public.apply_minimax_h3_job(o,rid,'submitted','task_h3_fixture');
 r:=public.apply_minimax_h3_job(o,rid,'completed');assert r#>>'{job,billing_status}'='awaiting_provider';
 assert (select total_spent from public.credit_accounts where user_id=u)=0;
 r:=public.apply_minimax_h3_job(o,rid,'completed',null,null,'[]',.4572);assert (r#>>'{job,charged_credits}')::numeric=10.5 and (r->>'balance')::numeric=989.5;
 tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.apply_minimax_h3_job(o,rid,'completed',null,null,'[]',100);
 r:=public.apply_minimax_h3_job(o,rid,'failed');assert (r#>>'{job,charged_credits}')::numeric=10.5;
 assert (select count(*) from public.credit_transactions where user_id=u)=tx;
 -- Each generation includes input-video seconds and only images after the fifth.
 refs:=jsonb_build_array(vid);
 for i in 1..9 loop refs:=refs||jsonb_build_array(img||jsonb_build_object('id','image-'||i));end loop;
 rid:=gen_random_uuid();r:=public.begin_minimax_h3_job(o,u,rid,'platform','generate',repeat('c',64),p||'{"resolution":"768p"}',refs);
 assert (r#>>'{job,estimated_credits}')::numeric=12.5 and (r#>>'{job,reference_duration_ms}')::integer=3000,r::text;
 r:=public.apply_minimax_h3_job(o,rid,'submission_unknown');assert r#>>'{job,billing_status}'='reserved';
 r:=public.apply_minimax_h3_job(o,rid,'failed',null,'VIDEO_PROVIDER_BUSY');assert r#>>'{job,billing_status}'='refunded';
 tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.apply_minimax_h3_job(o,rid,'failed');assert (select count(*) from public.credit_transactions where user_id=u)=tx;
 b:=(select balance from public.credit_accounts where user_id=u);
 -- Invalid requests return before any funds are reserved.
 for x in select value from jsonb_array_elements('[{"prompt":""},{"duration":3},{"duration":16},{"duration":"5"},{"resolution":"720p"},{"generate_audio":true},{"seed":1}]') loop
  r:=public.begin_minimax_h3_job(o,u,gen_random_uuid(),'platform','generate',repeat('d',64),p||x,'[]');assert r->>'code'='INVALID_VIDEO_INPUT',r::text;
 end loop;
 for refs in select value from jsonb_array_elements(jsonb_build_array(
   '[1]'::jsonb,jsonb_build_array(img||'{"size":31457281}'),jsonb_build_array(img||'{"width":255}'),
   jsonb_build_array(vid||'{"fps":12}'),jsonb_build_array(vid||'{"audio_codecs":["opus"]}'),
   jsonb_build_array(vid||'{"duration_ms":1999}'),
   jsonb_build_array(img||'{"role":"first_frame"}',vid),
   jsonb_build_array(img||'{"role":"last_frame"}',img||'{"id":"b"}'),
   '[{"id":"a","kind":"audio","size":1024,"duration_ms":3000}]'::jsonb,
   jsonb_build_array(vid||'{"duration_ms":8000}',vid||'{"id":"b","duration_ms":8000}')
 )) loop
  r:=public.begin_minimax_h3_job(o,u,gen_random_uuid(),'platform','generate',repeat('e',64),p,refs);assert not (r->>'ok')::boolean,r::text;
 end loop;
 assert (select balance from public.credit_accounts where user_id=u)=b and (select count(*) from public.credit_transactions where user_id=u)=tx;
 rid:=gen_random_uuid();r:=public.begin_minimax_h3_job(o,u,rid,'platform','generate',repeat('f',64),p,'[]');
 update public.credit_accounts set balance=0 where user_id=u;
 r:=public.apply_minimax_h3_job(o,rid,'completed',null,null,'[]',1);assert r#>>'{job,billing_status}'='awaiting_balance' and (r->>'required_credits')::numeric=6;
 r:=public.begin_minimax_h3_job(o,u,gen_random_uuid(),'platform','generate',repeat('e',64),p,'[]');assert r->>'code'='VIDEO_UNSETTLED_BALANCE';
 update public.credit_accounts set balance=6 where user_id=u;
 r:=public.apply_minimax_h3_job(o,rid,'completed',null,null,'[]',.1);assert r#>>'{job,billing_status}'='settled' and (r#>>'{job,charged_credits}')::numeric=22.5;
 rid:=gen_random_uuid();r:=public.begin_minimax_h3_job(o||'-'||repeat('a',64),u,rid,'own_key','generate',repeat('a',64),p,'[]');assert (r->>'ok')::boolean;
 r:=public.apply_minimax_h3_job(o||'-'||repeat('a',64),rid,'completed');assert r#>>'{job,billing_status}'='not_applicable' and (r#>>'{job,charged_credits}')::numeric=0;
 assert not has_function_privilege('anon','public.begin_minimax_h3_job(text,uuid,uuid,text,text,text,jsonb,jsonb)','EXECUTE');
 assert not has_function_privilege('authenticated','private.apply_minimax_h3_job(text,uuid,text,text,text,jsonb,numeric,bigint)','EXECUTE');
 assert has_function_privilege('service_role','public.apply_minimax_h3_job(text,uuid,text,text,text,jsonb,numeric,bigint)','EXECUTE');
end $$;
rollback;
