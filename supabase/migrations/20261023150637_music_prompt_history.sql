-- Text-only music history, separate from durable task and billing records.
create table public.music_prompt_history (
  job_id uuid primary key references public.music_jobs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  prompt text not null check (char_length(prompt) between 1 and 14000),
  parameters jsonb not null check (jsonb_typeof(parameters)='object' and
    parameters - array['model','version','parameter_format','custom','instrumental','prompt','sound_prompt','lyrics','title','style','negative_tags'] = '{}'::jsonb),
  created_at timestamptz not null
);
create index music_prompt_history_owner_created_idx on public.music_prompt_history(user_id,created_at desc,job_id desc);
create index music_prompt_history_expiry_idx on public.music_prompt_history(created_at,job_id);
alter table public.music_prompt_history enable row level security;
revoke all on public.music_prompt_history from public,anon,authenticated;
grant select,insert,delete on public.music_prompt_history to service_role;

-- History and reservation commit together. The old begin RPC remains available
-- to older candidates; no client-supplied prices, credentials or media are stored.
create function public.begin_music_job_with_history(
  p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_model text,p_version text,p_fingerprint text,
  p_prompt text,p_parameters jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_result jsonb;
begin
  if p_prompt is null or char_length(p_prompt) not between 1 and 14000
     or p_parameters is null or jsonb_typeof(p_parameters)<>'object'
     or p_parameters - array['model','version','parameter_format','custom','instrumental','prompt','sound_prompt','lyrics','title','style','negative_tags'] <> '{}'::jsonb
     or p_parameters->>'model' is distinct from p_model then
    return jsonb_build_object('ok',false,'code','INVALID_MUSIC_HISTORY');
  end if;
  v_result:=private.begin_music_job(p_owner,p_user_id,p_request_id,p_mode,p_model,p_version,p_fingerprint);
  if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;
  insert into public.music_prompt_history(job_id,user_id,prompt,parameters,created_at)
    select j.id,j.user_id,p_prompt,p_parameters,j.created_at from public.music_jobs j
    where j.owner_scope=p_owner and j.request_id=p_request_id and j.user_id=p_user_id
      and j.created_at>statement_timestamp()-interval '7 days'
    on conflict(job_id) do nothing;
  return v_result;
end;
$$;
revoke all on function public.begin_music_job_with_history(text,uuid,uuid,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.begin_music_job_with_history(text,uuid,uuid,text,text,text,text,text,jsonb) to service_role;

create function public.get_prompt_history(p_user_id uuid,p_cutoff timestamptz,p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 51)
returns table(id uuid,prompt text,created_at timestamptz,kind text,parameters jsonb)
language sql security invoker set search_path = '' as $$
  select h.id,h.prompt,h.created_at,h.kind,h.parameters from (
    select g.id,g.prompt,g.created_at,'image'::text as kind,null::jsonb as parameters
      from public.generation_jobs g where g.user_id=p_user_id and g.prompt<>''
        and g.created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
    union all
    select m.job_id,m.prompt,m.created_at,'music'::text,m.parameters
      from public.music_prompt_history m where m.user_id=p_user_id
        and m.created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
  ) h
  where p_before is null or (h.created_at,h.id)<(p_before,p_before_id)
  order by h.created_at desc,h.id desc limit least(greatest(p_limit,1),51);
$$;
revoke all on function public.get_prompt_history(uuid,timestamptz,timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.get_prompt_history(uuid,timestamptz,timestamptz,uuid,integer) to service_role;

-- Reuse the existing hourly seven-day text cleanup schedule. Task metadata,
-- credit transactions and audio files are never deleted by this function.
create or replace function private.prune_prompt_text(p_dry_run boolean default true)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_cutoff timestamptz:=statement_timestamp()-interval '7 days';
  v_images integer; v_music integer;
begin
  if p_dry_run is null then raise exception 'Explicit cleanup mode required'; end if;
  if p_dry_run then
    select count(*) into v_images from public.generation_jobs where created_at<=v_cutoff and prompt<>'';
    select count(*) into v_music from public.music_prompt_history where created_at<=v_cutoff;
    return jsonb_build_object('dry_run',true,'eligible',v_images+v_music,'music_eligible',v_music,'cutoff',v_cutoff);
  end if;
  with expired as (select id from public.generation_jobs where created_at<=v_cutoff and prompt<>'' order by created_at,id limit 5000 for update skip locked)
    update public.generation_jobs g set prompt='' from expired where g.id=expired.id;
  get diagnostics v_images=row_count;
  with expired as (select job_id from public.music_prompt_history where created_at<=v_cutoff order by created_at,job_id limit 5000 for update skip locked)
    delete from public.music_prompt_history m using expired where m.job_id=expired.job_id;
  get diagnostics v_music=row_count;
  return jsonb_build_object('cleared',v_images+v_music,'music_cleared',v_music,'cutoff',v_cutoff,'max_rows_per_run',10000);
end;
$$;
revoke all on function private.prune_prompt_text(boolean) from public,anon,authenticated,service_role;
