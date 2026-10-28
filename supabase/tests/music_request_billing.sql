-- Isolated DB only. Fixtures and ledger changes are rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at) values ('11111111-1111-4111-8111-111111111111','11111111@example.invalid',now());
insert into public.profiles(id,username,status) values ('11111111-1111-4111-8111-111111111111','request-billing-test','active') on conflict(id) do update set status='active';
insert into public.credit_accounts(user_id,balance) values ('11111111-1111-4111-8111-111111111111',100) on conflict(user_id) do update set balance=100;
set local role service_role;
do $$
declare
  u uuid:='11111111-1111-4111-8111-111111111111'; owner text:='user-'||u;
  r uuid; v jsonb; n integer; b integer:=100; ledger_count integer;
begin
  foreach n in array array[1,2,3,64] loop
    r:=gen_random_uuid();
    v:=public.begin_music_job(owner,u,r,'platform','suno','v6',repeat('a',64));
    b:=b-2;
    if (v->>'balance')::numeric<>b or v->'job'->>'billing_unit'<>'request' then raise exception 'reservation not fixed per request'; end if;
    v:=public.apply_music_job(owner,r,'completed',null,n);
    if (v->>'balance')::numeric<>b or v->'job'->>'charged_credits'<>'2' or (v->'job'->>'generated_count')::int<>n then raise exception 'track count changed price'; end if;
    select count(*) into ledger_count from public.credit_transactions where music_job_id=(v->'job'->>'id')::uuid;
    if ledger_count<>2 then raise exception 'unexpected ledger'; end if;
    v:=public.apply_music_job(owner,r,'completed',null,64);
    v:=public.apply_music_job(owner,r,'failed');
    if (select balance from public.credit_accounts where user_id=u)<>b or v->'job'->>'billing_status'<>'settled' then raise exception 'terminal charge repeated or refunded'; end if;
  end loop;
  r:=gen_random_uuid();
  v:=public.begin_music_job(owner,u,r,'platform','flowmusic','lyria-3.5',repeat('b',64));
  v:=public.apply_music_job(owner,r,'submission_unknown');
  if (select balance from public.credit_accounts where user_id=u)<>b-2 then raise exception 'unknown refunded'; end if;
  v:=public.apply_music_job(owner,r,'failed'); v:=public.apply_music_job(owner,r,'failed');
  if (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'refund repeated'; end if;
  r:=gen_random_uuid();
  v:=public.begin_music_job(owner,u,r,'platform','suno','v6',repeat('c',64));
  v:=public.apply_music_job(owner,r,'completed',null,0);
  if v->>'code'<>'MUSIC_EMPTY_RESULT' then raise exception 'empty result billed'; end if;
  v:=public.apply_music_job(owner,r,'rejected');
  r:=gen_random_uuid();
  v:=public.begin_music_job('guest-own-key',null,r,'own_key','suno','v6',repeat('d',64));
  v:=public.apply_music_job('guest-own-key',r,'completed',null,2);
  if v->'job'->>'charged_credits'<>'0' or (select balance from public.credit_accounts where user_id=u)<>b then raise exception 'own key charged'; end if;
end;
$$;
reset role;
update public.credit_accounts set balance=2 where user_id='11111111-1111-4111-8111-111111111111';
set local role service_role;
do $$
declare u uuid:='11111111-1111-4111-8111-111111111111'; r uuid:=gen_random_uuid(); v jsonb;
begin
 v:=public.begin_music_job('user-'||u,u,r,'platform','suno','v6',repeat('e',64));
 v:=public.apply_music_job('user-'||u,r,'completed',null,2);
 if v->'job'->>'billing_status'<>'settled' or v->'job'->>'charged_credits'<>'2' or (v->>'balance')::numeric<>0 then raise exception 'two-credit balance cannot receive both tracks'; end if;
end;
$$;
rollback;
