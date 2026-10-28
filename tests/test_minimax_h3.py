import io
import unittest
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from PIL import Image
from backend import minimax_h3 as h, video_provider as v, video_routes as routes
from backend.video_references import VideoReferences, reference_metadata
from backend.prompt_history import video_history_parameters


def image(id='i', **extra):
    return {'id':id,'kind':'image','size':1024,'width':256,'height':256,**extra}


def video(id='v', **extra):
    return {'id':id,'kind':'video','size':1024,'width':854,'height':480,'duration_ms':3000,'fps':24,'codec':'avc1','audio_codecs':['mp4a'],**extra}


class MinimaxH3Tests(unittest.TestCase):
    def body(self, **extra):return v.normalized_video_parameters({'model':h.MODEL,'prompt':'fixture',**extra})

    def test_strict_contract_and_history_without_seedance_parameters(self):
        body=self.body();self.assertEqual(video_history_parameters(body),body)
        self.assertEqual(body['resolution'],'2k')
        for extra in [{'prompt':''},{'prompt':'字'*7001},{'duration':3},{'duration':16},{'duration':5.5},{'duration':True},{'duration':'5'},
                      {'resolution':'720p'},{'seed':1},{'tools':[]},{'generate_audio':True},{'return_last_frame':True},{'watermark':1},{'nsfw_check':'false'}]:
            with self.subTest(extra=extra),self.assertRaises(v.VideoError):self.body(**extra)
        self.assertEqual(len(self.body(prompt='字'*7000)['prompt']),7000)

    def test_frames_and_references_are_explicit_and_exclusive(self):
        urls=['https://fixture.invalid/a.png','https://fixture.invalid/b.png']
        ordinary=v.video_payload(self.body(),[image('a'),image('b')],urls)
        self.assertEqual(ordinary['image_urls'],urls);self.assertNotIn('first_frame_image',ordinary)
        result=v.video_payload(self.body(),[image('a',role='first_frame'),image('b',role='last_frame')],urls)
        self.assertEqual(result['first_frame_image'],urls[0]);self.assertEqual(result['last_frame_image'],urls[1])
        self.assertEqual(result['resolution'],'2K');self.assertEqual(result['aspect_ratio'],'adaptive')
        self.assertNotIn('image_urls',result);self.assertNotIn('size',result)
        self.assertEqual(v.video_payload(self.body(size='adaptive'),[],[])['aspect_ratio'],'16:9')
        for refs in [[image(role='first_frame'),image('b')],[image(role='first_frame'),video()],
                     [image(role='last_frame'),image('b',role='last_frame')],
                     [{'id':'a','kind':'audio','size':100,'duration_ms':2000}],
                     [image(asset_url='asset://owned')],[image('same'),image('same')]]:
            with self.subTest(refs=refs),self.assertRaises(v.VideoError):h.validate_references(refs)
        # Last-only is explicitly allowed by the API's independent optional fields.
        self.assertIn('last_frame_image',v.video_payload(self.body(),[image(role='last_frame')],[urls[0]]))

    def test_media_boundaries_counts_formats_and_duration(self):
        for fps in (23.976,60):h.validate_references([video(fps=fps)])
        h.validate_references([image(width=5760,height=5760)])
        h.validate_references([image(),{'id':'a','kind':'audio','size':15*1024*1024,'duration_ms':15000}])
        bads=[image(width=255),image(height=5761),image(width=256,height=1000),image(size=30*1024*1024+1),
              video(fps=23.975),video(fps=60.001),video(fps=float('nan')),video(codec='vp09'),video(audio_codecs=['opus']),video(audio_codecs=None),
              video(duration_ms=1999),video(duration_ms=15001),video(width=255)]
        for ref in bads:
            with self.subTest(ref=ref),self.assertRaises(v.VideoError):h.validate_references([ref])
        for refs in [[video('a',duration_ms=8000),video('b',duration_ms=8000)],
                     [image(str(i)) for i in range(10)],
                     [image(),{'id':'a','kind':'audio','size':15*1024*1024+1,'duration_ms':2000}],
                     [image(),*[{'id':str(i),'kind':'audio','size':10,'duration_ms':8000} for i in range(2)]]]:
            with self.assertRaises(v.VideoError):h.validate_references(refs)

    def test_estimate_and_actual_cost_formula_use_decimal_half_rounding(self):
        for resolution,estimated,reserved in [('768p','6.5','10.5'),('2k','10.5','16.5')]:
            q=h.estimate(self.body(resolution=resolution),[])
            self.assertEqual(q['estimated'],Decimal(estimated));self.assertEqual(q['reserved'],Decimal(reserved))
            self.assertEqual(v.video_price(self.body(resolution=resolution),[]),Decimal(reserved))
        refs=[*[image(str(i)) for i in range(9)],video()]
        q=h.estimate(self.body(resolution='768p'),refs)
        self.assertEqual(q['estimated_usd'],Decimal('.54848'));self.assertEqual(q['estimated'],Decimal('12.5'))
        from backend.seedance25 import actual_cost
        self.assertEqual(actual_cost({'cost':'.54848','credits_cost':5.4848}),Decimal('.54848'))
        self.assertIsNone(actual_cost({'credits_cost':5.4848}))
        self.assertIsNone(actual_cost({'cost':'.54848','credits_cost':54.848}))

    def test_real_heif_bytes_and_owner_bound_upload(self):
        import pillow_heif
        pillow_heif.register_heif_opener()
        data=io.BytesIO();Image.new('RGB',(256,384)).save(data,format='HEIF')
        content=data.getvalue();info=reference_metadata(content,'heic',h.MODEL)
        self.assertEqual((info['width'],info['height']),(256,384))
        for model in ('seedance-2.0-mini','seedance-2.5','gemini-omni-1.1-flash'):
            with self.assertRaises(v.VideoError):reference_metadata(content,'heic',model)
        response=Mock(status_code=200);response.__enter__=Mock(return_value=response);response.__exit__=Mock(return_value=False)
        response.json.return_value={'url':'/object/upload/sign/private-bucket/portrait.heic?token=fixture'}
        response.iter_content.return_value=[content]
        server=SimpleNamespace(SUPABASE_STORAGE_ENABLED=True,SUPABASE_STORAGE_SERVICE_KEY='offline-secret',SUPABASE_STORAGE_URL='https://fixture.supabase.co',
            _supabase_storage_url=lambda p:'https://fixture.supabase.co/storage/v1'+p,_supabase_object_path=lambda p:'private-bucket/'+p,_supabase_storage_request=Mock(return_value=response))
        refs=VideoReferences(server);issued=refs.issue('owner','portrait.heic',len(content),model=h.MODEL)
        result=refs.complete('owner',issued['upload_ticket'])
        self.assertEqual(refs.verify(result['receipt'],'owner')['model'],h.MODEL)
        with self.assertRaises(v.VideoError):refs.verify(result['receipt'],'other-owner')
        with self.assertRaises(v.VideoError):refs.verify(result['receipt']+'x','owner')
        with patch('backend.video_references.pinned_custom_response',return_value=response):
            result=refs.import_url('owner','https://fixture.invalid/a.heif','a.heif',model=h.MODEL)
        self.assertEqual(result['content_type'],'image/heic')

    def test_actual_video_bytes_and_invalid_heif_fail_before_submission(self):
        data=Path('tests/fixtures/minimax-h3-reference.mp4').read_bytes()
        result=reference_metadata(data,'mp4',h.MODEL)
        self.assertEqual(result['fps'],24);self.assertIn('audio_codecs',result)
        with self.assertRaises(v.VideoError):reference_metadata(b'fake HEIF','heic',h.MODEL)

    def test_new_store_rpc_keeps_old_model_rpcs_untouched(self):
        with patch.object(routes,'SupabaseGateway'),patch.object(routes.VideoStore,'rpc',return_value={'ok':True}) as rpc:
            routes.VideoStore().apply_h3('owner','request','completed',cost=Decimal('.4572'))
        self.assertEqual(rpc.call_args.args[0],'apply_minimax_h3_job')
        self.assertEqual(rpc.call_args.args[1]['p_cost_usd'],'0.4572')
