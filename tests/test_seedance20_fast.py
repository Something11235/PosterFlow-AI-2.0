import unittest
from decimal import Decimal
from unittest.mock import patch
from backend import seedance20 as s, video_provider as p
from backend.prompt_history import video_history_parameters
from backend.video_routes import VideoStore


class SeedanceFastTests(unittest.TestCase):
    def test_documented_fast_controls_and_resolution_limits(self):
        for resolution in ['480p','720p']:
            data=p.normalized_video_parameters({'model':s.FAST_MODEL,'prompt':'x'*4000,'resolution':resolution,'duration':15,'seed':0,'generate_audio':False,'return_last_frame':True,'tools':[{'type':'web_search'}],'nsfw_check':True})
            self.assertEqual(data['model'],s.FAST_MODEL);self.assertEqual(data['resolution'],resolution)
            self.assertEqual(data['seed'],0);self.assertEqual(video_history_parameters(data),data)
        for bad in [{'resolution':'1080p'},{'resolution':'4k'},{'duration':3},{'duration':16},{'duration':-1},{'prompt':'x'*4001},{'draft':True},{'output_format':'mov'},{'omni_reference_task_type':'edit'},{'generate_audio':'false'}]:
            with self.subTest(bad=bad),self.assertRaises(p.VideoError):p.normalized_video_parameters({'model':s.FAST_MODEL,'prompt':'fixture',**bad})

    def test_exact_twenty_percent_rates_and_video_only_reference_discount(self):
        for resolution,price,reserve,usd in [('480p','4.5','7.5','.1992'),('720p','9.5','15.5','.428')]:
            body=s.normalized_parameters({'model':s.FAST_MODEL,'prompt':'fixture','resolution':resolution,'duration':5})
            q=s.estimate(body,[]);self.assertEqual(q['estimated'],Decimal(price));self.assertEqual(q['reserved'],Decimal(reserve));self.assertEqual(q['estimated_usd'],Decimal(usd));self.assertEqual(q['profile'],s.FAST_PROFILE)
        body=s.normalized_parameters({'model':s.FAST_MODEL,'prompt':'fixture','resolution':'480p'})
        video={'kind':'video','id':'v','width':854,'height':480,'duration_ms':3000}
        audio={'kind':'audio','id':'a','duration_ms':3000}
        quote=s.estimate(body,[video,audio]);self.assertEqual(quote['estimated_usd'],Decimal('.18944'));self.assertEqual(quote['estimated'],Decimal('4.5'));self.assertEqual(quote['reserved'],Decimal('7'))
        self.assertEqual(s.PROFILE['markup'],'1.2');self.assertEqual(s.FAST_PROFILE['markup'],'1.2')
        self.assertEqual(s.cost_credits(Decimal('.33')),Decimal('7.5'))

    def test_fast_keeps_reference_role_duration_and_owner_limits(self):
        body=s.normalized_parameters({'model':s.FAST_MODEL,'prompt':'fixture'})
        img={'id':'image','kind':'image','width':512,'height':512}
        vid={'id':'video','kind':'video','width':854,'height':480,'duration_ms':3000}
        for refs in [[{'id':'audio','kind':'audio','duration_ms':3000}],[{**img,'width':299}],[{**vid,'duration_ms':1000}],[{**img,'role':'first_frame'},vid],[img]*10]:
            with self.subTest(refs=refs),self.assertRaises(p.VideoError):s.estimate(body,refs)
        self.assertEqual(p.video_payload(body,[{**img,'role':'first_frame'}],['https://fixture.invalid/frame.png'])['model'],s.FAST_MODEL)

    def test_fast_settlement_uses_its_own_rpc_including_deferred_cost(self):
        with patch.object(VideoStore,'__init__',return_value=None),patch.object(VideoStore,'rpc',return_value={'ok':True}) as rpc:
            VideoStore().apply20('owner','request','completed',cost=Decimal('.1992'),model=s.FAST_MODEL)
        self.assertEqual(rpc.call_args.args[0],'apply_seedance20_fast_job');self.assertEqual(rpc.call_args.args[1]['p_cost_usd'],'0.1992')
