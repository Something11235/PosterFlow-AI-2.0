-- Local preparation only. Apply with a separately approved website release.
set local lock_timeout='5s';
alter table public.music_jobs drop constraint music_jobs_operation_check;
alter table public.music_jobs add constraint music_jobs_operation_check
 check(operation in ('generate','inspo','upload_cover','flow_cover'));
alter table public.music_jobs
 add column flow_stage text check(flow_stage in ('importing','cover_submitting','generating')),
 add column flow_import_task_id text check(flow_import_task_id ~ '^[A-Za-z0-9_-]{8,160}$');
alter table public.music_jobs add constraint music_jobs_flow_operation_check
 check((operation='flow_cover' and flow_stage is not null and reference_count=1 and model='flowmusic')
    or (operation<>'flow_cover' and flow_stage is null and flow_import_task_id is null));
alter table public.music_jobs drop constraint music_jobs_history_parameters_check;
alter table public.music_jobs add constraint music_jobs_history_parameters_check check(
 jsonb_typeof(history_parameters)='object' and
 history_parameters-array['model','version','parameter_format','custom','instrumental','prompt','sound_prompt','lyrics','title','style','negative_tags','operation','strength']='{}'::jsonb);

create function private.begin_flow_cover_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,
 p_version text,p_fingerprint text,p_prompt text,p_parameters jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;j public.music_jobs;
begin
 if p_user_id is null or p_version is null or p_version not in ('lyria-3-pro','lyria-3.5')
  or p_parameters is null or jsonb_typeof(p_parameters)<>'object'
  or p_parameters-array['model','version','prompt','title','strength','operation']<>'{}'::jsonb
  or p_parameters->>'model' is distinct from 'flowmusic'
  or p_parameters->>'operation' is distinct from 'flow_cover'
  or p_parameters->>'version' is distinct from p_version
  or jsonb_typeof(p_parameters->'prompt') is distinct from 'string'
  or char_length(trim(p_parameters->>'prompt')) not between 1 and 3000
  or jsonb_typeof(p_parameters->'strength') is distinct from 'string'
  or (p_parameters->>'strength') !~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
  or (p_parameters ? 'title' and (jsonb_typeof(p_parameters->'title')<>'string' or char_length(p_parameters->>'title')>200))
  or not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null)
  or not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null)
  or (p_mode='own_key' and p_owner !~ ('^user-'||p_user_id::text||'-[a-f0-9]{64}$')) then
  return jsonb_build_object('ok',false,'code','INVALID_MUSIC_INPUT');
 end if;
 r:=public.begin_music_job_with_history(p_owner,p_user_id,p_request_id,p_mode,'flowmusic',p_version,p_fingerprint,p_prompt,p_parameters-array['operation','strength']);
 if not coalesce((r->>'ok')::boolean,false) then return r;end if;
 select * into j from public.music_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if coalesce((r->>'existing')::boolean,false) then
  if j.operation<>'flow_cover' then return jsonb_build_object('ok',false,'code','MUSIC_REQUEST_CONFLICT');end if;
 else
  update public.music_jobs set operation='flow_cover',reference_count=1,flow_stage='importing',
   history_parameters=p_parameters where id=j.id returning * into j;
 end if;
 return r||jsonb_build_object('job',to_jsonb(j));
end;
$$;
create function public.begin_flow_cover_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,
 p_version text,p_fingerprint text,p_prompt text,p_parameters jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.begin_flow_cover_job(p_owner,p_user_id,p_request_id,p_mode,p_version,p_fingerprint,p_prompt,p_parameters);
$$;

create function private.advance_flow_cover_job(p_owner text,p_request_id uuid,p_expected_task text,p_event text,
 p_task_id text default null,p_error_code text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.music_jobs;r jsonb;b jsonb;
begin
 select * into j from public.music_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if not found then return jsonb_build_object('ok',false,'code','MUSIC_NOT_FOUND');end if;
 if j.operation<>'flow_cover' or p_expected_task is null or p_expected_task !~ '^[A-Za-z0-9_-]{8,160}$'
  or p_event is null or p_event not in ('import_progress','import_failed','claim_cover','cover_submitted','cover_rejected','cover_unknown') then
  return jsonb_build_object('ok',false,'code','INVALID_MUSIC_EVENT');
 end if;
 -- Stale/concurrent GETs never regress phases or acquire a second paid POST.
 if j.billing_status in ('settled','refunded') or j.status in ('completed','failed') then
  return jsonb_build_object('ok',true,'claimed',false,'job',to_jsonb(j));
 end if;
 if p_event in ('import_progress','import_failed','claim_cover') then
  if j.flow_stage<>'importing' or j.provider_task_id is distinct from p_expected_task then
   return jsonb_build_object('ok',true,'claimed',false,'job',to_jsonb(j));
  end if;
  if p_event='claim_cover' then
   if j.history_created_at is null or j.history_created_at<=statement_timestamp()-interval '7 days' then
    return private.apply_music_job(p_owner,p_request_id,'failed',null,0,'MUSIC_FLOW_SOURCE_EXPIRED')||jsonb_build_object('claimed',false);
   end if;
   b:=jsonb_build_object('model','flowmusic','instruction',j.history_parameters->>'prompt',
     'strength',(j.history_parameters->>'strength')::numeric);
   if j.version='lyria-3.5' then b:=b||jsonb_build_object('version',j.version);end if;
   if coalesce(j.history_parameters->>'title','')<>'' then b:=b||jsonb_build_object('title',j.history_parameters->>'title');end if;
   update public.music_jobs set flow_import_task_id=provider_task_id,provider_task_id=null,
    flow_stage='cover_submitting',status='submission_unknown',last_checked_at=now() where id=j.id returning * into j;
   return jsonb_build_object('ok',true,'claimed',true,'job',to_jsonb(j),'parameters',b);
  end if;
  return private.apply_music_job(p_owner,p_request_id,case when p_event='import_failed' then 'failed' else 'processing' end,null,0,p_error_code);
 end if;
 if j.flow_stage<>'cover_submitting' or j.flow_import_task_id is distinct from p_expected_task then
  return jsonb_build_object('ok',true,'claimed',false,'job',to_jsonb(j));
 end if;
 r:=private.apply_music_job(p_owner,p_request_id,
   case p_event when 'cover_submitted' then 'submitted' when 'cover_rejected' then 'rejected' else 'submission_unknown' end,
   p_task_id,0,p_error_code);
 if not coalesce((r->>'ok')::boolean,false) then return r;end if;
 if p_event='cover_submitted' then
  update public.music_jobs set flow_stage='generating' where id=j.id returning * into j;
  r:=r||jsonb_build_object('job',to_jsonb(j));
 end if;
 return r;
end;
$$;
create function public.advance_flow_cover_job(p_owner text,p_request_id uuid,p_expected_task text,p_event text,
 p_task_id text default null,p_error_code text default null)
returns jsonb language sql security invoker set search_path='' as $$
 select private.advance_flow_cover_job(p_owner,p_request_id,p_expected_task,p_event,p_task_id,p_error_code);
$$;
revoke all on function private.begin_flow_cover_job(text,uuid,uuid,text,text,text,text,jsonb),
 public.begin_flow_cover_job(text,uuid,uuid,text,text,text,text,jsonb),
 private.advance_flow_cover_job(text,uuid,text,text,text,text),public.advance_flow_cover_job(text,uuid,text,text,text,text)
 from public,anon,authenticated;
grant execute on function private.begin_flow_cover_job(text,uuid,uuid,text,text,text,text,jsonb),
 public.begin_flow_cover_job(text,uuid,uuid,text,text,text,text,jsonb),
 private.advance_flow_cover_job(text,uuid,text,text,text,text),public.advance_flow_cover_job(text,uuid,text,text,text,text)
 to service_role;
