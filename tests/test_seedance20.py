import unittest
from decimal import Decimal
from unittest.mock import patch
from backend import seedance20 as s
from backend import video_provider as p
from backend.prompt_history import video_history_parameters


class Seedance20Tests(unittest.TestCase):
    def test_standard_controls_are_distinct_from_mini_and_25(self):
        for resolution in ['480p','720p','1080p','4k']:
            result=p.normalized_video_parameters({'model':s.MODEL,'resolution':resolution,'duration':4,'seed':0,'prompt':'x'*4000,'generate_audio':False,'return_last_frame':True,'tools':[{'type':'web_search'}]})
            self.assertEqual(result['resolution'],resolution);self.assertEqual(result['model'],s.MODEL)
            self.assertEqual(result['seed'],0);self.assertFalse(result['generate_audio'])
            self.assertEqual(video_history_parameters(result),result)
        for bad in [{'prompt':'x'*4001},{'duration':3},{'duration':16},{'duration':-1},{'draft':True},{'draft_request_id':'fixture'},{'output_format':'mov'},{'omni_reference_task_type':'edit'},{'watermark':True},{'resolution':'2k'},{'generate_audio':'false'}]:
            with self.subTest(bad=bad),self.assertRaises(p.VideoError):p.normalized_video_parameters({'model':s.MODEL,'prompt':'fixture',**bad})

    def test_gold_estimate_and_actual_billing_use_exact_twenty_percent_and_half_credit_ceiling(self):
        expected={'480p':('7.5','12'),'720p':('16','25.5'),'1080p':('39.5','63'),'4k':('80','128')}
        for resolution,(estimate,reserve) in expected.items():
            result=s.estimate(p.normalized_video_parameters({'model':s.MODEL,'prompt':'fixture','resolution':resolution,'duration':5}),[])
            self.assertEqual(result['estimated'],Decimal(estimate));self.assertEqual(result['reserved'],Decimal(reserve))
        for usd,credits in [('0','0'),('0.33','7.5'),('0.71','16'),('1','22.5')]:self.assertEqual(s.cost_credits(Decimal(usd)),Decimal(credits))
        self.assertEqual(s.PROFILE['markup'],'1.2')
        from backend import seedance25
        self.assertEqual(seedance25.PROFILE['markup'],'1.2')
        self.assertEqual(p.PRICES,{'480p':Decimal('.5'),'720p':Decimal('1')})

    def test_reference_video_discount_and_only_video_duration_are_used(self):
        body=p.normalized_video_parameters({'model':s.MODEL,'prompt':'fixture','duration':5,'resolution':'480p'})
        image={'kind':'image','id':'image','width':512,'height':512}
        audio={'kind':'audio','id':'audio','duration_ms':3000}
        video={'kind':'video','id':'video','duration_ms':3000,'width':854,'height':480}
        no_video=s.estimate(body,[image,audio]);self.assertEqual(no_video['estimated_usd'],Decimal('.33'))
        with_video=s.estimate(body,[video,audio]);self.assertEqual(with_video['estimated_usd'],Decimal('.32'))
        payload=p.video_payload(body,[image,video,audio],['https://fixture.invalid/image.png','https://fixture.invalid/video.mp4','https://fixture.invalid/audio.wav'])
        self.assertEqual(payload['model'],s.MODEL);self.assertIn('video_urls',payload);self.assertNotIn('draft',payload)
        for refs in [[audio],[{**image,'width':200}],[{**video,'duration_ms':1000}],[{**image,'role':'first_frame'},video],[{**image,'role':'reference_image'}]]:
            with self.subTest(refs=refs),self.assertRaises(p.VideoError):s.estimate(body,refs)

    def test_cost_is_never_guessed_from_time_or_inconsistent_credits(self):
        self.assertIsNone(s.actual_cost({'actual_time':20,'credits_cost':2}))
        self.assertIsNone(s.actual_cost({'cost':'.33','credits_cost':20}))
        self.assertEqual(s.actual_cost({'cost':'.33','credits_cost':3.3}),Decimal('.33'))

    def test_standard_submit_uses_the_same_documented_endpoint_once(self):
        with patch.object(p,'video_request',return_value={'data':[{'task_id':'task_standard_fixture'}]}) as post:
            result=p.submit_video('offline',s.normalized_parameters({'model':s.MODEL,'prompt':'fixture','resolution':'4k'}))
        self.assertEqual(result,'task_standard_fixture');post.assert_called_once();self.assertEqual(post.call_args.args[1],'/videos/generations')
