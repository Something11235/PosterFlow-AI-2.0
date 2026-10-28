-- One physical music table. Preserve the old RPC signatures for the live app.
-- Atomic copy + integrity checks + function switch + drop; no CASCADE.
set local lock_timeout = '5s';
lock table public.music_jobs in access exclusive mode;
lock table public.music_prompt_history in access exclusive mode;

create temporary table music_merge_original_jobs on commit drop as
  select id,md5(to_jsonb(j)::text) as hash from public.music_jobs j;
create temporary table music_merge_original_history on commit drop as
  select job_id,user_id,md5(prompt) as prompt_hash,md5(parameters::text) as parameters_hash,created_at
  from public.music_prompt_history;

do $$ begin
 if exists(select 1 from public.music_prompt_history h left join public.music_jobs j on j.id=h.job_id
   where j.id is null or j.user_id is distinct from h.user_id) then
   raise exception 'Music history owner integrity check failed';
 end if;
end $$;

alter table public.music_jobs
 add column history_prompt text not null default '' check(char_length(history_prompt)<=14000),
 add column history_parameters jsonb check(jsonb_typeof(history_parameters)='object' and
   history_parameters-array['model','version','parameter_format','custom','instrumental','prompt','sound_prompt','lyrics','title','style','negative_tags']='{}'::jsonb),
 add column history_created_at timestamptz,
 add constraint music_jobs_history_complete check(
   (history_prompt='' and history_parameters is null and history_created_at is null) or
   (history_prompt<>'' and history_parameters is not null and history_created_at is not null));

update public.music_jobs j
 set history_prompt=h.prompt,history_parameters=h.parameters,history_created_at=h.created_at
 from public.music_prompt_history h where h.job_id=j.id and h.user_id=j.user_id;

create index music_jobs_history_owner_created_idx on public.music_jobs(user_id,history_created_at desc,id desc)
 where history_created_at is not null;
create index music_jobs_history_expiry_idx on public.music_jobs(history_created_at,id)
 where history_created_at is not null;

create or replace function public.begin_music_job_with_history(
 p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_model text,p_version text,p_fingerprint text,
 p_prompt text,p_parameters jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_result jsonb;
begin
 if p_prompt is null or char_length(p_prompt) not between 1 and 14000
   or p_parameters is null or jsonb_typeof(p_parameters)<>'object'
   or p_parameters-array['model','version','parameter_format','custom','instrumental','prompt','sound_prompt','lyrics','title','style','negative_tags']<>'{}'::jsonb
   or p_parameters->>'model' is distinct from p_model then
   return jsonb_build_object('ok',false,'code','INVALID_MUSIC_HISTORY');
 end if;
 v_result:=private.begin_music_job(p_owner,p_user_id,p_request_id,p_mode,p_model,p_version,p_fingerprint);
 if not coalesce((v_result->>'ok')::boolean,false) then return v_result;end if;
 update public.music_jobs set history_prompt=p_prompt,history_parameters=p_parameters,history_created_at=created_at
 where owner_scope=p_owner and request_id=p_request_id and user_id=p_user_id
   and history_created_at is null and created_at>statement_timestamp()-interval '7 days';
 return v_result;
end;
$$;

create or replace function public.get_prompt_history(p_user_id uuid,p_cutoff timestamptz,p_before timestamptz default null,p_before_id uuid default null,p_limit integer default 51)
returns table(id uuid,prompt text,created_at timestamptz,kind text,parameters jsonb)
language sql security invoker set search_path='' as $$
 select h.id,h.prompt,h.created_at,h.kind,h.parameters from (
   select g.id,g.prompt,g.created_at,'image'::text as kind,null::jsonb as parameters
    from public.generation_jobs g where g.user_id=p_user_id and g.prompt<>''
     and g.created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
   union all
   select m.id,m.history_prompt,m.history_created_at,'music'::text,m.history_parameters
    from public.music_jobs m where m.user_id=p_user_id and m.history_prompt<>''
     and m.history_created_at>greatest(p_cutoff,statement_timestamp()-interval '7 days')
 ) h
 where p_before is null or (h.created_at,h.id)<(p_before,p_before_id)
 order by h.created_at desc,h.id desc limit least(greatest(p_limit,1),51);
$$;

create or replace function private.prune_prompt_text(p_dry_run boolean default true)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_cutoff timestamptz:=statement_timestamp()-interval '7 days';v_images integer;v_music integer;
begin
 if p_dry_run is null then raise exception 'Explicit cleanup mode required';end if;
 if p_dry_run then
  select count(*) into v_images from public.generation_jobs where created_at<=v_cutoff and prompt<>'';
  select count(*) into v_music from public.music_jobs where history_created_at<=v_cutoff;
  return jsonb_build_object('dry_run',true,'eligible',v_images+v_music,'music_eligible',v_music,'cutoff',v_cutoff);
 end if;
 with expired as(select id from public.generation_jobs where created_at<=v_cutoff and prompt<>'' order by created_at,id limit 5000 for update skip locked)
  update public.generation_jobs g set prompt='' from expired where g.id=expired.id;
 get diagnostics v_images=row_count;
 with expired as(select id from public.music_jobs where history_created_at<=v_cutoff order by history_created_at,id limit 5000 for update skip locked)
  update public.music_jobs m set history_prompt='',history_parameters=null,history_created_at=null from expired where m.id=expired.id;
 get diagnostics v_music=row_count;
 return jsonb_build_object('cleared',v_images+v_music,'music_cleared',v_music,'cutoff',v_cutoff,'max_rows_per_run',10000);
end;
$$;

revoke all on function public.begin_music_job_with_history(text,uuid,uuid,text,text,text,text,text,jsonb),
 public.get_prompt_history(uuid,timestamptz,timestamptz,uuid,integer) from public,anon,authenticated;
grant execute on function public.begin_music_job_with_history(text,uuid,uuid,text,text,text,text,text,jsonb),
 public.get_prompt_history(uuid,timestamptz,timestamptz,uuid,integer) to service_role;
revoke all on function private.prune_prompt_text(boolean) from public,anon,authenticated,service_role;

do $$ begin
 if exists(select 1 from music_merge_original_jobs o left join public.music_jobs j on j.id=o.id
   where j.id is null or o.hash<>md5((to_jsonb(j)-array['history_prompt','history_parameters','history_created_at'])::text))
   or (select count(*) from music_merge_original_jobs)<>(select count(*) from public.music_jobs) then
   raise exception 'Original music task fields changed';
 end if;
 if exists(select 1 from music_merge_original_history h left join public.music_jobs j on j.id=h.job_id
   where j.id is null or j.user_id is distinct from h.user_id or md5(j.history_prompt)<>h.prompt_hash
     or md5(j.history_parameters::text)<>h.parameters_hash or j.history_created_at is distinct from h.created_at)
   or (select count(*) from music_merge_original_history)<>(select count(*) from public.music_jobs where history_created_at is not null) then
   raise exception 'Music history copy integrity check failed';
 end if;
end $$;

drop table public.music_prompt_history;
comment on column public.music_jobs.history_prompt is 'Seven-day prompt/lyrics snapshot; expires independently of task and billing records.';
