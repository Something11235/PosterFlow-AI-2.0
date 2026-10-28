begin;
insert into auth.users(id,email,email_confirmed_at) values ('11111111-1111-4111-8111-111111111111','activityone@example.invalid',now()),('22222222-2222-4222-8222-222222222222','activitytwo@example.invalid',now());
insert into public.profiles(id,username,status) values ('11111111-1111-4111-8111-111111111111','activity-one','active'),('22222222-2222-4222-8222-222222222222','activity-two','active') on conflict(id) do update set status='active',username=excluded.username;
update public.credit_accounts set balance=100 where user_id in ('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222');
do $$
declare
 u uuid:='11111111-1111-4111-8111-111111111111'; u2 uuid:='22222222-2222-4222-8222-222222222222';
 r uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; today date:=(now() at time zone 'Asia/Shanghai')::date;
 day0 timestamptz:=today::timestamp at time zone 'Asia/Shanghai'; v jsonb; d jsonb; n bigint; before_music bigint; before_images bigint;
begin
 select count(distinct user_id) into before_music from public.music_jobs where created_at>=day0 and created_at<day0+interval '1 day';
 select count(distinct user_id) into before_images from public.generation_jobs where created_at>=day0 and created_at<day0+interval '1 day';
 v:=public.reserve_platform_credits(u,gen_random_uuid(),1,'fixture','gpt-image-2','image',null,null);
 update public.generation_jobs set created_at=day0+interval '5 hours' where id=(v->>'job_id')::uuid;
 v:=public.begin_music_job('user-'||u,u,r,'platform','suno','v6',repeat('a',64));
 update public.music_jobs set created_at=day0+interval '3 hours' where request_id=r;
 v:=public.apply_music_job('user-'||u,r,'completed',null,2);
 r:=gen_random_uuid();v:=public.begin_music_job('user-'||u2,u2,r,'platform','suno','v6',repeat('b',64));
 update public.music_jobs set created_at=day0-interval '1 second' where request_id=r;
 v:=public.apply_music_job('user-'||u2,r,'failed');
 r:=gen_random_uuid();v:=public.begin_music_job('guest-own-key',null,r,'own_key','suno','v6',repeat('c',64));
 update public.music_jobs set created_at=day0+interval '6 hours' where request_id=r;
 v:=public.get_admin_music_overview(today-1,today,'',100);
 select value into d from jsonb_array_elements(v->'days') where value->>'stat_date'=today::text;
 select count(distinct user_id) into n from (select user_id from public.generation_jobs where created_at>=day0 and created_at<day0+interval '1 day' union select user_id from public.music_jobs where created_at>=day0 and created_at<day0+interval '1 day') x;
 if (d->>'active_users')::bigint<>n or (v->'activity'->>'daily_active_users')::bigint<>n then raise exception 'DAU duplicate across types or chart/card differs'; end if;
 if (d->>'image_active_users')::bigint<>before_images+1 or (d->>'music_active_users')::bigint<>before_music+1 then raise exception 'anonymous included or kind counts incorrect'; end if;
 select value into d from jsonb_array_elements(v->'days') where value->>'stat_date'=(today-1)::text;
 if (d->>'active_users')::int<>1 then raise exception 'Beijing midnight off by eight hours'; end if;
 v:=public.get_admin_music_overview(today-1,today,'activity-one',100);
 if jsonb_array_length(v->'jobs')<>1 or jsonb_array_length(v->'image_jobs')<>1 then raise exception 'mixed usage user search failed'; end if;
 if v->'jobs'->0->>'charged_credits'<>'2' or v->'jobs'->0->>'generated_count'<>'2' or v->'jobs'->0->>'billing_unit'<>'request' then raise exception 'admin music price/count incorrect'; end if;
 if has_function_privilege('authenticated','public.get_admin_music_overview(date,date,text,integer)','EXECUTE') or has_function_privilege('anon','private.get_admin_music_overview(date,date,text,integer)','EXECUTE') then raise exception 'admin RPC privilege leak'; end if;
end;
$$;
set local role service_role;
select public.get_admin_music_overview((now() at time zone 'Asia/Shanghai')::date,(now() at time zone 'Asia/Shanghai')::date,'',1);
reset role;
rollback;
