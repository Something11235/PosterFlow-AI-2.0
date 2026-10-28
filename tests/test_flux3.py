import io
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from backend import flux3 as f, video_provider as v
from backend.video_references import reference_metadata
from backend.video_routes import VideoStore

def image(id='a.png',**kw):return {'id':id,'kind':'image','size':1024,'width':128,'height':128,**kw}
def video(**kw):return {'id':'v.mp4','kind':'video','size':1024,'width':854,'height':480,'duration_ms':3000,**kw}
def source(**kw):return {'model':f.MODEL,'is_draft':True,'status':'completed','billing_status':'settled','provider_task_id':'task_draft_fixture','requested_duration':5,'pricing_profile':{'continuation':False},**kw}
class FluxTests(unittest.TestCase):
    def body(self,**kw):return v.normalized_video_parameters({'model':f.MODEL,'prompt':'镜头推进',**kw})
    def test_exact_six_rates_and_audio_no_discount(self):
        for draft,continuation,res,price,reserve in [(True,False,'hd','5.5','8.5'),(True,True,'hd','11','17'),(False,False,'hd','15.5','24.5'),(False,False,'fhd','26','41.5'),(False,True,'hd','36.5','58.5'),(False,True,'fhd','47','75')]:
            refs=[video()] if continuation else [];body=self.body(draft=draft,resolution=res)
            q=f.estimate(body,refs);self.assertEqual(q['estimated'],Decimal(price));self.assertEqual(q['reserved'],Decimal(reserve))
            self.assertEqual(v.video_price(body,refs),q['reserved']);self.assertEqual(f.estimate({**body,'audio':False},refs)['estimated_usd'],q['estimated_usd'])
    def test_contract_rejects_unsupported_or_wrong_types(self):
        for kw in [{'duration':'auto'},{'duration':4},{'duration':21},{'duration':5.5},{'duration':True},{'resolution':'720p'},{'aspect_ratio':'adaptive'},{'safety_tolerance':5},{'safety_tolerance':False},{'draft':True,'resolution':'fhd'},{'audio':'false'},{'seed':2},{'mode':'i2v'}]:
            with self.subTest(kw=kw),self.assertRaises(v.VideoError):self.body(**kw)
        for ratio in f.RATIOS:self.body(aspect_ratio=ratio,duration=20)
    def test_order_and_repeated_keyframes_are_preserved(self):
        refs=[image('z.png'),image('a.png'),image('z.png')];urls=['https://fixture.invalid/z.png','https://fixture.invalid/a.png','https://fixture.invalid/z.png']
        payload=v.video_payload(self.body(),refs,urls);self.assertEqual(payload['image_urls'],urls)
        self.assertNotEqual(v.video_fingerprint(self.body(),refs),v.video_fingerprint(self.body(),refs[1:]+refs[:1]))
        self.assertNotIn('image_with_roles',payload);self.assertNotIn('mode',payload)
    def test_video_payload_and_no_source_duration_added(self):
        body=self.body();p=v.video_payload(body,[video()],['https://fixture.invalid/v.mp4']);self.assertIn('video_url',p);self.assertNotIn('video_urls',p)
        self.assertEqual(f.estimate(body,[video(duration_ms=30000)])['estimated'],Decimal('36.5'))
    def test_media_and_prompt_constraints_before_reserve(self):
        for refs in [[video(),image()],[{'id':'a.wav','kind':'audio'}],[image(role='first_frame')],[image(asset_url='asset://owned')],[image()]*11,[video(id='v.mov')],[video(duration_ms=30001)],[image(width=0)],[image(size=16*1024*1024+1)]]:
            with self.subTest(refs=refs),self.assertRaises(v.VideoError):f.estimate(self.body(),refs)
        with self.assertRaises(v.VideoError):f.estimate(self.body(prompt=''),[image()])
    def test_final_payload_only_contains_model_resolution_and_server_source(self):
        body=self.body_final();s=source(pricing_profile={'continuation':True})
        self.assertEqual(f.payload(body,[],[],s),{'model':f.MODEL,'resolution':'fhd','draft_from_task_id':'task_draft_fixture'})
        self.assertEqual(f.estimate(body,[],s)['estimated'],Decimal('47'))
        with self.assertRaises(v.VideoError):f.payload(body,[image()],['https://fixture.invalid/a.png'],s)
        for extra in [{'prompt':'changed'},{'duration':5},{'audio':False},{'draft':False}]:
            with self.assertRaises(v.VideoError):f.normalized_parameters({**body,**extra})
    def body_final(self):return f.normalized_parameters({'model':f.MODEL,'resolution':'fhd','draft_request_id':'11111111-1111-4111-8111-111111111111'})
    def test_other_unfinished_unsettled_source_rejected(self):
        for s in [None,source(model='seedance-2.5'),source(is_draft=False),source(status='processing'),source(billing_status='awaiting_balance'),source(provider_task_id='malformed')]:
            with self.assertRaises(v.VideoError):f.payload(self.body_final(),[],[],s)
    def test_real_media_is_independently_validated(self):
        b=io.BytesIO();Image.new('RGB',(128,128)).save(b,'PNG')
        self.assertEqual(reference_metadata(b.getvalue(),'png',f.MODEL)['width'],128)
        self.assertEqual(reference_metadata(Path('tests/fixtures/seedance-reference.mp4').read_bytes(),'mp4',f.MODEL)['fps'],12)
        for ext in ['wav','mov','pdf']:
            with self.assertRaises(v.VideoError):reference_metadata(b'fixture',ext,f.MODEL)
    def test_cost_rpc_uses_decimal_string_and_not_generic_billing(self):
        with patch.object(VideoStore,'__init__',return_value=None),patch.object(VideoStore,'rpc',return_value={'ok':True}) as rpc:VideoStore().apply_flux('owner','rid','completed',cost=Decimal('.68'))
        self.assertEqual(rpc.call_args.args[0],'apply_flux3_job');self.assertEqual(rpc.call_args.args[1]['p_cost_usd'],'0.68')
    def test_final_history_keeps_owner_request_id_but_no_provider_id(self):
        from backend.prompt_history import video_history_parameters
        body=self.body_final();self.assertEqual(video_history_parameters(body),body)

class FluxRouteTests(unittest.TestCase):
    def setUp(self):
        from tests.test_video_routes import VideoRouteTests
        self.fixture=VideoRouteTests();self.fixture.setUp();self.addCleanup(self.fixture.tearDown)
        self.fx=self.fixture;self.fx.input['parameters']={'model':f.MODEL,'prompt':'fixture','resolution':'hd','duration':5}
        self.fx.store.apply_flux=lambda owner,rid,event,**kwargs:self.fx.store.apply(owner,rid,event,**kwargs)
        self.fx.refs.revalidate.side_effect=lambda value,model:value
    def test_submit_once_on_repeated_same_intent(self):
        from backend import video_routes as r
        with patch.object(r,'submit_video',return_value='task_flux_fixture') as post:
            self.assertEqual(self.fx.client.post('/api/video/generations',json=self.fx.input).status_code,202)
            repeat=self.fx.client.post('/api/video/generations',json=self.fx.input)
            self.assertTrue(repeat.json['idempotent']);post.assert_called_once()
            self.assertEqual(post.call_args.args[1]['model'],f.MODEL)
    def test_other_owner_draft_and_changed_prompt_never_reserve_or_post(self):
        from backend import video_routes as r
        self.fx.input['parameters']={'model':f.MODEL,'resolution':'fhd','draft_request_id':'33333333-3333-4333-8333-333333333333'}
        self.fx.store.rows[('other-owner','33333333-3333-4333-8333-333333333333')]=source()
        with patch.object(r,'submit_video') as post:
            self.assertEqual(self.fx.client.post('/api/video/generations',json=self.fx.input).json['code'],'VIDEO_DRAFT_INVALID')
            self.fx.input['parameters']['prompt']='changed'
            self.assertEqual(self.fx.client.post('/api/video/generations',json=self.fx.input).json['code'],'VIDEO_DRAFT_INVALID')
            post.assert_not_called();self.assertEqual(self.fx.store.begin_calls,[])
    def test_owned_draft_uses_only_server_provider_id(self):
        from backend import video_routes as r
        from tests.test_video_routes import UID
        rid='33333333-3333-4333-8333-333333333333';self.fx.store.rows[('user-'+UID,rid)]=source(request_id=rid)
        self.fx.input['parameters']={'model':f.MODEL,'resolution':'fhd','draft_request_id':rid}
        with patch.object(r,'submit_video',return_value='task_flux_final') as post:
            response=self.fx.client.post('/api/video/generations',json=self.fx.input)
            self.assertEqual(response.status_code,202,response.json)
            self.assertEqual(post.call_args.args[1],{'model':f.MODEL,'resolution':'fhd','draft_from_task_id':'task_draft_fixture'})
