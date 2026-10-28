"""MiniMax H3 generation: independent media contract and real-USD billing."""
from decimal import Decimal

try:
    from backend.video_provider import VideoError, video_text, SIZES
    from backend.seedance20 import cost_credits
    from backend.music_provider import safe_media_url
except ModuleNotFoundError:
    from video_provider import VideoError, video_text, SIZES
    from seedance20 import cost_credits
    from music_provider import safe_media_url

MODEL = 'MiniMax-H3'
MAX_MODEL = 'MiniMax-H3-Max'
MODELS = {MODEL, MAX_MODEL}
PROFILE = {'version':'minimax-h3-usd7-cny038-markup20-half-v1','usd_cny':'7','credit_cny':'0.38','markup':'1.2'}
MAX_PROFILE = {**PROFILE,'version':'minimax-h3-max-usd7-cny038-markup20-half-v1'}
RATES = {'768p':Decimal('.05712'),'2k':Decimal('.09144')}
MAX_RATES = {'480p':Decimal('.03768'),'768p':Decimal('.05712'),'1080p':Decimal('.128')}
MAX_REFERENCE_RATES = {'480p':Decimal('.04232'),'768p':Decimal('.11088'),'1080p':Decimal('.11936')}
IMAGE_RATE = Decimal('.02288')
MAX_IMAGE_RATE = Decimal('.05712')
LIMITS = {'image':30*1024*1024,'video':50*1024*1024,'audio':15*1024*1024}


def normalized_parameters(data):
    if not isinstance(data,dict) or not isinstance(data.get('model'),str) or data.get('model') not in MODELS:
        raise VideoError('INVALID_VIDEO_MODEL','请选择 MiniMax H3 支持的参数。')
    maximum=data['model']==MAX_MODEL
    allowed = {'model','prompt','duration','size','resolution','watermark'} | (set() if maximum else {'nsfw_check'})
    if set(data)-allowed:raise VideoError('INVALID_VIDEO_INPUT','请选择当前 MiniMax 型号支持的参数。')
    res=data.get('resolution','768p' if maximum else '2k');size=data.get('size','16:9');duration=data.get('duration',5)
    rates=MAX_RATES if maximum else RATES
    if not isinstance(res,str) or res not in rates or not isinstance(size,str) or size not in SIZES or type(duration) is not int or not (5 if maximum else 4)<=duration<=15:
        raise VideoError('INVALID_VIDEO_INPUT','H3 Max 支持 480P / 768P / 1080P、5–15 秒整数时长及列表中的画幅。' if maximum else 'H3 支持 768P / 2K、4–15 秒整数时长及列表中的画幅。')
    if maximum and res=='1080p' and 'watermark' in data:
        raise VideoError('INVALID_VIDEO_INPUT','H3 Max 的 1080P 不支持水印，请移除水印参数（即使为 false 也不能发送）。')
    prompt=video_text(data.get('prompt',''),'提示词',7000)
    if not prompt:raise VideoError('INVALID_VIDEO_INPUT','H3 的所有创作方式都需要填写提示词，最多 7000 个字符。')
    body={'model':data['model'],'prompt':prompt,'duration':duration,'size':size,'resolution':res}
    keys=(() if res=='1080p' else ('watermark',)) if maximum else ('watermark','nsfw_check')
    for key in keys:
        value=data.get(key,False)
        if type(value) is not bool:raise VideoError('INVALID_VIDEO_INPUT','视频开关参数无效。')
        body[key]=value
    return body


def validate_image(width,height):
    if type(width) is not int or type(height) is not int or not 256<=width<=5760 or not 256<=height<=5760 or not .4<=width/height<=2.5:
        raise VideoError('VIDEO_REFERENCE_RESOLUTION','H3 参考图片和视频宽高须为 256–5760 像素，宽高比须为 0.4–2.5。')


def validate_references(refs,body=None):
    if not isinstance(refs,list) or len(refs)>15 or any(not isinstance(r,dict) or not isinstance(r.get('id'),str) or not r.get('id') for r in refs):
        raise VideoError('VIDEO_REFERENCE_COUNT','H3 最多 9 张参考图、3 段视频和 3 段音频。')
    groups={k:[r for r in refs if r.get('kind')==k] for k in LIMITS}
    if sum(map(len,groups.values()))!=len(refs) or any(len(groups[k])>n for k,n in [('image',9),('video',3),('audio',3)]):
        raise VideoError('VIDEO_REFERENCE_COUNT','H3 最多 9 张参考图、3 段视频和 3 段音频。')
    if len({r['id'] for r in refs})!=len(refs):raise VideoError('VIDEO_REFERENCE_INVALID','同一素材不能重复添加。')
    if any(r.get('asset_url') for r in refs):raise VideoError('VIDEO_REFERENCE_INVALID','H3 不支持 Seedance 审核素材，请直接上传或链接导入。')
    for r in refs:
        if type(r.get('size')) is not int or not 0<r['size']<=LIMITS[r['kind']]:
            raise VideoError('VIDEO_REFERENCE_SIZE','H3 图片最多 30 MB、视频 50 MB、音频 15 MB，请重新上传不符合要求的素材。')
        if r.get('role') is not None and (not isinstance(r['role'],str) or r['role'] and (r['kind']!='image' or r['role'] not in {'first_frame','last_frame','reference_image'})):
            raise VideoError('VIDEO_REFERENCE_ROLE','H3 图片角色无效。')
    frames=[r for r in groups['image'] if r.get('role') in {'first_frame','last_frame'}]
    if frames and (len(frames)!=len(refs) or len({r['role'] for r in frames})!=len(frames)):
        raise VideoError('VIDEO_REFERENCE_ROLE','H3 首尾帧各最多一张，不能与普通参考图、参考视频或音频混用。')
    if groups['audio'] and not(groups['image'] or groups['video']):
        raise VideoError('VIDEO_REFERENCE_AUDIO','H3 参考音频须搭配普通参考图片或视频。')
    for r in groups['image']+groups['video']:validate_image(r.get('width'),r.get('height'))
    for kind in ('video','audio'):
        values=[r.get('duration_ms') for r in groups[kind]]
        if any(type(v) is not int or not 2000<=v<=15000 for v in values) or sum(values)>15000:
            raise VideoError('VIDEO_REFERENCE_DURATION','H3 视频和音频每段须为 2–15 秒，两类素材各自合计最多 15 秒。')
    for r in groups['video']:
        fps=r.get('fps')
        maximum=isinstance(body,dict) and body.get('model')==MAX_MODEL
        if type(fps) not in (int,float) or not 23.976<=fps<=60 or r.get('codec') not in {'avc1','avc3','hvc1','hev1'} or not maximum and (not isinstance(r.get('audio_codecs'),list) or any(c not in {'mp4a','.mp3','mp3 ','mp3'} for c in r.get('audio_codecs',[]))):
            raise VideoError('VIDEO_REFERENCE_FORMAT','H3 Max 参考视频须为 H.264 / H.265、23.976–60 FPS。' if maximum else 'H3 参考视频须为 H.264 / H.265、23.976–60 FPS，音轨仅支持 AAC / MP3。')
    return sum(r['duration_ms'] for r in groups['video'])


def estimate(body,refs):
    ms=validate_references(refs,body)
    maximum=body['model']==MAX_MODEL
    extras=max(0,sum(r['kind']=='image' for r in refs)-(2 if maximum else 5))
    rates=MAX_RATES if maximum else RATES
    reference_rates=MAX_REFERENCE_RATES if maximum else RATES
    usd=Decimal(body['duration'])*rates[body['resolution']]+Decimal(ms)/1000*reference_rates[body['resolution']]+extras*(MAX_IMAGE_RATE if maximum else IMAGE_RATE)
    return {'estimated':cost_credits(usd),'reserved':cost_credits(usd*Decimal('1.6')),
            'estimated_usd':usd,'reference_ms':ms,'profile':MAX_PROFILE if maximum else PROFILE}


def payload(body,refs,urls):
    validate_references(refs,body)
    if len(refs)!=len(urls) or any(not safe_media_url(u) for u in urls):raise VideoError('VIDEO_REFERENCE_INVALID','尚未取得有效素材地址。')
    result={k:body[k] for k in ('model','prompt','duration','watermark','nsfw_check') if k in body}
    result['resolution']=body['resolution'].upper()
    frames=any(r.get('role') in {'first_frame','last_frame'} for r in refs)
    result['aspect_ratio']='adaptive' if frames else '16:9' if not refs and body['size']=='adaptive' else body['size']
    for kind,field in [('image','image_urls'),('video','video_urls'),('audio','audio_urls')]:
        values=[]
        for r,url in zip(refs,urls):
            if r['kind']!=kind:continue
            if frames:result[r['role']+'_image']=url
            else:values.append(url)
        if values:result[field]=values
    return result
