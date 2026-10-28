-- Isolated DB only. No live account fixtures.
begin;
insert into auth.users(id,email,email_confirmed_at) values ('11111111-1111-4111-8111-111111111111','11111111@example.invalid',now()),('22222222-2222-4222-8222-222222222222','22222222@example.invalid',now());
insert into public.profiles(id,username,status) values ('11111111-1111-4111-8111-111111111111','history-one','active'),('22222222-2222-4222-8222-222222222222','history-two','active') on conflict(id) do update set status='active';
insert into public.credit_accounts(user_id,balance) values ('11111111-1111-4111-8111-111111111111',100),('22222222-2222-4222-8222-222222222222',100) on conflict(user_id) do update set balance=100;
set local role service_role;
do $$
declare
 u uuid:='11111111-1111-4111-8111-111111111111'; r uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; v jsonb; count_rows int; b int;
begin
 v:=public.begin_music_job_with_history('user-'||u,u,r,'platform','flowmusic','lyria-3.5',repeat('a',64),'爵士和歌词','{"model":"flowmusic","sound_prompt":"爵士","lyrics":"歌词"}');
 if v->>'ok'<>'true' then raise exception 'atomic history reservation failed'; end if;
 v:=public.begin_music_job_with_history('user-'||u,u,r,'platform','flowmusic','lyria-3.5',repeat('a',64),'重复文本','{"model":"flowmusic","sound_prompt":"重复"}');
 if (select count(*) from public.music_prompt_history where user_id=u)<>1 or (select prompt from public.music_prompt_history where user_id=u)<>'爵士和歌词' then raise exception 'history duplicated or overwritten'; end if;
 select balance into b from public.credit_accounts where user_id=u;
 v:=public.begin_music_job_with_history('user-'||u,u,gen_random_uuid(),'platform','suno','v6',repeat('b',64),'invalid','{"model":"suno","api_key":"must-not-store"}');
 if v->>'code'<>'INVALID_MUSIC_HISTORY' or (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'unsafe history was stored or reserved credits'; end if;
 v:=public.reserve_platform_credits(u,gen_random_uuid(),1,'fixture','gpt-image-2','图片提示词',null,null);
 select count(*) into count_rows from public.get_prompt_history(u,now()-interval '7 days');
 if count_rows<>2 then raise exception 'image/music union incomplete'; end if;
 if exists(select 1 from public.get_prompt_history('22222222-2222-4222-8222-222222222222',now()-interval '7 days')) then raise exception 'history owner isolation failed'; end if;
 if exists(select 1 from public.get_prompt_history(u,now()-interval '7 days',now()-interval '1 day',gen_random_uuid())) then raise exception 'cursor filter failed'; end if;
 if has_table_privilege('authenticated','public.music_prompt_history','SELECT') or has_function_privilege('anon','public.get_prompt_history(uuid,timestamptz,timestamptz,uuid,integer)','EXECUTE') or has_function_privilege('authenticated','public.begin_music_job_with_history(text,uuid,uuid,text,text,text,text,text,jsonb)','EXECUTE') then raise exception 'public history privilege leak'; end if;
end;
$$;
reset role;
update public.music_prompt_history set created_at=now()-interval '8 days';
do $$
declare jobs bigint; tx bigint; v jsonb;
begin
 select count(*) into jobs from public.music_jobs; select count(*) into tx from public.credit_transactions;
 if exists(select 1 from public.get_prompt_history('11111111-1111-4111-8111-111111111111',now()-interval '30 days') where kind='music') then raise exception 'expired text exposed'; end if;
 v:=private.prune_prompt_text(true);
 if (v->>'music_eligible')::int<>1 then raise exception 'music cleanup dry run wrong'; end if;
 v:=private.prune_prompt_text(false);
 if exists(select 1 from public.music_prompt_history) or (select count(*) from public.music_jobs)<>jobs or (select count(*) from public.credit_transactions)<>tx then raise exception 'cleanup removed task or billing'; end if;
end;
$$;
rollback;
