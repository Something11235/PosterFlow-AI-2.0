-- Isolated development verification; all fixture data is rolled back.
begin;
do $$
begin
  if not (select relrowsecurity from pg_class where oid='public.signup_bonus_claims'::regclass) then
    raise exception 'Registration deduplication must use RLS';
  end if;
  if has_table_privilege('anon','public.signup_bonus_claims','SELECT')
     or has_table_privilege('authenticated','public.signup_bonus_claims','INSERT')
     or has_function_privilege('anon','public.handle_new_user()','EXECUTE')
     or has_function_privilege('authenticated','public.handle_new_user()','EXECUTE') then
    raise exception 'Client registration privileges exceed the server-only contract';
  end if;
end;
$$;
insert into auth.users(id,email,raw_user_meta_data) values
('44444444-4444-4444-8444-444444444444','internal-auth-test@example.invalid','{"username":"internal-auth-regression"}');
do $$
begin
  if not exists(select 1 from public.profiles where id='44444444-4444-4444-8444-444444444444')
     or not exists(select 1 from public.credit_accounts where user_id='44444444-4444-4444-8444-444444444444') then
    raise exception 'Registration trigger stopped creating the profile and credit account';
  end if;
end;
$$;
rollback;
