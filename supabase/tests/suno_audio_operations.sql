-- Isolated fixtures only; all tasks, balances and history changes roll back.
begin;
do $$
declare
 u uuid:='55555555-5555-4555-8555-555555555555'; owner text:='user-'||u;
 req uuid; v jsonb; b integer; gid uuid; n integer; op text;
begin
 select balance into b from public.credit_accounts where user_id=u;
 foreach op in array array['inspo','upload_cover'] loop
  req:=gen_random_uuid();
  v:=public.begin_music_audio_job(owner,u,req,'platform','v6',repeat('a',64),'audio composition',jsonb_build_object('model','suno','prompt','original lyrics','operation',op),op,1);
  if v->>'ok'<>'true' or (v->>'balance')::numeric<>b-2 or v->'job'->>'operation'<>op or v->'job'->>'reference_count'<>'1' then raise exception 'audio reservation failed: %',v;end if;
  gid:=(v->'job'->>'id')::uuid;
  v:=public.begin_music_audio_job(owner,u,req,'platform','v6',repeat('a',64),'changed',jsonb_build_object('model','suno','operation',op),op,1);
  if v->>'ok' is distinct from 'true' or v->>'existing' is distinct from 'true' or (select balance from public.credit_accounts where user_id=u)<>b-2 then raise exception 'duplicate debited twice';end if;
  if (select history_prompt from public.music_jobs where id=gid)<>'audio composition' then raise exception 'duplicate rewrote history';end if;
  v:=public.apply_music_job(owner,req,'completed',null,2);
  b:=b-2;
  if v->'job'->>'charged_credits'<>'2' or (v->>'balance')::numeric<>b or v->'job'->'history_parameters'->>'operation'<>op then raise exception 'two tracks did not settle for two credits';end if;
  v:=public.apply_music_job(owner,req,'completed',null,2);
  if (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'repeated result charged twice';end if;
 end loop;
 req:=gen_random_uuid();
 v:=public.begin_music_audio_job(owner,u,req,'platform','v6',repeat('b',64),'reject', '{"model":"suno","operation":"inspo"}', 'inspo',4);
 if v->>'ok' is distinct from 'true' then raise exception 'four-reference reservation failed: %',v;end if;
 v:=public.apply_music_job(owner,req,'submission_unknown');
 if (select balance from public.credit_accounts where user_id=u)<>b-2 then raise exception 'unknown refunded';end if;
 v:=public.apply_music_job(owner,req,'failed'); v:=public.apply_music_job(owner,req,'failed');
 if (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'refund repeated or missing';end if;
 req:=gen_random_uuid();
 v:=public.begin_music_audio_job(owner||'-'||repeat('c',64),u,req,'own_key','v6',repeat('c',64),'own-key', '{"model":"suno","operation":"inspo"}', 'inspo',1);
 if v->>'ok'<>'true' then raise exception 'own-key audio rejected: %',v;end if;
 v:=public.apply_music_job(owner||'-'||repeat('c',64),req,'completed',null,2);
 if v->'job'->>'charged_credits'<>'0' or (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'own key debited';end if;
 -- No change to the accepted legacy endpoint or merged-history ownership.
 v:=public.begin_music_job_with_history(owner,u,gen_random_uuid(),'platform','suno','v6',repeat('d',64),'text only','{"model":"suno","prompt":"text only"}');
 if v->>'ok'<>'true' or v->'job'->>'operation'<>'generate' or v->'job'->>'reference_count'<>'0' then raise exception 'legacy generation broken';end if;
 b:=b-2;
 select count(*) into n from public.music_jobs;
 v:=public.begin_music_audio_job(owner,u,gen_random_uuid(),'platform','v6',repeat('e',64),'invalid','{"model":"suno","operation":"upload_cover"}','upload_cover',2);
 if v->>'ok'<>'false' then raise exception 'cover accepted two references';end if;
 v:=public.begin_music_audio_job(owner,u,gen_random_uuid(),'platform','v6',repeat('e',64),'invalid','{"model":"suno","operation":"inspo","audio_url":"https://never-store.invalid"}','inspo',1);
 if v->>'ok'<>'false' then raise exception 'URL accepted in history';end if;
 update public.profiles set status='frozen' where id=u;
 v:=public.begin_music_audio_job(owner,u,gen_random_uuid(),'platform','v6',repeat('e',64),'invalid','{"model":"suno","operation":"inspo"}','inspo',1);
 if v->>'ok'<>'false' then raise exception 'frozen account accepted';end if;
 update public.profiles set status='active' where id=u;
 update auth.users set email_confirmed_at=null where id=u;
 v:=public.begin_music_audio_job(owner||'-'||repeat('c',64),u,gen_random_uuid(),'own_key','v6',repeat('e',64),'invalid','{"model":"suno","operation":"inspo"}','inspo',1);
 if v->>'ok'<>'false' then raise exception 'unverified own-key accepted';end if;
 update auth.users set email_confirmed_at=now() where id=u;
 if (select count(*) from public.music_jobs)<>n or (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'invalid operation changed money or tasks';end if;
 if exists(select 1 from public.get_prompt_history('66666666-6666-4666-8666-666666666666',now()-interval '7 days') where kind='music') then raise exception 'cross-account history exposed';end if;
 update public.music_jobs set history_created_at=now()-interval '8 days' where id=gid;
 perform private.prune_prompt_text(false);
 if not exists(select 1 from public.music_jobs where id=gid and operation='upload_cover' and reference_count=1 and charged_credits=2 and history_parameters is null) then raise exception 'text cleanup damaged audio task';end if;
 if (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'prune changed money';end if;
 v:=private.get_admin_music_overview(current_date-1,current_date+1,'',100);
 if not exists(select 1 from jsonb_array_elements(v->'jobs') j where j->>'operation'='inspo' and j->>'reference_count'='4') then raise exception 'admin lost audio creation type';end if;
 if has_function_privilege('anon','public.begin_music_audio_job(text,uuid,uuid,text,text,text,text,jsonb,text,integer)','execute') or has_function_privilege('authenticated','public.begin_music_audio_job(text,uuid,uuid,text,text,text,text,jsonb,text,integer)','execute') then raise exception 'audio RPC exposed to browser';end if;
end;
$$;
rollback;
