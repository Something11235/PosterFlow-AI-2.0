"""Wan 3.0's documented reference/frame families and actual-USD billing."""
import re
from decimal import Decimal

try:
    from backend.video_provider import VideoError, video_text
    from backend.music_provider import safe_media_url
    from backend.seedance20 import cost_credits
except ModuleNotFoundError:
    from video_provider import VideoError, video_text
    from music_provider import safe_media_url
    from seedance20 import cost_credits

MODEL='wan3.0-video'
PROFILE={'version':'wan30-usd7-cny038-markup20-half-v1','usd_cny':'7','credit_cny':'0.38','markup':'1.2'}
RATES={'480p':Decimal('.03288'),'720p':Decimal('.06575'),'1080p':Decimal('.1315')}
SIZES={'adaptive','16:9','4:3','1:1','3:4','9:16'}
LIMITS={'image':20*1024*1024,'video':100*1024*1024,'audio':15*1024*1024,'document':100*1024*1024}
DOCUMENTS={'docx','doc','xlsx','xls','pptx','ppt','pdf','txt','key','pages','numbers','md'}


def normalized_parameters(data):
    allowed={'model','prompt','resolution','size','duration','audio','seed','watermark','nsfw_check','link_url'}
    if not isinstance(data,dict) or data.get('model')!=MODEL or set(data)-allowed:
        raise VideoError('INVALID_VIDEO_INPUT','请选择 Wan 3.0 支持的参数。')
    res=data.get('resolution','1080p');size=data.get('size','adaptive');duration=data.get('duration',5)
    if not isinstance(res,str) or res not in RATES or not isinstance(size,str) or size not in SIZES or type(duration) is not int or duration!=-1 and not 2<=duration<=30:
        raise VideoError('INVALID_VIDEO_INPUT','Wan 支持 480P / 720P / 1080P、2–30 秒或自动时长和列表中的画幅。')
    body={'model':MODEL,'prompt':video_text(data.get('prompt',''),'提示词',20000),'resolution':res,'size':size,'duration':duration}
    for key,default in [('audio',True),('watermark',False),('nsfw_check',False)]:
        value=data.get(key,default)
        if type(value) is not bool:raise VideoError('INVALID_VIDEO_INPUT','Wan 开关参数须为布尔值。')
        body[key]=value
    if 'seed' in data:
        seed=data['seed']
        if type(seed) is not int or not 0<=seed<=2147483647:raise VideoError('INVALID_VIDEO_INPUT','Wan 随机种子须为 0–2147483647 的整数。')
        body['seed']=seed
    if 'link_url' in data and not isinstance(data['link_url'],str):raise VideoError('VIDEO_REFERENCE_URL','网页链接须为 HTTPS 字符串。')
    if data.get('link_url'):
        url=safe_media_url(data['link_url'])
        if not url:raise VideoError('VIDEO_REFERENCE_URL','请输入无需登录、可公开读取的 HTTPS 网页链接。')
        body['link_url']=url
    return body


def validate_dimensions(width,height,kind='image'):
    maximum=8000 if kind=='image' else 4096
    if type(width) is not int or type(height) is not int or not 240<=width<=maximum or not 240<=height<=maximum or not .125<=width/height<=8:
        raise VideoError('VIDEO_REFERENCE_RESOLUTION',f'Wan {"图片" if kind=="image" else "视频"}宽高须为 240–{maximum} 像素，长边与短边之比不能超过 8:1。')


def validate_references(refs,body,require_content=True):
    if not isinstance(refs,list) or len(refs)>21 or any(not isinstance(r,dict) or not isinstance(r.get('id'),str) or not r['id'] for r in refs):
        raise VideoError('VIDEO_REFERENCE_COUNT','Wan 最多 10 图 / 5 视频 / 5 音频 / 1 文档。')
    groups={kind:[r for r in refs if r.get('kind')==kind] for kind in LIMITS}
    if sum(map(len,groups.values()))!=len(refs) or any(len(groups[k])>n for k,n in [('image',10),('video',5),('audio',5),('document',1)]):
        raise VideoError('VIDEO_REFERENCE_COUNT','Wan 最多 10 图 / 5 视频 / 5 音频 / 1 文档。')
    if len({r['id'] for r in refs})!=len(refs) or any(r.get('asset_url') for r in refs):
        raise VideoError('VIDEO_REFERENCE_INVALID','请使用不重复的本人上传素材；Wan 不支持 Seedance 审核素材。')
    for r in refs:
        role=r.get('role')
        if role is not None and (not isinstance(role,str) or role and (r['kind']!='image' or role not in {'first_frame','last_frame','reference_image'})):
            raise VideoError('VIDEO_REFERENCE_ROLE','Wan 图片角色无效。')
        if type(r.get('size')) is not int or not 0<r['size']<=LIMITS[r['kind']]:
            raise VideoError('VIDEO_REFERENCE_SIZE','Wan 图片最多 20 MB、视频/文档 100 MB、音频 15 MB。')
        if r['kind'] in {'image','video'}:validate_dimensions(r.get('width'),r.get('height'),r['kind'])
        if r['kind']=='image' and r.get('has_alpha'):
            raise VideoError('VIDEO_REFERENCE_FORMAT','Wan 不支持带透明通道的 PNG，请先转换为不透明 PNG 或 JPG。')
        if r['kind']=='document' and r.get('pages') is not None and (type(r['pages']) is not int or not 1<=r['pages']<=50):
            raise VideoError('VIDEO_REFERENCE_PAGES','参考文档最多 50 页，请拆分后上传。')
    frames=[r for r in groups['image'] if r.get('role') in {'first_frame','last_frame'}]
    if frames and (len(frames)!=len(refs) or body.get('link_url') or len({r['role'] for r in frames})!=len(frames) or not any(r['role']=='first_frame' for r in frames)):
        raise VideoError('VIDEO_REFERENCE_ROLE','Wan 首帧必选、尾帧可选，各最多一张；不能与普通参考图、视频、音频、文档或网页混用。')
    if groups['document'] and body.get('link_url'):raise VideoError('VIDEO_REFERENCE_INVALID','文档与网页只能选择一种。')
    for kind in ('video','audio'):
        values=[r.get('duration_ms') for r in groups[kind]]
        if any(type(v) is not int or not 1000<=v<=15000 for v in values) or sum(values)>15000:
            raise VideoError('VIDEO_REFERENCE_DURATION','Wan 视频和音频每段 1–15 秒，两类各自合计最多 15 秒。')
    ms=sum(r['duration_ms'] for r in groups['video'])
    if body.get('duration',5)!=-1 and ms+body.get('duration',5)*1000>30000:
        raise VideoError('VIDEO_REFERENCE_DURATION','参考视频总时长加生成时长不能超过 30 秒，请缩短时长。')
    counts={'图片':len(groups['image']),'视频':len(groups['video']),'音频':len(groups['audio'])}
    if any(int(n)>counts[k] for k,n in re.findall(r'@(图片|视频|音频)([1-9]\d*)',body.get('prompt',''))):
        raise VideoError('VIDEO_REFERENCE_INVALID','提示词引用的素材编号不存在，请修改或重新添加素材。')
    if require_content and not(body.get('prompt') or refs or body.get('link_url')):
        raise VideoError('INVALID_VIDEO_INPUT','请填写提示词，或添加参考素材、文档或网页。')
    return ms


def estimate(body,refs,require_content=True):
    ms=validate_references(refs,body,require_content)
    seconds=Decimal(30) if body['duration']==-1 else Decimal(body['duration'])+Decimal(ms)/1000
    usd=seconds*RATES[body['resolution']]
    return {'estimated':cost_credits(usd),'reserved':cost_credits(usd*Decimal('1.6')),'estimated_usd':usd,'reference_ms':ms,'profile':PROFILE}


def payload(body,refs,urls):
    validate_references(refs,body)
    if len(refs)!=len(urls) or any(not safe_media_url(url) for url in urls):raise VideoError('VIDEO_REFERENCE_INVALID','尚未取得有效素材地址。')
    result={k:v for k,v in body.items() if k!='resolution'};result['resolution']=body['resolution'].upper()
    result['prompt']=re.sub(r'@(图片|视频|音频)([1-9]\d*)',lambda m:('图' if m[1]=='图片' else m[1])+m[2],body['prompt'])
    images=[{'url':url,'role':r.get('role') or 'reference_image'} for r,url in zip(refs,urls) if r['kind']=='image']
    if images:result['image_with_roles']=images
    for kind,field in [('video','video_urls'),('audio','audio_urls')]:
        values=[url for r,url in zip(refs,urls) if r['kind']==kind]
        if values:result[field]=values
    for r,url in zip(refs,urls):
        if r['kind']=='document':result['file_url']=url
    # Explicit roles prevent a normal single image becoming a first frame.
    if images:result['generation_type']='frame' if any(i['role']=='first_frame' for i in images) else 'reference'
    return result
