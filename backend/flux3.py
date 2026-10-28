"""FLUX 3 Video: ordered keyframes, MP4 continuation and separate draft billing."""
import uuid
from decimal import Decimal

try:
    from backend.video_provider import VideoError, video_text, TASK_ID
    from backend.music_provider import safe_media_url
    from backend.seedance20 import cost_credits
except ModuleNotFoundError:
    from video_provider import VideoError, video_text, TASK_ID
    from music_provider import safe_media_url
    from seedance20 import cost_credits

MODEL='flux-3-video'
PROFILE={'version':'flux3-usd7-cny038-markup20-half-v1','usd_cny':'7','credit_cny':'0.38','markup':'1.2'}
RATES={'draft':Decimal('.048'),'v2v-draft':Decimal('.096'),'hd':Decimal('.136'),'fhd':Decimal('.232'),'v2v-hd':Decimal('.328'),'v2v-fhd':Decimal('.424')}
RATIOS={'auto','21:9','2:1','16:9','4:3','1:1','3:4','9:16'}

def normalized_parameters(data):
    if not isinstance(data,dict) or data.get('model')!=MODEL:raise VideoError('INVALID_VIDEO_MODEL','请选择 FLUX 3 Video。')
    res=data.get('resolution','hd')
    if not isinstance(res,str) or res not in {'hd','fhd'}:raise VideoError('INVALID_VIDEO_INPUT','FLUX 支持 HD / FHD，草稿仅 HD。')
    if 'draft_request_id' in data:
        if set(data)-{'model','resolution','draft_request_id'}:raise VideoError('VIDEO_DRAFT_INVALID','草稿转正式片只能修改清晰度，不能重新提交提示词、时长或素材。')
        try:rid=str(uuid.UUID(data['draft_request_id']))
        except (ValueError,TypeError,AttributeError):raise VideoError('VIDEO_DRAFT_INVALID','请选择本人已完成并结算的 FLUX 草稿。') from None
        return {'model':MODEL,'resolution':res,'draft_request_id':rid}
    if set(data)-{'model','resolution','prompt','duration','aspect_ratio','audio','draft','safety_tolerance','nsfw_check'}:raise VideoError('INVALID_VIDEO_INPUT','请求包含 FLUX 未支持的参数。')
    duration=data.get('duration',5);ratio=data.get('aspect_ratio','auto');safety=data.get('safety_tolerance',2)
    if type(duration) is not int or not 5<=duration<=20 or not isinstance(ratio,str) or ratio not in RATIOS or type(safety) is not int or not 0<=safety<=4:
        raise VideoError('INVALID_VIDEO_INPUT','FLUX 支持 5–20 秒整数、列表中的画幅及 0–4 的审核容忍度。')
    body={'model':MODEL,'resolution':res,'prompt':video_text(data.get('prompt',''),'提示词',32000),'duration':duration,'aspect_ratio':ratio,'safety_tolerance':safety}
    for key,default in [('audio',True),('draft',False),('nsfw_check',False)]:
        value=data.get(key,default)
        if type(value) is not bool:raise VideoError('INVALID_VIDEO_INPUT','FLUX 开关须为布尔值。')
        body[key]=value
    if body['draft'] and res!='hd':raise VideoError('INVALID_VIDEO_INPUT','FLUX 草稿仅支持 HD。')
    return body

def validate_references(refs,body,require_content=True):
    if not isinstance(refs,list) or len(refs)>10 or any(not isinstance(r,dict) for r in refs):raise VideoError('VIDEO_REFERENCE_COUNT','FLUX 支持最多 10 张有序关键帧，或 1 段 MP4 视频。')
    images=[r for r in refs if r.get('kind')=='image'];videos=[r for r in refs if r.get('kind')=='video']
    if len(images)+len(videos)!=len(refs) or len(videos)>1 or images and videos:raise VideoError('VIDEO_REFERENCE_INVALID','请选择有序图片或一段 MP4；视频续写不能同时使用关键帧，不支持参考音频。')
    if body.get('draft_request_id') and refs:raise VideoError('VIDEO_DRAFT_INVALID','正式片继承草稿素材，不能重新上传素材。')
    for r in refs:
        if not isinstance(r.get('id'),str) or not r['id'] or r.get('asset_url') or r.get('role'):raise VideoError('VIDEO_REFERENCE_INVALID','FLUX 按图片列表顺序确定关键帧，不使用其他模型的图片角色或审核素材。')
        limit=16*1024*1024 if r['kind']=='image' else 50*1024*1024
        if type(r.get('size')) is not int or not 0<r['size']<=limit:raise VideoError('VIDEO_REFERENCE_SIZE','本站限制图片 16 MB、视频 50 MB。')
        if any(type(r.get(k)) is not int or r[k]<1 for k in ('width','height')) or r['width']*r['height']>32000000:raise VideoError('VIDEO_REFERENCE_RESOLUTION','素材无法识别或超过本站 3200 万像素限制。')
        if r['kind']=='video' and (not r['id'].lower().endswith('.mp4') or type(r.get('duration_ms')) is not int or not 0<r['duration_ms']<=30000):raise VideoError('VIDEO_REFERENCE_FORMAT','续写素材须为 MP4；本站暂限 30 秒、50 MB。')
    # Repeated keyframes are intentional; do not dedupe or reorder images.
    if require_content and not body.get('draft_request_id') and not body.get('prompt'):raise VideoError('INVALID_VIDEO_INPUT','FLUX 文生、图生及视频续写均需要提示词。')
    return sum(r['duration_ms'] for r in videos)

def validate_source(source):
    if not source or source.get('model')!=MODEL or not source.get('is_draft') or source.get('status')!='completed' or source.get('billing_status') not in {'settled','not_applicable'} or not str(source.get('provider_task_id') or '').startswith('task_') or not TASK_ID.fullmatch(source.get('provider_task_id') or '') or type(source.get('requested_duration')) is not int or not 5<=source['requested_duration']<=20:
        raise VideoError('VIDEO_DRAFT_INVALID','请选择本人已完成并结算的 FLUX 草稿。')

def estimate(body,refs,source=None,require_content=True):
    ms=validate_references(refs,body,require_content)
    if body.get('draft_request_id'):
        validate_source(source);seconds=source['requested_duration'];continuation=source.get('pricing_profile',{}).get('continuation') is True
    else:seconds=body['duration'];continuation=any(r['kind']=='video' for r in refs)
    variant=('v2v-' if continuation else '')+('draft' if body.get('draft') else body['resolution'])
    usd=seconds*RATES[variant]
    return {'estimated':cost_credits(usd),'reserved':cost_credits(usd*Decimal('1.6')),'estimated_usd':usd,'reference_ms':ms,'profile':{**PROFILE,'continuation':continuation}}

def payload(body,refs,urls,source=None):
    validate_references(refs,body)
    if body.get('draft_request_id'):
        validate_source(source)
        return {'model':MODEL,'resolution':body['resolution'],'draft_from_task_id':source['provider_task_id']}
    if len(refs)!=len(urls) or any(not safe_media_url(u) for u in urls):raise VideoError('VIDEO_REFERENCE_INVALID','尚未取得有效素材地址。')
    result={**body}
    if refs and refs[0]['kind']=='image':result['image_urls']=list(urls)
    elif refs:result['video_url']=urls[0]
    return result
