import io
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from backend import minimax_h3 as h, video_provider as v
from backend.video_routes import VideoStore
from backend.video_references import reference_metadata
from backend.prompt_history import video_history_parameters


def image(n,**extra):return {'id':str(n),'kind':'image','size':1024,'width':256,'height':384,**extra}
def video(**extra):return {'id':'v','kind':'video','size':1024,'width':854,'height':480,'duration_ms':3000,'fps':24,'codec':'avc1','audio_codecs':[],**extra}


class MinimaxH3MaxTests(unittest.TestCase):
    def body(self,**extra):return v.normalized_video_parameters({'model':h.MAX_MODEL,'prompt':'fixture',**extra})

    def test_max_contract_rejects_four_seconds_2k_and_undocumented_parameters(self):
        self.assertEqual(self.body()['resolution'],'768p')
        self.assertEqual(video_history_parameters(self.body()),self.body())
        for extra in [{'model':[]},{'model':{}},{'duration':4},{'duration':16},{'duration':5.5},{'duration':'5'},{'resolution':'2k'},{'resolution':'720p'},
                      {'nsfw_check':False},{'generate_audio':False},{'seed':0},{'middle_frames':[]},{'watermark':1}]:
            with self.subTest(extra=extra),self.assertRaises(v.VideoError):self.body(**extra)
        # H3 remains separate: 4s and 2K still supported, with a different profile.
        original=v.normalized_video_parameters({'model':h.MODEL,'prompt':'fixture','duration':4,'resolution':'2k'})
        self.assertEqual(original['duration'],4);self.assertEqual(h.estimate(original,[])['profile'],h.PROFILE)

    def test_1080p_never_sends_watermark_even_false_and_history_roundtrips(self):
        for value in [True,False,None]:
            with self.assertRaises(v.VideoError):self.body(resolution='1080p',watermark=value)
        body=self.body(resolution='1080p');result=v.video_payload(body,[],[])
        self.assertNotIn('watermark',body);self.assertNotIn('watermark',result);self.assertNotIn('nsfw_check',result)
        self.assertEqual(result['resolution'],'1080P');self.assertEqual(video_history_parameters(body),body)
        self.assertTrue(v.video_payload(self.body(resolution='480p',watermark=True),[],[])['watermark'])

    def test_separate_reference_rates_first_two_images_free_and_half_credit_rounding(self):
        for res,cost,estimate,reserve in [('480p','.1884','4.5','7'),('768p','.2856','6.5','10.5'),('1080p','.64','14.5','23')]:
            with self.subTest(res=res):
                q=h.estimate(self.body(resolution=res),[])
                self.assertEqual(q['estimated_usd'],Decimal(cost));self.assertEqual(q['estimated'],Decimal(estimate));self.assertEqual(q['reserved'],Decimal(reserve))
                self.assertEqual(v.video_price(self.body(resolution=res),[]),Decimal(reserve))
        refs=[image(i) for i in range(3)]+[video()]
        q=h.estimate(self.body(),refs)
        self.assertEqual(q['estimated_usd'],Decimal('.67536'));self.assertEqual(q['estimated'],Decimal('15'));self.assertEqual(q['reserved'],Decimal('24'))
        with_audio=h.estimate(self.body(),refs+[{'id':'a','kind':'audio','size':1024,'duration_ms':15000}])
        self.assertEqual(with_audio['estimated_usd'],q['estimated_usd'])
        self.assertEqual(h.estimate(self.body(),[image(1),image(2)])['estimated_usd'],Decimal('.2856'))
        self.assertEqual(q['profile']['version'],'minimax-h3-max-usd7-cny038-markup20-half-v1')

    def test_explicit_frames_ordinary_refs_and_real_media_constraints(self):
        urls=['https://fixture.invalid/a.png','https://fixture.invalid/b.png']
        result=v.video_payload(self.body(resolution='1080p'),[image(1,role='first_frame'),image(2,role='last_frame')],urls)
        self.assertEqual(result['aspect_ratio'],'adaptive');self.assertEqual(result['first_frame_image'],urls[0]);self.assertNotIn('watermark',result)
        ordinary=v.video_payload(self.body(),[image(1),image(2)],urls)
        self.assertEqual(ordinary['image_urls'],urls);self.assertNotIn('first_frame_image',ordinary)
        for refs in [[image(1,role='first_frame'),video()],[video(fps=12)],[image(1,width=255)],
                     [image(1,role='middle_frame')],[image(1,role=['first_frame'])],[{'id':'a','kind':'audio','size':1024,'duration_ms':3000}],
                     [image(1),{'id':'a','kind':'audio','size':1024,'duration_ms':1999}],
                     [video(duration_ms=8000),video(id='b',duration_ms=8000)]]:
            with self.subTest(refs=refs),self.assertRaises(v.VideoError):h.estimate(self.body(),refs)
        info=reference_metadata(Path('tests/fixtures/minimax-h3-reference.mp4').read_bytes(),'mp4',h.MAX_MODEL)
        self.assertEqual(info['fps'],24)
        import pillow_heif
        pillow_heif.register_heif_opener();buf=io.BytesIO();Image.new('RGB',(256,384)).save(buf,'HEIF')
        self.assertEqual(reference_metadata(buf.getvalue(),'heic',h.MAX_MODEL)['width'],256)

    def test_max_settlement_uses_independent_rpc_and_exact_actual_cost(self):
        with patch.object(VideoStore,'__init__',return_value=None),patch.object(VideoStore,'rpc',return_value={'ok':True}) as rpc:
            VideoStore().apply_h3_max('owner','request','completed',cost=Decimal('.67536'))
        self.assertEqual(rpc.call_args.args[0],'apply_minimax_h3_max_job');self.assertEqual(rpc.call_args.args[1]['p_cost_usd'],'0.67536')
