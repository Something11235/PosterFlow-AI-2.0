-- Run only in an isolated development database with the music migration applied.
-- Every fixture and ledger mutation is rolled back.
begin;
insert into auth.users(id,email_confirmed_at) values
('11111111-1111-4111-8111-111111111111',now()),
('22222222-2222-4222-8222-222222222222',null),
('33333333-3333-4333-8333-333333333333',now());
insert into public.profiles(id,username,status) values
('11111111-1111-4111-8111-111111111111','music-test-active','active'),
('22222222-2222-4222-8222-222222222222','music-test-unverified','active'),
('33333333-3333-4333-8333-333333333333','music-test-frozen','frozen')
on conflict(id) do update set status=excluded.status;
insert into public.credit_accounts(user_id,balance) values
('11111111-1111-4111-8111-111111111111',100),
('22222222-2222-4222-8222-222222222222',100),
('33333333-3333-4333-8333-333333333333',100)
on conflict(user_id) do update set balance=100;
set local role service_role;
do $$
declare
  u uuid := '11111111-1111-4111-8111-111111111111';
  owner text := 'user-' || u::text;
  r uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  r2 uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  r3 uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  v jsonb;
  b integer;
begin
  v:=public.begin_music_job(owner,u,r,'platform','suno','v6',repeat('a',64));
  if v->>'existing'<>'false' or (v->>'balance')::int<>98 then raise exception 'reservation failed'; end if;
  v:=public.begin_music_job(owner,u,r,'platform','suno','v6',repeat('a',64));
  if v->>'existing'<>'true' then raise exception 'duplicate generated again'; end if;
  v:=public.begin_music_job(owner,u,r,'platform','suno','v6',repeat('b',64));
  if v->>'code'<>'MUSIC_REQUEST_CONFLICT' then raise exception 'parameter fingerprint not enforced'; end if;
  v:=public.apply_music_job(owner,r,'submitted','task_music_sql_1');
  v:=public.apply_music_job(owner,r,'completed',null,2);
  if v->'job'->>'charged_credits'<>'4' or (v->>'balance')::int<>96 then raise exception 'two songs must cost four'; end if;
  v:=public.apply_music_job(owner,r,'completed',null,2);
  v:=public.apply_music_job(owner,r,'failed',null,0,'late-failure');
  select balance into b from public.credit_accounts where user_id=u;
  if b<>96 or v->'job'->>'status'<>'completed' then raise exception 'terminal state regressed or charged again'; end if;
  v:=public.apply_music_job('different-owner',r,'failed');
  if v->>'code'<>'MUSIC_NOT_FOUND' then raise exception 'cross-user access'; end if;
  v:=public.begin_music_job(owner,u,r2,'platform','flowmusic','lyria-3.5',repeat('b',64));
  v:=public.apply_music_job(owner,r2,'submission_unknown');
  select balance into b from public.credit_accounts where user_id=u;
  if b<>94 or v->'job'->>'billing_status'<>'reserved' then raise exception 'unknown state refunded'; end if;
  v:=public.apply_music_job(owner,r2,'rejected',null,0,'test-rejection');
  v:=public.apply_music_job(owner,r2,'rejected',null,0,'duplicate-rejection');
  select balance into b from public.credit_accounts where user_id=u;
  if b<>96 then raise exception 'refund duplicated'; end if;
  v:=public.begin_music_job('guest-own-key',null,r3,'own_key','custom/model','user-version',repeat('c',64));
  v:=public.apply_music_job('guest-own-key',r3,'completed',null,3);
  if v->'job'->>'charged_credits'<>'0' then raise exception 'own key charged website credits'; end if;
  select balance into b from public.credit_accounts where user_id=u;
  if b<>96 then raise exception 'own key mutated account'; end if;
  v:=public.begin_music_job('user-22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222',gen_random_uuid(),'platform','suno','v6',repeat('a',64));
  if v->>'code'<>'EMAIL_UNVERIFIED' then raise exception 'unverified account allowed'; end if;
  v:=public.begin_music_job('user-33333333-3333-4333-8333-333333333333','33333333-3333-4333-8333-333333333333',gen_random_uuid(),'platform','suno','v6',repeat('a',64));
  if v->>'code'<>'ACCOUNT_FROZEN' then raise exception 'frozen account allowed'; end if;
  v:=public.begin_music_job(owner,u,gen_random_uuid(),'platform','custom/model','v6',repeat('a',64));
  if v->>'ok'<>'false' then raise exception 'custom model allowed on platform'; end if;
  if has_function_privilege('anon','public.begin_music_job(text,uuid,uuid,text,text,text,text)','EXECUTE')
     or has_function_privilege('authenticated','private.apply_music_job(text,uuid,text,text,integer,text)','EXECUTE')
     or has_table_privilege('authenticated','public.music_jobs','SELECT') then raise exception 'privilege leak'; end if;
end;
$$;
reset role;
update public.credit_accounts set balance=2 where user_id='11111111-1111-4111-8111-111111111111';
set local role service_role;
do $$
declare
  u uuid := '11111111-1111-4111-8111-111111111111';
  owner text := 'user-' || u::text;
  r uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v jsonb;
begin
  v:=public.begin_music_job(owner,u,r,'platform','suno','v6-mini',repeat('d',64));
  v:=public.apply_music_job(owner,r,'completed',null,2);
  if v->'job'->>'billing_status'<>'awaiting_balance' or (v->>'balance')::int<>0 then raise exception 'low balance was overdrawn'; end if;
  v:=public.apply_music_job(owner,r,'unknown');
  if v->'job'->>'status'<>'completed' then raise exception 'completed count was lost'; end if;
end;
$$;
reset role;
update public.credit_accounts set balance=2 where user_id='11111111-1111-4111-8111-111111111111';
set local role service_role;
do $$
declare v jsonb;
begin
  v:=public.apply_music_job('user-11111111-1111-4111-8111-111111111111','dddddddd-dddd-4ddd-8ddd-dddddddddddd','completed',null,9);
  if v->'job'->>'charged_credits'<>'4' or v->'job'->>'generated_count'<>'2' or (v->>'balance')::int<>0 then raise exception 'top-up failed or original count changed'; end if;
end;
$$;
rollback;
