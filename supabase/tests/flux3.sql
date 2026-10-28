begin;
insert into auth.users(id,email,email_confirmed_at) values('cf000000-0000-4000-8000-000000000001','flux-fixture@example.invalid',now());
select public.ensure_signup_bonus('cf000000-0000-4000-8000-000000000001');
update public.credit_accounts set balance=1000,total_spent=0,total_refunded=0 where user_id='cf000000-0000-4000-8000-000000000001';
do $$
declare u uuid:='cf000000-0000-4000-8000-000000000001';o text:='user-'||u::text;rid uuid:=gen_random_uuid();draft_rid uuid;final_rid uuid;r jsonb;tx bigint;b numeric;bad jsonb;
 p jsonb:='{"model":"flux-3-video","prompt":"fixture","resolution":"hd","duration":5,"aspect_ratio":"auto","draft":false,"audio":true,"safety_tolerance":2,"nsfw_check":false}';
 img jsonb:='{"id":"image.png","kind":"image","size":1024,"width":128,"height":128}';
 vid jsonb:='{"id":"video.mp4","kind":"video","size":1024,"width":854,"height":480,"duration_ms":3000,"fps":12,"codec":"avc1"}';
begin
 assert private.flux3_charge(.24)=5.5 and private.flux3_charge(.68)=15.5 and private.flux3_charge(1.16)=26;
 r:=public.begin_flux3_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');
 assert (r->>'ok')::boolean and (r#>>'{job,estimated_credits}')::numeric=15.5 and (r#>>'{job,reserved_credits}')::numeric=24.5,r::text;
 assert r#>>'{job,pricing_profile,markup}'='1.2';
 r:=public.begin_flux3_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');assert (r->>'existing')::boolean;
 assert (select balance from public.credit_accounts where user_id=u)=975.5;
 r:=public.begin_flux3_job(o,u,rid,'platform','generate',repeat('b',64),p,'[]');assert r->>'code'='VIDEO_REQUEST_CONFLICT';
 r:=public.apply_wan30_job(o,rid,'completed',null,null,'[]',.68);assert r->>'code'='VIDEO_NOT_FOUND';
 r:=public.apply_flux3_job('other-owner',rid,'completed',null,null,'[]',.68);assert r->>'code'='VIDEO_NOT_FOUND';
 r:=public.apply_flux3_job(o,rid,'submitted','task_flux_fixture');
 r:=public.apply_flux3_job(o,rid,'completed');assert r#>>'{job,billing_status}'='awaiting_provider';
 assert (select total_spent from public.credit_accounts where user_id=u)=0;
 r:=public.apply_flux3_job(o,rid,'completed',null,null,'[]',.68);assert (r#>>'{job,charged_credits}')::numeric=15.5 and (r->>'balance')::numeric=984.5;
 tx:=(select count(*) from public.credit_transactions where user_id=u);
 r:=public.apply_flux3_job(o,rid,'completed',null,null,'[]',100);r:=public.apply_flux3_job(o,rid,'failed');
 assert (select count(*) from public.credit_transactions where user_id=u)=tx;
 -- Repeated, ordered keyframes are allowed and stored without sorting or deduping.
 rid:=gen_random_uuid();r:=public.begin_flux3_job(o,u,rid,'platform','generate',repeat('a',64),p,jsonb_build_array(img,img));
 assert (r->>'ok')::boolean and jsonb_array_length(r#>'{job,reference_metadata}')=2,r::text;
 r:=public.apply_flux3_job(o,rid,'failed');
 -- A continuation draft has its own rate, and finalization retains that mode.
 draft_rid:=gen_random_uuid();r:=public.begin_flux3_job(o,u,draft_rid,'platform','generate',repeat('a',64),p||'{"draft":true}',jsonb_build_array(vid));
 assert (r#>>'{job,estimated_credits}')::numeric=11 and (r#>>'{job,reserved_credits}')::numeric=17 and (r#>>'{job,is_draft}')::boolean,r::text;
 r:=public.apply_flux3_job(o,draft_rid,'submitted','task_flux_draft');r:=public.apply_flux3_job(o,draft_rid,'completed',null,null,'[]',.48);
 assert (r#>>'{job,charged_credits}')::numeric=11;
 final_rid:=gen_random_uuid();bad:=jsonb_build_object('model','flux-3-video','resolution','fhd','draft_request_id',draft_rid);
 r:=public.begin_flux3_job(o,u,final_rid,'platform','generate',repeat('a',64),bad,'[]');
 assert (r#>>'{job,estimated_credits}')::numeric=47 and (r#>>'{job,reserved_credits}')::numeric=75,r::text;
 assert (r#>>'{job,draft_source_id}')::uuid=(select id from public.video_jobs where request_id=draft_rid);
 r:=public.apply_flux3_job(o,final_rid,'submitted','task_flux_final');r:=public.apply_flux3_job(o,final_rid,'completed',null,null,'[]',2.12);
 assert (r#>>'{job,charged_credits}')::numeric=47;
 assert (select charged_credits from public.video_jobs where request_id=draft_rid)=11;
 for bad in select value from jsonb_array_elements(jsonb_build_array(p||'{"duration":4}',p||'{"duration":21}',p||'{"safety_tolerance":5}',p||'{"safety_tolerance":true}',p||'{"draft":true,"resolution":"fhd"}',p||'{"seed":1}',p||'{"audio":"false"}',p||'{"prompt":""}')) loop
  b:=(select balance from public.credit_accounts where user_id=u);
  r:=public.begin_flux3_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),bad,'[]');assert not(r->>'ok')::boolean,r::text;
  assert (select balance from public.credit_accounts where user_id=u)=b;
 end loop;
 for bad in select value from jsonb_array_elements(jsonb_build_array(jsonb_build_array(img,vid),jsonb_build_array(img||'{"role":"first_frame"}'),jsonb_build_array(vid||'{"id":"v.mov"}'),jsonb_build_array(vid||'{"duration_ms":30001}'),jsonb_build_array('{"id":"a.wav","kind":"audio"}'::jsonb))) loop
  r:=public.begin_flux3_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),p,bad);assert not(r->>'ok')::boolean,r::text;
 end loop;
 bad:=jsonb_build_object('model','flux-3-video','resolution','hd','draft_request_id',draft_rid);
 r:=public.begin_flux3_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),bad||'{"prompt":"changed"}','[]');assert r->>'code'='VIDEO_DRAFT_INVALID';
 r:=public.begin_flux3_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),bad||jsonb_build_object('draft_request_id',final_rid),'[]');assert r->>'code'='VIDEO_DRAFT_INVALID';
 r:=public.begin_flux3_job(o||'-'||repeat('b',64),u,gen_random_uuid(),'own_key','generate',repeat('a',64),bad,'[]');assert r->>'code'='VIDEO_DRAFT_INVALID';
 -- Unknown submission keeps reservation; terminal failure refunds exactly once.
 rid:=gen_random_uuid();b:=(select balance from public.credit_accounts where user_id=u);
 r:=public.begin_flux3_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');r:=public.apply_flux3_job(o,rid,'submission_unknown');
 assert (select balance from public.credit_accounts where user_id=u)=b-24.5;
 r:=public.apply_flux3_job(o,rid,'failed');r:=public.apply_flux3_job(o,rid,'failed');assert (select balance from public.credit_accounts where user_id=u)=b;
 -- Insufficient settlement gap holds authoritative cost, then topup reuses it.
 rid:=gen_random_uuid();r:=public.begin_flux3_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');
 update public.credit_accounts set balance=0 where user_id=u;
 r:=public.apply_flux3_job(o,rid,'completed',null,null,'[]',2);assert r#>>'{job,billing_status}'='awaiting_balance';
 r:=public.begin_flux3_job(o,u,gen_random_uuid(),'platform','generate',repeat('a',64),p,'[]');assert r->>'code'='VIDEO_UNSETTLED_BALANCE';
 update public.credit_accounts set balance=1000 where user_id=u;
 r:=public.apply_flux3_job(o,rid,'completed',null,null,'[]',99);assert (r#>>'{job,charged_credits}')::numeric=44.5;
 b:=(select balance from public.credit_accounts where user_id=u);rid:=gen_random_uuid();
 r:=public.begin_flux3_job(o||'-'||repeat('b',64),u,rid,'own_key','generate',repeat('a',64),p,'[]');
 r:=public.apply_flux3_job(o||'-'||repeat('b',64),rid,'completed');assert r#>>'{job,billing_status}'='not_applicable' and (r#>>'{job,charged_credits}')::numeric=0;
 assert (select balance from public.credit_accounts where user_id=u)=b;
 assert not has_function_privilege('anon','public.begin_flux3_job(text,uuid,uuid,text,text,text,jsonb,jsonb)','execute');
 assert not has_function_privilege('authenticated','private.apply_flux3_job(text,uuid,text,text,text,jsonb,numeric,bigint)','execute');
 assert has_function_privilege('service_role','public.apply_flux3_job(text,uuid,text,text,text,jsonb,numeric,bigint)','execute');
end;$$;
rollback;
