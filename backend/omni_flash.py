"""Gemini Omni 1.1 Flash's independent, documented video contract."""
import uuid
from decimal import Decimal

try:
    from backend.video_provider import VideoError, video_text, TASK_ID
    from backend.seedance20 import cost_credits
except ModuleNotFoundError:
    from video_provider import VideoError, video_text, TASK_ID
    from seedance20 import cost_credits

MODEL = 'gemini-omni-1.1-flash'
PROFILE = {'version':'omni11-usd7-cny038-markup20-half-v1','usd_cny':'7','credit_cny':'0.38','markup':'1.2'}
# APIMart Gold per-second output estimates. Input tokens also cost money;
# never use this estimate to settle a task (only the trusted final USD cost).
RATES = {'360p':Decimal('.0296'),'720p':Decimal('.088'),'1080p':Decimal('.132'),'4k':Decimal('.264')}
TASKS = {'auto','text_to_video','image_to_video','reference_to_video','edit','extend'}


def normalized_parameters(data):
    allowed = {'model','prompt','resolution','aspect_ratio','task','continue_request_id'}
    if not isinstance(data,dict) or set(data)-allowed or data.get('model')!=MODEL:
        raise VideoError('INVALID_VIDEO_MODEL','请选择 Gemini Omni 支持的参数；时长由模型自动决定。')
    res=data.get('resolution','720p');ratio=data.get('aspect_ratio','16:9');task=data.get('task','auto')
    if not all(isinstance(x,str) for x in [res,ratio,task]) or res not in RATES or ratio not in {'16:9','9:16'} or task not in TASKS:
        raise VideoError('INVALID_VIDEO_INPUT','Omni 支持 360P / 720P / 1080P / 4K、横屏或竖屏和列表中的创作方式。')
    body={'model':MODEL,'prompt':video_text(data.get('prompt',''),'提示词',32000),'resolution':res,'aspect_ratio':ratio,'task':task}
    if data.get('continue_request_id'):
        try:body['continue_request_id']=str(uuid.UUID(data['continue_request_id']))
        except (TypeError,ValueError,AttributeError):raise VideoError('VIDEO_CONTINUATION_INVALID','请选择本人已完成并结算的 Omni 任务。') from None
    return body


def validate_references(refs,body):
    if not isinstance(refs,list) or len(refs)>11 or any(not isinstance(r,dict) or not isinstance(r.get('id'),str) for r in refs):
        raise VideoError('VIDEO_REFERENCE_COUNT','Omni 最多 10 张图片和 1 段视频，不支持参考音频。')
    if len({r['id'] for r in refs})!=len(refs):raise VideoError('VIDEO_REFERENCE_INVALID','同一素材不能重复添加。')
    images=[r for r in refs if r.get('kind')=='image'];videos=[r for r in refs if r.get('kind')=='video']
    if len(images)+len(videos)!=len(refs) or len(images)>10 or len(videos)>1:
        raise VideoError('VIDEO_REFERENCE_COUNT','Omni 最多 10 张图片和 1 段视频，不支持参考音频。')
    if any(r.get('asset_url') for r in refs):raise VideoError('VIDEO_REFERENCE_INVALID','Omni 仅支持上传或链接导入的图片和视频，不支持 Seedance 审核素材。')
    for r in images:
        w,h=r.get('width'),r.get('height')
        if type(w) is not int or type(h) is not int or min(w,h)<1 or w*h>32000000:
            raise VideoError('VIDEO_REFERENCE_RESOLUTION','图片无法识别或超出本站 3200 万像素限制。')
        if r.get('role') not in {None,'','first_frame','last_frame'}:raise VideoError('VIDEO_REFERENCE_ROLE','请选择普通参考、首帧或尾帧。')
    if any(r.get('role') for r in videos):raise VideoError('VIDEO_REFERENCE_ROLE','首尾帧角色仅用于图片。')
    roles=[r.get('role') for r in images if r.get('role')]
    if len(set(roles))!=len(roles) or ('last_frame' in roles and 'first_frame' not in roles):
        raise VideoError('VIDEO_REFERENCE_ROLE','尾帧必须同时配有首帧，首帧和尾帧各一张。')
    for r in videos:
        if type(r.get('duration_ms')) is not int or not 0<r['duration_ms']<=10000:
            raise VideoError('VIDEO_REFERENCE_DURATION','Omni 参考视频最多 10 秒，请截短后重新添加。')
    if body.get('continue_request_id') and videos:raise VideoError('VIDEO_CONTINUATION_INVALID','继续已有任务和上传参考视频只能选择一种。')
    task=body.get('task','auto')
    if task=='text_to_video' and (refs or body.get('continue_request_id')):raise VideoError('VIDEO_TASK_CONSTRAINT','文生视频方式只使用提示词，请选择自动判断或其他创作方式。')
    if task in {'image_to_video','reference_to_video'} and not images:raise VideoError('VIDEO_TASK_CONSTRAINT','图像或参考创作需要添加图片。')
    if task in {'edit','extend'} and not(videos or body.get('continue_request_id')):raise VideoError('VIDEO_TASK_CONSTRAINT','编辑或续写需要上传一段视频，或选择本人已完成的 Omni 任务。')
    return sum(r['duration_ms'] for r in videos)


def estimate(body,refs):
    ref_ms=validate_references(refs,body)
    usd=RATES[body['resolution']]*10
    return {'estimated':cost_credits(usd),'reserved':cost_credits(usd*Decimal('1.6')),
            'estimated_usd':usd,'reference_ms':ref_ms,'profile':PROFILE}


def payload(body,refs,urls,source=None):
    validate_references(refs,body)
    try:from backend.music_provider import safe_media_url
    except ModuleNotFoundError:from music_provider import safe_media_url
    if len(refs)!=len(urls) or any(not safe_media_url(u) for u in urls):raise VideoError('VIDEO_REFERENCE_INVALID','尚未取得有效素材地址。')
    if not body['prompt'] and not refs and not source:raise VideoError('INVALID_VIDEO_INPUT','请填写提示词或添加图片、视频素材。')
    result={k:body[k] for k in ['model','prompt','resolution','aspect_ratio']};images=[];videos=[];frames={}
    for r,url in zip(refs,urls):
        if r['kind']=='video':videos.append(url)
        elif r.get('role'):frames[r['role']+'_image']=url
        else:images.append(url)
    if images:result['image_urls']=images
    if videos:result['video_urls']=videos
    result.update(frames)
    if source:
        if source.get('model')!=MODEL or source.get('status')!='completed' or source.get('billing_status') not in {'settled','not_applicable'} or not TASK_ID.fullmatch(source.get('provider_task_id') or ''):
            raise VideoError('VIDEO_CONTINUATION_INVALID','请选择本人已完成并结算的 Omni 任务。')
        result['extend_from_task_id']=source['provider_task_id']
    elif body.get('continue_request_id'):raise VideoError('VIDEO_CONTINUATION_INVALID','未找到本人已完成的 Omni 任务。')
    if not frames and body['task']!='auto':result['metadata']={'task':body['task']}
    return result
