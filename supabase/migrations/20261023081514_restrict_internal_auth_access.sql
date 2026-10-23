-- Registration deduplication is server-only, including on projects that disable
-- automatic Data API grants. Trigger invocation does not require client EXECUTE.
alter table public.signup_bonus_claims enable row level security;
revoke all on table public.signup_bonus_claims from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
alter function public.handle_new_user() set search_path = '';
