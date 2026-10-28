import io
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from backend import omni_flash as o, video_provider as v, video_routes as routes
from backend.video_references import reference_metadata
from backend.prompt_history import video_history_parameters


class OmniFlashTests(unittest.TestCase):
    def body(self,**extra):return v.normalized_video_parameters({'model':o.MODEL,'prompt':'fixture',**extra})

    def test_independent_whitelist_and_history(self):
        for res in o.RATES:
            b=self.body(resolution=res);self.assertEqual(video_history_parameters(b),b)
            self.assertEqual(b['aspect_ratio'],'16:9')
        for extra in [{'duration':5},{'seed':1},{'generate_audio':True},{'tools':[]},{'size':'16:9'},{'nsfw_check':True},{'output_format':'mov'},{'resolution':'480p'},{'aspect_ratio':'1:1'},{'task':'reference'},{'extend_from_task_id':'task_other'},{'continue_request_id':'invalid'}]:
            with self.subTest(extra=extra),self.assertRaises(v.VideoError):self.body(**extra)

    def test_cost_is_actual_not_estimated_or_credits_cost(self):
        for res,estimate,reserve in [('360p','7','10.5'),('720p','19.5','31.5'),('1080p','29.5','47'),('4k','58.5','93.5')]:
            q=o.estimate(self.body(resolution=res),[])
            self.assertEqual(q['estimated'],Decimal(estimate));self.assertEqual(q['reserved'],Decimal(reserve))
        self.assertEqual(o.cost_credits(Decimal('1')),Decimal('22.5'))
        from backend.seedance25 import actual_cost
        self.assertEqual(actual_cost({'cost':'.88','credits_cost':8.8}),Decimal('.88'))
        self.assertIsNone(actual_cost({'cost':'.88','credits_cost':88}))
        self.assertIsNone(actual_cost({'credits_cost':8.8,'actual_time':8}))

    def test_roles_are_not_lost_or_subject_references_overwritten(self):
        img=lambda id,role=None:{'id':id,'kind':'image','width':128,'height':256,**({'role':role} if role else {})}
        refs=[img('first','first_frame'),img('style'),img('last','last_frame')]
        urls=['https://fixture.invalid/'+r['id']+'.png' for r in refs]
        b=o.payload(self.body(task='image_to_video'),refs,urls)
        self.assertEqual(b['image_urls'],[urls[1]]);self.assertEqual(b['first_frame_image'],urls[0]);self.assertEqual(b['last_frame_image'],urls[2])
        self.assertNotIn('metadata',b);self.assertNotIn('image_with_roles',b);self.assertNotIn('duration',b)
        self.assertEqual(o.payload(self.body(task='reference_to_video'),[refs[1]],[urls[1]])['metadata'],{'task':'reference_to_video'})
        for refs in [[img('last','last_frame')],[img('a','first_frame'),img('b','first_frame')],[{'id':'a','kind':'audio','duration_ms':3000}],[{**img('i'),'asset_url':'asset://approved'}],[{'id':'v','kind':'video','duration_ms':10001}],[img(str(i)) for i in range(11)]]:
            with self.subTest(refs=refs),self.assertRaises(v.VideoError):o.estimate(self.body(),refs)

    def test_video_edit_continuation_and_task_intent(self):
        ref={'id':'v','kind':'video','duration_ms':10000}
        b=o.payload(self.body(task='edit'),[ref],['https://fixture.invalid/clip.mp4'])
        self.assertEqual(b['video_urls'],['https://fixture.invalid/clip.mp4']);self.assertEqual(b['metadata'],{'task':'edit'})
        rid='11111111-1111-4111-8111-111111111111'
        source={'model':o.MODEL,'status':'completed','billing_status':'settled','provider_task_id':'task_omni_fixture'}
        b=o.payload(self.body(task='extend',continue_request_id=rid),[],[],source)
        self.assertEqual(b['extend_from_task_id'],'task_omni_fixture');self.assertNotIn('continue_request_id',b)
        for source in [None,{**source,'status':'processing'},{**source,'billing_status':'awaiting_balance'},{**source,'model':'seedance-2.5'}]:
            with self.assertRaises(v.VideoError):o.payload(self.body(continue_request_id=rid),[],[],source)
        with self.assertRaises(v.VideoError):o.estimate(self.body(continue_request_id=rid),[ref])
        for task in ['image_to_video','reference_to_video','edit','extend']:
            with self.assertRaises(v.VideoError):o.estimate(self.body(task=task),[])

    def test_real_bytes_use_omni_limits_and_existing_seedance_limits_remain(self):
        buf=io.BytesIO();Image.new('RGB',(128,256)).save(buf,format='PNG')
        self.assertEqual(reference_metadata(buf.getvalue(),'png',o.MODEL)['width'],128)
        with self.assertRaises(v.VideoError):reference_metadata(buf.getvalue(),'png')
        video=Path('tests/fixtures/seedance-reference.mp4').read_bytes()
        self.assertEqual(reference_metadata(video,'mp4',o.MODEL)['kind'],'video')
        with self.assertRaises(v.VideoError):reference_metadata(b'not audio','wav',o.MODEL)

    def test_store_rpc_and_cost_field_do_not_touch_legacy_rpc(self):
        with patch.object(routes,'SupabaseGateway'), patch.object(routes.VideoStore,'rpc',return_value={'ok':True}) as rpc:
            routes.VideoStore().apply_omni('owner','request','completed',cost=Decimal('.88'))
        self.assertEqual(rpc.call_args.args[0],'apply_omni_flash_job');self.assertEqual(rpc.call_args.args[1]['p_cost_usd'],'0.88')
