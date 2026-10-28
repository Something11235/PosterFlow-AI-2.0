begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('99999999-9999-4999-8999-999999999999','video-fixture@example.invalid',now());
select public.ensure_signup_bonus('99999999-9999-4999-8999-999999999999');
update public.credit_accounts set balance=100.1234,total_spent=0,total_refunded=0 where user_id='99999999-9999-4999-8999-999999999999';
do $$
declare u uuid:='99999999-9999-4999-8999-999999999999';o text:='user-'||u::text;
 r jsonb;j jsonb;p jsonb:='{"model":"seedance-2.0-mini","prompt":"fixture","resolution":"480p","duration":5,"size":"16:9","generate_audio":true,"return_last_frame":false,"nsfw_check":false}';
 rid uuid:='99999999-9999-4999-8999-000000000001';refs jsonb;
begin
 r:=public.begin_video_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');
 assert (r->>'ok')::boolean and (r->>'balance')::numeric=97.6234,r::text;
 assert (r#>>'{job,reserved_credits}')::numeric=2.5 and (r#>>'{job,unit_credit_cost}')::numeric=0.5;
 r:=public.begin_video_job(o,u,rid,'platform','generate',repeat('a',64),p,'[]');assert (r->>'existing')::boolean;
 r:=public.begin_video_job(o,u,rid,'platform','generate',repeat('b',64),p,'[]');assert r->>'code'='VIDEO_REQUEST_CONFLICT';
 r:=public.apply_video_job('user-other',rid,'failed');assert r->>'code'='VIDEO_NOT_FOUND';
 r:=public.apply_video_job(o,rid,'submission_unknown');assert r#>>'{job,billing_status}'='reserved';
 r:=public.apply_video_job(o,rid,'submitted','task_video_fixture_000001');
 r:=public.apply_video_job(o,rid,'completed');assert (r#>>'{job,charged_credits}')::numeric=2.5;
 r:=public.apply_video_job(o,rid,'failed');assert r#>>'{job,status}'='completed';
 assert (select total_spent from public.credit_accounts where user_id=u)=2.5;
 assert (select count(*) from public.credit_transactions where video_job_id=(r#>>'{job,id}')::uuid and type='spend')=1;
 -- 5 s video + 3 s audio + 10 s generated = 7.5; image/audio add no time.
 refs:='[{"id":"v","kind":"video","duration_ms":5000,"width":854,"height":480},{"id":"a","kind":"audio","duration_ms":3000}]';
 rid:='99999999-9999-4999-8999-000000000002';
 r:=public.begin_video_job(o,u,rid,'platform','generate',repeat('b',64),p||'{"duration":10}',refs);
 assert (r#>>'{job,reserved_credits}')::numeric=7.5 and (r#>>'{job,reference_duration_ms}')::integer=5000,r::text;
 assert (r->>'balance')::numeric=90.1234;
 r:=public.apply_video_job(o,rid,'rejected',null,'VIDEO_CONTENT_REJECTED');assert (r->>'balance')::numeric=97.6234;
 r:=public.apply_video_job(o,rid,'rejected');assert r#>>'{job,billing_status}'='refunded';
 assert (select total_refunded from public.credit_accounts where user_id=u)=7.5;
 r:=public.begin_video_job(o,u,gen_random_uuid(),'platform','generate',repeat('c',64),p||'{"unit_credit_cost":0}','[]');
 assert r->>'code'='INVALID_VIDEO_INPUT';
 -- Subsecond reference durations retain four decimal credit precision.
 r:=public.begin_video_job(o,u,gen_random_uuid(),'platform','generate',repeat('c',64),p,'[{"id":"v2","kind":"video","duration_ms":5001,"width":854,"height":480}]');
 assert (r#>>'{job,reserved_credits}')::numeric=5.0005;
 r:=public.apply_video_job(o,(r#>>'{job,request_id}')::uuid,'failed');assert (r->>'balance')::numeric=97.6234;
 -- Own key and asset review do not consume website credits.
 rid:=gen_random_uuid();r:=public.begin_video_job(o||'-'||repeat('f',64),u,rid,'own_key','generate',repeat('d',64),p,'[]');
 assert (r#>>'{job,reserved_credits}')::numeric=0;
 r:=public.apply_video_job(o||'-'||repeat('f',64),rid,'completed');assert (r#>>'{job,charged_credits}')::numeric=0;
 rid:=gen_random_uuid();r:=public.begin_video_job(o,u,rid,'platform','asset_review',repeat('e',64),'{}','[{"id":"i","kind":"image","sha256":"fixture"}]');
 assert (r#>>'{job,reserved_credits}')::numeric=0;
 r:=public.apply_video_job(o,rid,'completed',null,null,'[{"status":"Active"}]');assert r->>'code'='VIDEO_BAD_ASSET';
 r:=public.apply_video_job(o,rid,'completed',null,null,'[{"id":"i","kind":"image","status":"Active","asset_url":"asset://fixture_asset_001"}]');
 assert r#>>'{job,status}'='completed' and jsonb_array_length(r#>'{job,asset_results}')=1;
 -- History shares the job, is owner-bound, and expiry never deletes money.
 assert (select count(*) from public.get_prompt_history(u,now()-interval '7 days') where kind='video')=4;
 assert not exists(select 1 from public.get_prompt_history('77777777-7777-4777-8777-777777777777',now()-interval '7 days') where kind='video');
 r:=public.get_admin_music_overview((now() at time zone 'Asia/Shanghai')::date,(now() at time zone 'Asia/Shanghai')::date,'video-fixture',100);
 assert (r#>>'{video_metrics,requests}')::integer=4 and (r#>>'{video_metrics,credits}')::numeric=2.5;
 assert jsonb_array_length(r->'video_jobs')=4;
 assert exists(select 1 from jsonb_array_elements(r->'days') d where (d->>'video_active_users')::integer=1);
 update public.video_jobs set history_created_at=now()-interval '8 days' where user_id=u and operation='generate';
 r:=private.prune_prompt_text(false);assert (r->>'video_cleared')::integer=4;
 assert (select total_spent from public.credit_accounts where user_id=u)=2.5;
 assert (select count(*) from public.video_jobs where user_id=u)=5;
 assert not exists(select 1 from public.get_prompt_history(u,now()-interval '30 days') where kind='video');
 for i in 1..3 loop
  r:=public.begin_video_job(o,u,gen_random_uuid(),'platform','generate',repeat('f',64),p,'[]');assert (r->>'ok')::boolean;
 end loop;
 r:=public.begin_video_job(o,u,gen_random_uuid(),'platform','generate',repeat('f',64),p,'[]');assert r->>'code'='VIDEO_QUEUE_FULL';
 assert not has_table_privilege('authenticated','public.video_jobs','select');
 assert not has_function_privilege('anon','public.begin_video_job(text,uuid,uuid,text,text,text,jsonb,jsonb)','execute');
 assert not has_function_privilege('authenticated','public.apply_video_job(text,uuid,text,text,text,jsonb)','execute');
 assert has_function_privilege('service_role','public.begin_video_job(text,uuid,uuid,text,text,text,jsonb,jsonb)','execute');
end;$$;
insert into storage.objects(bucket_id,name,created_at) values
 ('posterflow-images','posterflow/video-'||repeat('a',64)||'/references/1700000000-'||repeat('a',32)||'.mp4',now()-interval '13 hours'),
 ('posterflow-images','posterflow/video-'||repeat('a',64)||'/references/1700000000-'||repeat('b',32)||'.png',now()-interval '1 hour'),
 ('posterflow-images','posterflow/music-'||repeat('a',64)||'/audio-references/1700000000-'||repeat('a',32)||'.mp3',now()-interval '13 hours');
do $$declare r jsonb;begin
 r:=private.prune_video_references(true);assert (r->>'eligible_objects')::integer=1;
 r:=private.prune_video_references(false);assert (r->>'deleted_objects')::integer=1;
 assert (select count(*) from storage.objects where name like 'posterflow/music-%')=1;
 assert (select count(*) from storage.objects where name like 'posterflow/video-%')=1;
 assert not has_function_privilege('service_role','private.prune_video_references(boolean)','execute');
end;$$;
rollback;
