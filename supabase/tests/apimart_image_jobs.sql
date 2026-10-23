-- Isolated database only. Every account/job/ledger fixture is rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 ('11111111-1111-4111-8111-111111111111','image-sql@example.invalid',now(),'{"username":"apimart-image-sql"}'),
 ('22222222-2222-4222-8222-222222222222','image-unverified@example.invalid',null,'{"username":"image-unverified"}');
select public.ensure_signup_bonus('11111111-1111-4111-8111-111111111111');
update public.credit_accounts set balance=100 where user_id='11111111-1111-4111-8111-111111111111';
set local role service_role;
select public.begin_apimart_image_job('invalid-owner',null,gen_random_uuid(),'platform','nano-banana-pro',1,repeat('a',64),'denied');
reset role;
do $$
declare
 u uuid:='11111111-1111-4111-8111-111111111111'; o text:='user-11111111-1111-4111-8111-111111111111';
 req uuid; token uuid; other uuid; j jsonb; v jsonb; b integer; m text; gid uuid;
begin
 foreach m in array array['gemini-nano-banana-2.1','nano-banana-pro','grok-imagine-image-2.0','grok-imagine-2.0-ext'] loop
  req:=gen_random_uuid();token:=gen_random_uuid();
  v:=public.begin_apimart_image_job(o,u,req,'platform',m,1,repeat('a',64),'test prompt');
  if (v->>'balance')::int<>100 then
   -- First reservation starts at 100 and each completed iteration costs one.
   if (v->>'balance')::int not between 96 and 99 then raise exception 'Wrong reservation';end if;
  end if;
  j:=v->'job';gid:=(j->>'generation_job_id')::uuid;
  if (select reserved_credits from public.generation_jobs where id=gid)<>1 then raise exception 'New model must reserve one per image';end if;
  v:=public.apply_apimart_image_job(o,req,'submitted','task_image_fixture_'||replace(m,'.','-'));
  v:=public.apply_apimart_image_job(o,req,'claim',null,'[]',token);
  if v->>'claimed'<>'true' then raise exception 'Save lease missing';end if;
  v:=public.apply_apimart_image_job(o,req,'completed',null,'["fixture.png"]',token);
  if (select charged_credits from public.generation_jobs where id=gid)<>1 then raise exception 'Actual image must cost one';end if;
  v:=public.apply_apimart_image_job(o,req,'completed',null,'["fixture.png"]',token);
  v:=public.apply_apimart_image_job(o,req,'failed');
  if v->'job'->>'status'<>'completed' then raise exception 'Terminal result regressed';end if;
 end loop;
 select balance into b from public.credit_accounts where user_id=u;
 if b<>96 then raise exception 'Exactly four images should cost four credits';end if;
 req:=gen_random_uuid();token:=gen_random_uuid();other:=gen_random_uuid();
 v:=public.begin_apimart_image_job(o,u,req,'platform','gemini-nano-banana-2.1',4,repeat('b',64),'batch');
 gid:=(v->'job'->>'generation_job_id')::uuid;
 v:=public.begin_apimart_image_job(o,u,req,'platform','gemini-nano-banana-2.1',4,repeat('b',64),'batch');
 if v->>'existing'<>'true' or (v->>'balance')::int<>92 then raise exception 'Request charged twice';end if;
 v:=public.begin_apimart_image_job(o,u,req,'platform','gemini-nano-banana-2.1',4,repeat('c',64),'changed');
 if v->>'code'<>'IMAGE_REQUEST_CONFLICT' then raise exception 'Fingerprint conflict missed';end if;
 v:=public.apply_apimart_image_job(o,req,'submission_unknown');
 update public.generation_jobs set created_at=now()-interval '1 day' where id=gid;
 v:=public.recover_stale_generation_jobs(u,5);
 if (select balance from public.credit_accounts where user_id=u)<>92 then raise exception 'Old recovery refunded accepted async image';end if;
 v:=public.apply_apimart_image_job(o,req,'submitted','task_batch_fixture');
 v:=public.apply_apimart_image_job(o,req,'claim',null,'[]',token);
 v:=public.apply_apimart_image_job(o,req,'claim',null,'[]',other);
 if v->>'claimed'<>'false' then raise exception 'Concurrent worker acquired lease';end if;
 v:=public.apply_apimart_image_job(o,req,'failed');
 if v->'job'->>'status'<>'saving' then raise exception 'Failure raced active saver';end if;
 v:=public.apply_apimart_image_job(o,req,'completed',null,'["one.png","two.png"]',other);
 if v->>'code'<>'IMAGE_SAVE_CONFLICT' then raise exception 'Wrong saver completed task';end if;
 v:=public.apply_apimart_image_job(o,req,'retry',null,'[]',token);
 if v->'job'->>'status'<>'processing' then raise exception 'Save retry lost task';end if;
 v:=public.apply_apimart_image_job(o,req,'claim',null,'[]',other);
 v:=public.apply_apimart_image_job(o,req,'completed',null,'["one.png","two.png"]',other);
 if (v->>'balance')::int<>94 then raise exception 'Partial result must charge 2 and refund 2';end if;
 v:=public.apply_apimart_image_job('different-owner',req,'failed');
 if v->>'code'<>'IMAGE_TASK_NOT_FOUND' then raise exception 'Cross owner lookup leak';end if;
 req:=gen_random_uuid();
 v:=public.begin_apimart_image_job(o,u,req,'platform','grok-imagine-2.0-ext',3,repeat('d',64),'failure');
 v:=public.apply_apimart_image_job(o,req,'failed',null,'[]',null,'fixture-rejected');
 v:=public.apply_apimart_image_job(o,req,'failed');
 if (select balance from public.credit_accounts where user_id=u)<>94 then raise exception 'Refund duplicated or missing';end if;
 v:=public.begin_apimart_image_job('user-22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222',gen_random_uuid(),'platform','nano-banana-pro',1,repeat('a',64),'unverified');
 if v->>'code'<>'EMAIL_UNVERIFIED' then raise exception 'Unverified user charged';end if;
 req:=gen_random_uuid();token:=gen_random_uuid();
 v:=public.begin_apimart_image_job('guest-key-fingerprint',null,req,'own_key','nano-banana-pro',1,repeat('a',64),'guest');
 v:=public.apply_apimart_image_job('guest-key-fingerprint',req,'submitted','task_guest_fixture');
 v:=public.apply_apimart_image_job('guest-key-fingerprint',req,'claim',null,'[]',token);
 v:=public.apply_apimart_image_job('guest-key-fingerprint',req,'completed',null,'["guest.png"]',token);
 if (select balance from public.credit_accounts where user_id=u)<>94 then raise exception 'Own key charged platform';end if;
 if has_table_privilege('authenticated','public.apimart_image_jobs','SELECT') or has_function_privilege('anon','public.begin_apimart_image_job(text,uuid,uuid,text,text,integer,text,text)','EXECUTE') then raise exception 'Task permissions leaked';end if;
end;
$$;
rollback;
