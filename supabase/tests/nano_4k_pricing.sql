-- Isolated database fixtures only; never run on production.
begin;
insert into auth.users(id,email,email_confirmed_at) values ('44444444-4444-4444-8444-444444444444','nano-4k@example.invalid',now());
select public.ensure_signup_bonus('44444444-4444-4444-8444-444444444444');
update public.credit_accounts set balance=200 where user_id='44444444-4444-4444-8444-444444444444';
do $$
declare u uuid:='44444444-4444-4444-8444-444444444444'; req uuid; r jsonb; t uuid; b int; res text; refs int; cost int; gid uuid; before_count bigint;
begin
 foreach res in array array['1K','2K','4K'] loop
  foreach refs in array array[0,8] loop
   cost:=case when res='4K' then 2 else 1 end;
   select balance into b from public.credit_accounts where user_id=u;
   req:=gen_random_uuid();
   r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','gemini-nano-banana-2.1',4,repeat('a',64),'fixture',refs,res);
   if r->>'ok'<>'true' or (r->>'balance')::numeric<>b-4*cost then raise exception 'wrong reservation %, refs %, %',res,refs,r;end if;
   if r->'job'->>'pricing_resolution'<>res or (r->'job'->>'unit_credit_cost')::int<>cost then raise exception 'missing price snapshot';end if;
   gid:=(r->'job'->>'generation_job_id')::uuid;
   if (select (metadata->>'model_cost')::int from public.generation_jobs where id=gid)<>cost then raise exception 'settlement price missing';end if;
   r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','gemini-nano-banana-2.1',4,repeat('a',64),'fixture',refs,res);
   if r->>'existing'<>'true' or (r->>'balance')::numeric<>b-4*cost then raise exception 'duplicate reservation charged';end if;
   r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','gemini-nano-banana-2.1',4,repeat('a',64),'fixture',refs,case when res='4K' then '2K' else '4K' end);
   if r->>'code'<>'IMAGE_REQUEST_CONFLICT' then raise exception 'resolution conflict ignored';end if;
   r:=public.apply_apimart_image_job('user-'||u,req,'submitted','task_nano_fixture_12345678');
   t:=gen_random_uuid();r:=public.apply_apimart_image_job('user-'||u,req,'claim',null,'[]',t);
   r:=public.apply_apimart_image_job('user-'||u,req,'completed',null,'["fixture.png"]',t);
   if (r->>'balance')::numeric<>b-cost or (select charged_credits from public.generation_jobs where id=gid)<>cost then raise exception 'partial settlement wrong';end if;
   r:=public.apply_apimart_image_job('user-'||u,req,'completed',null,'["fixture.png"]',t);
   if (r->>'balance')::numeric<>b-cost then raise exception 'double settled';end if;
  end loop;
 end loop;
 select balance into b from public.credit_accounts where user_id=u;
 req:=gen_random_uuid();r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','gemini-nano-banana-2.1',4,repeat('b',64),'fixture',0,'4K');
 r:=public.apply_apimart_image_job('user-'||u,req,'failed',null,'[]',null,'REFERENCE_UPLOAD_FAILED');
 r:=public.apply_apimart_image_job('user-'||u,req,'failed');
 if (r->>'balance')::numeric<>b then raise exception '4K refund not full/once';end if;
 -- Old v2 reservations retain their original one-credit snapshot on v3 retries.
 req:=gen_random_uuid();r:=public.begin_apimart_image_job_v2('user-'||u,u,req,'platform','gemini-nano-banana-2.1',1,repeat('c',64),'old fixture',0);
 r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','gemini-nano-banana-2.1',1,repeat('c',64),'old fixture',0,'4K');
 if r->>'existing'<>'true' or r->'job'->>'unit_credit_cost'<>'1' then raise exception 'old reservation repriced';end if;
 r:=public.apply_apimart_image_job('user-'||u,req,'failed');
 r:=public.begin_apimart_image_job_v3('guest-own-key',null,gen_random_uuid(),'own_key','gemini-nano-banana-2.1',4,repeat('d',64),'fixture',8,'4K');
 if r->>'ok'<>'true' or r->'job'->>'unit_credit_cost'<>'0' then raise exception 'own key charged';end if;
 -- The same new RPC preserves Grok's text/reference prices and automatic resolution.
 foreach refs in array array[0,3] loop
  req:=gen_random_uuid();select balance into b from public.credit_accounts where user_id=u;
  cost:=case when refs=0 then 1 else 2 end;
  r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','grok-imagine-image-2.0',2,repeat('e',64),'fixture',refs,null);
  if r->>'ok'<>'true' or (r->>'balance')::numeric<>b-2*cost or (r->'job'->>'unit_credit_cost')::int<>cost then raise exception 'Grok new RPC price changed';end if;
  r:=public.apply_apimart_image_job('user-'||u,req,'failed');
 end loop;
 req:=gen_random_uuid();r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','grok-imagine-2.0-ext',1,repeat('e',64),'fixture',0,null);
 if r->>'ok'<>'true' or r->'job'->>'unit_credit_cost'<>'1' then raise exception 'Ext price changed';end if;
 r:=public.apply_apimart_image_job('user-'||u,req,'failed');
 update public.credit_accounts set balance=1 where user_id=u;
 select count(*) into before_count from public.credit_transactions where user_id=u;
 req:=gen_random_uuid();r:=public.begin_apimart_image_job_v3('user-'||u,u,req,'platform','gemini-nano-banana-2.1',1,repeat('e',64),'fixture',0,'4K');
 if r->>'code'<>'CREDITS_INSUFFICIENT' or exists(select 1 from public.apimart_image_jobs where request_id=req) or (select count(*) from public.credit_transactions where user_id=u)<>before_count then raise exception 'insufficient balance mutated ledger';end if;
 r:=public.begin_apimart_image_job_v3('user-'||u,u,gen_random_uuid(),'platform','gemini-nano-banana-2.1',1,repeat('f',64),'fixture',0,'2K');
 if r->>'ok'<>'true' or (r->>'balance')::numeric<>0 then raise exception 'lower tier one-credit rejected';end if;
 foreach res in array array[null,'auto','8K'] loop
  r:=public.begin_apimart_image_job_v3('user-'||u,u,gen_random_uuid(),'platform','gemini-nano-banana-2.1',1,repeat('f',64),'fixture',0,res);
  if r->>'code'<>'INVALID_IMAGE_TASK' then raise exception 'invalid resolution accepted';end if;
 end loop;
 if has_function_privilege('anon','public.begin_apimart_image_job_v3(text,uuid,uuid,text,text,integer,text,text,integer,text)','execute') or has_function_privilege('authenticated','private.reserve_nano_4k_credits(uuid,uuid,integer,text,text,text,integer,integer)','execute') then raise exception 'price RPC exposed';end if;
end;
$$;
rollback;
