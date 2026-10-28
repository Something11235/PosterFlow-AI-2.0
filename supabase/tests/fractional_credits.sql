begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('88888888-8888-4888-8888-888888888888','decimal-fixture@example.invalid',now());
select public.ensure_signup_bonus('88888888-8888-4888-8888-888888888888');
update public.credit_accounts set balance=100.1234 where user_id='88888888-8888-4888-8888-888888888888';
do $$
declare u uuid:='88888888-8888-4888-8888-888888888888';r jsonb;j uuid;owner text:='user-88888888-8888-4888-8888-888888888888';
begin
 assert public.ensure_signup_bonus(u)#>>'{balance}'='100.1234';
 r:=public.admin_adjust_credit_amount(u,u,0.0001,'fractional fixture','decimal-admin-fixture');
 assert (r->>'ok')::boolean and (r->>'balance')::numeric=100.1235;
 r:=public.admin_adjust_credit_amount(u,u,0.0001,'fractional fixture','decimal-admin-fixture');
 assert (r->>'idempotent')::boolean and (r->>'balance')::numeric=100.1235;
 r:=public.admin_adjust_credit_amount(u,u,0.5,'fractional fixture','decimal-admin-fixture');assert r->>'code'='CREDIT_REQUEST_CONFLICT';
 r:=public.admin_adjust_credit_amount(u,u,0.00001,'fractional fixture','decimal-too-precise');assert r->>'code'='CREDIT_DELTA_INVALID';
 r:=public.admin_adjust_credit_amount(u,u,'NaN'::numeric,'fractional fixture','decimal-not-a-number');assert r->>'code'='CREDIT_DELTA_INVALID';

 -- Old integer image billing preserves the fractional remainder at all APIs.
 r:=public.reserve_platform_credits(u,'88888888-8888-4888-8888-000000000001',1,'openai','gpt-image-2.5-flare','fixture',100,1000);
 assert (r->>'ok')::boolean and (r->>'balance')::numeric=99.1235;j:=(r->>'job_id')::uuid;
 r:=public.settle_generation(j,1,100,'["decimal-fixture.png"]');assert (r->>'balance')::numeric=99.1235;
 assert (public.get_account_snapshot(u)#>>'{credits,balance}')::numeric=99.1235;

 -- New image wrappers formerly parsed the balance through integer casts.
 r:=public.begin_apimart_image_job_v3(owner,u,'88888888-8888-4888-8888-000000000002','platform','gemini-nano-banana-2.1',1,repeat('d',64),'fixture',0,'4K');
 assert (r->>'ok')::boolean and (r->>'balance')::numeric=97.1235;
 r:=public.apply_apimart_image_job(owner,'88888888-8888-4888-8888-000000000002','failed',null,null,null,'fixture');
 assert (r->>'balance')::numeric=99.1235;

 -- Existing Suno/Flow request prices stay two credits including refunds.
 r:=public.begin_music_job(owner,u,'88888888-8888-4888-8888-000000000003','platform','suno','v6',repeat('e',64));
 assert (r->>'balance')::numeric=97.1235;
 r:=public.apply_music_job(owner,'88888888-8888-4888-8888-000000000003','completed',null,2);assert (r->>'balance')::numeric=97.1235;
 r:=public.begin_music_job(owner,u,'88888888-8888-4888-8888-000000000004','platform','suno','v6',repeat('f',64));
 assert (r->>'balance')::numeric=95.1235;
 r:=public.apply_music_job(owner,'88888888-8888-4888-8888-000000000004','failed');assert (r->>'balance')::numeric=97.1235;
 assert (select balance from public.credit_accounts where user_id=u)=97.1235;
 assert not has_function_privilege('anon','public.admin_adjust_credit_amount(uuid,uuid,numeric,text,text)','execute');
 assert not has_function_privilege('authenticated','public.admin_adjust_credit_amount(uuid,uuid,numeric,text,text)','execute');
end;$$;
rollback;
