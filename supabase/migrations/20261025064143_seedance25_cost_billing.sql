-- Local only. Existing Mini intents keep their original prices and RPCs.
set local lock_timeout='5s';
alter table public.video_jobs
 drop constraint video_jobs_model_check,
 drop constraint video_jobs_billing_status_check,
 drop constraint video_jobs_resolution_check,
 drop constraint video_jobs_reference_duration_ms_check,
 drop constraint video_jobs_estimated_credits_check,
 drop constraint video_jobs_reserved_credits_check,
 drop constraint video_jobs_charged_credits_check,
 drop constraint video_jobs_reference_metadata_check,
 drop constraint video_jobs_check,
 drop constraint video_jobs_history_parameters_check,
 add constraint video_jobs_model_check check(model in ('seedance-2.0-mini','seedance-2.5')),
 add constraint video_jobs_billing_status_check check(billing_status in ('reserved','settled','refunded','not_applicable','awaiting_provider','awaiting_balance')),
 add constraint video_jobs_resolution_check check(resolution in ('480p','720p','1080p')),
 add constraint video_jobs_reference_duration_ms_check check(reference_duration_ms between 0 and 30000),
 add constraint video_jobs_estimated_credits_check check(estimated_credits between 0 and 5000),
 add constraint video_jobs_reserved_credits_check check(reserved_credits between 0 and 5000),
 add constraint video_jobs_charged_credits_check check(charged_credits between 0 and 25000),
 add constraint video_jobs_reference_metadata_check check(jsonb_typeof(reference_metadata)='array' and jsonb_array_length(reference_metadata)<=50),
 add constraint video_jobs_generation_shape check(
   (operation='generate' and resolution is not null and
    ((model='seedance-2.0-mini' and requested_duration between 4 and 15 and resolution in ('480p','720p'))
     or(model='seedance-2.5' and (requested_duration=-1 or requested_duration between 4 and 30))))
   or(operation='asset_review' and requested_duration=0 and resolution is null and unit_credit_cost=0 and estimated_credits=0)),
 add constraint video_jobs_history_fields check(history_parameters is null or (jsonb_typeof(history_parameters)='object' and
   history_parameters-array['model','prompt','duration','size','resolution','seed','generate_audio','return_last_frame','tools','nsfw_check',
     'draft','draft_request_id','output_format','watermark','omni_reference_task_type']='{}'::jsonb)),
 add column is_draft boolean not null default false,
 add column draft_source_id uuid references public.video_jobs(id) on delete set null,
 add column provider_cost_usd numeric(20,8) check(provider_cost_usd>=0 and provider_cost_usd<=1000),
 add column completion_tokens bigint check(completion_tokens>=0),
 add column pricing_profile jsonb;

create function private.seedance25_charge(p_usd numeric) returns numeric
language sql immutable security invoker set search_path='' as $$select ceil(p_usd*7/0.38*1.05*2)/2;$$;
revoke all on function private.seedance25_charge(numeric) from public,anon,authenticated;
grant execute on function private.seedance25_charge(numeric) to service_role;

create function private.begin_seedance25_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_operation text,p_fingerprint text,p_parameters jsonb,p_references jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.video_jobs;s public.video_jobs;b numeric;res text;seconds integer:=0;ref_ms integer:=0;rate numeric:=0;
 estimate numeric:=0;reserve numeric:=0;final boolean:=false;v_draft boolean:=false;source_id uuid;prompt text:='';
begin
 if p_user_id is null or p_request_id is null or p_mode is null or p_mode not in ('platform','own_key')
  or p_owner is null or (p_mode='platform' and p_owner<>'user-'||p_user_id::text)
  or(p_mode='own_key' and p_owner !~ ('^user-'||p_user_id::text||'-[a-f0-9]{64}$'))
  or p_operation is null or p_operation not in ('generate','asset_review')
  or p_fingerprint is null or p_fingerprint !~ '^[a-f0-9]{64}$'
  or p_parameters is null or jsonb_typeof(p_parameters)<>'object' or p_parameters->>'model' is distinct from 'seedance-2.5'
  or p_parameters-array['model','prompt','duration','size','resolution','seed','generate_audio','return_last_frame','tools','nsfw_check',
       'draft','draft_request_id','output_format','watermark','omni_reference_task_type']<>'{}'::jsonb
  or p_references is null or jsonb_typeof(p_references)<>'array' or jsonb_array_length(p_references)>50 then
  return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
 if exists(select 1 from jsonb_array_elements(p_references) r where jsonb_typeof(r)<>'object'
   or r-array['id','kind','sha256','asset_url','role','duration_ms','width','height','fps','codec','size']<>'{}'::jsonb
   or r->>'kind' is null or r->>'kind' not in ('image','video','audio') or r->>'id' is null) then
  return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
 perform pg_advisory_xact_lock(hashtextextended(p_owner||':'||p_request_id::text,0));
 select * into j from public.video_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if found then
  if j.model<>'seedance-2.5' or j.operation<>p_operation or j.request_fingerprint<>p_fingerprint then return jsonb_build_object('ok',false,'code','VIDEO_REQUEST_CONFLICT');end if;
  return jsonb_build_object('ok',true,'existing',true,'job',to_jsonb(j));
 end if;
 if not exists(select 1 from auth.users where id=p_user_id and email_confirmed_at is not null) then return jsonb_build_object('ok',false,'code','EMAIL_UNVERIFIED');end if;
 if not exists(select 1 from public.profiles where id=p_user_id and status='active' and deleted_at is null) then return jsonb_build_object('ok',false,'code','ACCOUNT_FROZEN');end if;
 if p_operation='generate' then
  final:=p_parameters?'draft_request_id';res:=p_parameters->>'resolution';
  if res is null or res not in ('480p','720p','1080p') then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
  if final then
   if p_parameters-array['model','draft_request_id','resolution','output_format','return_last_frame','watermark']<>'{}'::jsonb
    or res<>'1080p' or jsonb_array_length(p_references)<>0
    or coalesce(p_parameters->>'draft_request_id','') !~ '^[a-f0-9-]{36}$' then return jsonb_build_object('ok',false,'code','VIDEO_DRAFT_INVALID');end if;
   select * into s from public.video_jobs where owner_scope=p_owner and user_id=p_user_id and request_id=(p_parameters->>'draft_request_id')::uuid
    and model='seedance-2.5' and is_draft and status='completed' and billing_status in ('settled','not_applicable') and created_at>statement_timestamp()-interval '7 days';
   if not found then return jsonb_build_object('ok',false,'code','VIDEO_DRAFT_INVALID');end if;
   seconds:=s.requested_duration;source_id:=s.id;prompt:=s.history_prompt;
  else
   if coalesce(p_parameters->>'duration','') !~ '^(-1|[4-9]|[12][0-9]|30)$'
    or jsonb_typeof(p_parameters->'prompt') is distinct from 'string' or char_length(p_parameters->>'prompt') not between 1 and 32000
    or (p_parameters->>'draft') not in ('true','false') then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
   seconds:=(p_parameters->>'duration')::integer;prompt:=p_parameters->>'prompt';v_draft:=(p_parameters->>'draft')::boolean;
   if v_draft and res<>'480p' then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');end if;
   if exists(select 1 from jsonb_array_elements(p_references) r where r->>'kind' in ('video','audio') and coalesce(r->>'duration_ms','') !~ '^[0-9]{1,5}$') then return jsonb_build_object('ok',false,'code','VIDEO_REFERENCE_DURATION');end if;
   select coalesce(sum((r->>'duration_ms')::integer),0) into ref_ms from jsonb_array_elements(p_references) r where r->>'kind'='video';
   if ref_ms>30000 then return jsonb_build_object('ok',false,'code','VIDEO_REFERENCE_DURATION');end if;
  end if;
  rate:=case res when '480p' then case when ref_ms>0 then 0.0576 else 0.09608 end
    when '720p' then case when ref_ms>0 then 0.1296 else 0.216 end
    else case when ref_ms>0 then 0.3192 else 0.5346 end end;
  estimate:=private.seedance25_charge((case when seconds=-1 then 30 else seconds end+ref_ms/1000.0)*rate);
  reserve:=private.seedance25_charge((case when seconds=-1 then 30 else seconds end+ref_ms/1000.0)*rate*1.6);
 elsif p_parameters<>'{"model":"seedance-2.5"}'::jsonb or jsonb_array_length(p_references)<>1 then return jsonb_build_object('ok',false,'code','INVALID_VIDEO_INPUT');
 end if;
 select balance into b from public.credit_accounts where user_id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');end if;
 if p_mode='platform' and exists(select 1 from public.video_jobs where user_id=p_user_id and billing_status='awaiting_balance') then return jsonb_build_object('ok',false,'code','VIDEO_UNSETTLED_BALANCE');end if;
 if (select count(*) from public.video_jobs where user_id=p_user_id and operation=p_operation and status not in ('completed','failed'))>=3 then return jsonb_build_object('ok',false,'code','VIDEO_QUEUE_FULL');end if;
 if p_mode='platform' and b<reserve then return jsonb_build_object('ok',false,'code','CREDITS_INSUFFICIENT','required',reserve,'balance',b);end if;
 if p_mode='platform' and reserve>0 then update public.credit_accounts set balance=balance-reserve,updated_at=now() where user_id=p_user_id returning balance into b;end if;
 insert into public.video_jobs(user_id,owner_scope,request_id,billing_mode,operation,model,request_fingerprint,billing_status,resolution,
  requested_duration,reference_duration_ms,unit_credit_cost,estimated_credits,reserved_credits,reference_metadata,history_prompt,history_parameters,history_created_at,
  is_draft,draft_source_id,pricing_profile)
 values(p_user_id,p_owner,p_request_id,p_mode,p_operation,'seedance-2.5',p_fingerprint,case when p_mode='platform' and reserve>0 then 'reserved' else 'not_applicable' end,res,
  seconds,ref_ms,0,estimate,case when p_mode='platform' then reserve else 0 end,p_references,prompt,case when p_operation='generate' then p_parameters else null end,
  case when p_operation='generate' then now() else null end,v_draft,source_id,'{"version":"seedance25-usd7-cny038-markup5-half-v1","usd_cny":"7","credit_cny":"0.38","markup":"1.05"}') returning * into j;
 if p_mode='platform' and reserve>0 then
  insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
  values(p_user_id,j.id,'reserve',-reserve,'video-reserve:'||j.id::text,jsonb_build_object('media_type','video','model',j.model,'pricing_profile',j.pricing_profile));
 end if;
 return jsonb_build_object('ok',true,'existing',false,'job',to_jsonb(j),'balance',b);
end;$$;
create function public.begin_seedance25_job(p_owner text,p_user_id uuid,p_request_id uuid,p_mode text,p_operation text,p_fingerprint text,p_parameters jsonb,p_references jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.begin_seedance25_job(p_owner,p_user_id,p_request_id,p_mode,p_operation,p_fingerprint,p_parameters,p_references);$$;

create function private.apply_seedance25_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_error_code text default null,
 p_assets jsonb default '[]',p_cost_usd numeric default null,p_tokens bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.video_jobs;b numeric;c numeric;gap numeric;usd numeric;r jsonb;
begin
 select * into j from public.video_jobs where owner_scope=p_owner and request_id=p_request_id for update;
 if not found or j.model<>'seedance-2.5' then return jsonb_build_object('ok',false,'code','VIDEO_NOT_FOUND');end if;
 if j.status='failed' or (j.status='completed' and j.billing_status<>'awaiting_balance') then return jsonb_build_object('ok',true,'job',to_jsonb(j));end if;
 if p_event='completed' and j.operation='asset_review' then
  if p_assets is null or jsonb_typeof(p_assets)<>'array' or jsonb_array_length(p_assets)<>1
   or p_assets#>>'{0,status}' is distinct from 'Active' or coalesce(p_assets#>>'{0,asset_url}','') !~ '^asset://[A-Za-z0-9_-]{4,160}$' then
   return jsonb_build_object('ok',false,'code','VIDEO_BAD_ASSET');end if;
  update public.video_jobs set status='completed',billing_status='not_applicable',last_checked_at=now(),settled_at=now(),
   asset_results=jsonb_build_array(j.reference_metadata->0||jsonb_build_object('asset_id',p_assets#>>'{0,asset_id}','asset_url',p_assets#>>'{0,asset_url}','status','Active'))
   where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j));
 end if;
 if p_event<>'completed' then
  if j.provider_cost_usd>0 and p_event in ('failed','rejected') then return jsonb_build_object('ok',false,'code','VIDEO_ALREADY_GENERATED');end if;
  return private.apply_video_job(p_owner,p_request_id,p_event,p_task_id,p_error_code,p_assets);
 end if;
 if j.billing_mode='own_key' then
  update public.video_jobs set status='completed',billing_status='not_applicable',generated_count=1,charged_credits=0,settled_at=now(),last_checked_at=now(),error_code=null where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j));
 end if;
 usd:=coalesce(j.provider_cost_usd,p_cost_usd);
 if usd is null or usd=0 then
  update public.video_jobs set status='processing',billing_status='awaiting_provider',last_checked_at=now() where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j),'billing_pending',true);
 end if;
 if usd='NaN'::numeric or usd<0 or usd>1000 or (p_tokens is not null and p_tokens<0) then return jsonb_build_object('ok',false,'code','VIDEO_BILLING_INVALID');end if;
 usd:=ceil(usd*100000000)/100000000;
 c:=ceil(usd*(j.pricing_profile->>'usd_cny')::numeric/(j.pricing_profile->>'credit_cny')::numeric*(j.pricing_profile->>'markup')::numeric*2)/2;gap:=c-j.reserved_credits;
 select balance into b from public.credit_accounts where user_id=j.user_id for update;
 if b<gap then
  update public.video_jobs set status='completed',billing_status='awaiting_balance',provider_cost_usd=usd,completion_tokens=p_tokens,generated_count=1,last_checked_at=now() where id=j.id returning * into j;
  return jsonb_build_object('ok',true,'job',to_jsonb(j),'required_credits',gap-b,'final_credits',c);
 end if;
 update public.credit_accounts set balance=balance-gap,total_spent=total_spent+c,total_refunded=total_refunded+greatest(-gap,0),updated_at=now() where user_id=j.user_id returning balance into b;
 if gap<>0 then
  insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
  values(j.user_id,j.id,case when gap<0 then 'refund' else 'reserve' end,-gap,'video25-adjust:'||j.id::text,jsonb_build_object('media_type','video','settlement_difference',true));
 end if;
 insert into public.credit_transactions(user_id,video_job_id,type,delta,idempotency_key,metadata)
 values(j.user_id,j.id,'spend',0,'video-spend:'||j.id::text,jsonb_build_object('media_type','video','charged_credits',c,'provider_cost_usd',usd,'pricing_profile',j.pricing_profile));
 update public.video_jobs set status='completed',billing_status='settled',charged_credits=c,provider_cost_usd=usd,completion_tokens=p_tokens,generated_count=1,last_checked_at=now(),settled_at=now(),error_code=null where id=j.id returning * into j;
 return jsonb_build_object('ok',true,'job',to_jsonb(j),'balance',b);
end;$$;
create function public.apply_seedance25_job(p_owner text,p_request_id uuid,p_event text,p_task_id text default null,p_error_code text default null,
 p_assets jsonb default '[]',p_cost_usd numeric default null,p_tokens bigint default null)
returns jsonb language sql security invoker set search_path='' as $$select private.apply_seedance25_job(p_owner,p_request_id,p_event,p_task_id,p_error_code,p_assets,p_cost_usd,p_tokens);$$;
revoke all on function private.begin_seedance25_job(text,uuid,uuid,text,text,text,jsonb,jsonb),public.begin_seedance25_job(text,uuid,uuid,text,text,text,jsonb,jsonb),
 private.apply_seedance25_job(text,uuid,text,text,text,jsonb,numeric,bigint),public.apply_seedance25_job(text,uuid,text,text,text,jsonb,numeric,bigint) from public,anon,authenticated;
grant execute on function private.begin_seedance25_job(text,uuid,uuid,text,text,text,jsonb,jsonb),public.begin_seedance25_job(text,uuid,uuid,text,text,text,jsonb,jsonb),
 private.apply_seedance25_job(text,uuid,text,text,text,jsonb,numeric,bigint),public.apply_seedance25_job(text,uuid,text,text,text,jsonb,numeric,bigint) to service_role;
