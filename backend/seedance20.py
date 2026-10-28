"""Seedance 2.0 standard/Fast: documented controls and actual-USD settlement."""
from decimal import Decimal
try:
    from backend.video_provider import MODEL as MINI, VideoError, normalized_video_parameters, validate_video_references
    from backend.seedance25 import half_credit, actual_cost
except ModuleNotFoundError:
    from video_provider import MODEL as MINI, VideoError, normalized_video_parameters, validate_video_references
    from seedance25 import half_credit, actual_cost

MODEL = 'seedance-2.0'
FAST_MODEL = 'seedance-2.0-fast'
MODELS = {MODEL, FAST_MODEL}
PROFILE = {'version':'seedance20-usd7-cny038-markup20-half-v2','usd_cny':'7','credit_cny':'0.38','markup':'1.2'}
FAST_PROFILE = {'version':'seedance20fast-usd7-cny038-markup20-half-v1','usd_cny':'7','credit_cny':'0.38','markup':'1.2'}
# Official Gold USD rates: no input video / with input video. Estimates only.
RATES = {'480p':(Decimal('0.066'),Decimal('0.04')),
         '720p':(Decimal('0.142'),Decimal('0.08584')),
         '1080p':(Decimal('0.3544'),Decimal('0.21568')),
         '4k':(Decimal('0.722'),Decimal('0.44432'))}
FAST_RATES = {'480p':(Decimal('0.03984'),Decimal('0.02368')),
              '720p':(Decimal('0.0856'),Decimal('0.05128'))}


def cost_credits(usd):
    if not isinstance(usd,Decimal) or not usd.is_finite() or not 0<=usd<=1000:
        raise VideoError('VIDEO_BILLING_INVALID','视频计费结果暂不可用，请查询原任务。',502)
    return half_credit(usd*Decimal('7')/Decimal('0.38')*Decimal('1.2'))


def normalized_parameters(data):
    if not isinstance(data,dict) or data.get('model') not in MODELS:
        raise VideoError('INVALID_VIDEO_MODEL','请选择 Seedance 2.0 或 Fast。')
    model=data['model'];fast=model==FAST_MODEL
    resolution=data.get('resolution','720p')
    if resolution not in (FAST_RATES if fast else RATES):
        raise VideoError('INVALID_VIDEO_INPUT','Seedance 2.0 Fast 仅支持 480P、720P。' if fast else 'Seedance 2.0 支持 480P、720P、1080P 和 4K。')
    # Same documented controls as Mini, with a separate prompt/resolution limit.
    body=normalized_video_parameters({**data,'model':MINI,'resolution':'720p'})
    if len(body['prompt'])>4000:
        raise VideoError('INVALID_VIDEO_INPUT','Seedance 2.0 / Fast 提示词最多 4000 个字符。')
    return {**body,'model':model,'resolution':resolution}


def estimate(body,refs):
    ref_ms=validate_video_references(refs,body)
    fast=body.get('model')==FAST_MODEL
    rate=(FAST_RATES if fast else RATES)[body['resolution']][1 if ref_ms else 0]
    usd=(Decimal(body['duration'])+Decimal(ref_ms)/1000)*rate
    return {'estimated':cost_credits(usd),'reserved':cost_credits(usd*Decimal('1.6')),
            'estimated_usd':usd,'reference_ms':ref_ms,'profile':FAST_PROFILE if fast else PROFILE}
