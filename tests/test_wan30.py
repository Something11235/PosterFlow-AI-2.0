import io
import unittest
import wave
import zipfile
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from pypdf import PdfWriter
from backend import wan30 as w, video_provider as v
from backend.video_references import reference_metadata
from backend.video_routes import VideoStore
from backend.prompt_history import video_history_parameters

def image(n='i',**extra):return {'id':n,'kind':'image','size':1024,'width':240,'height':240,**extra}
def video(n='v',**extra):return {'id':n,'kind':'video','size':1024,'width':854,'height':480,'duration_ms':1000,**extra}
def audio(n='a',**extra):return {'id':n,'kind':'audio','size':1024,'duration_ms':1000,**extra}

class Wan30Tests(unittest.TestCase):
    def body(self,**extra):return v.normalized_video_parameters({'model':w.MODEL,'prompt':'fixture',**extra})
    def test_documented_controls_and_history_hide_page_url(self):
        body=self.body(duration=-1,audio=False,seed=2147483647,link_url='https://fixture.invalid/article')
        self.assertEqual(body['resolution'],'1080p');self.assertFalse(body['audio'])
        history=video_history_parameters(body);self.assertNotIn('link_url',history);self.assertFalse(history['audio'])
        for bad in [{'duration':1},{'duration':31},{'duration':2.5},{'seed':-1},{'seed':True},{'seed':2147483648},{'size':'21:9'},{'resolution':'2k'},
                    {'generate_audio':True},{'return_last_frame':True},{'prompt':'字'*20001},{'audio':'false'},{'link_url':'http://127.0.0.1/x'}]:
            with self.subTest(bad=bad),self.assertRaises(v.VideoError):self.body(**bad)
        self.assertEqual(len(self.body(prompt='字'*20000)['prompt']),20000)
    def test_explicit_image_roles_never_depend_on_count(self):
        urls=['https://fixture.invalid/a.png','https://fixture.invalid/b.png']
        p=v.video_payload(self.body(prompt='@图片1 follows @视频1'),[image(),video()],urls)
        self.assertEqual(p['prompt'],'图1 follows 视频1');self.assertEqual(p['generation_type'],'reference')
        self.assertEqual(p['image_with_roles'][0]['role'],'reference_image')
        self.assertNotIn('image_urls',p);self.assertNotIn('generate_audio',p)
        p=v.video_payload(self.body(),[image(role='first_frame'),image('b',role='last_frame')],urls)
        self.assertEqual(p['generation_type'],'frame')
        for refs in [[image(role='last_frame')],[image(role='first_frame'),video()],[image(role='first_frame'),image('b')]]:
            with self.assertRaises(v.VideoError):w.estimate(self.body(),refs)
        with self.assertRaises(v.VideoError):w.estimate(self.body(link_url=urls[0]),[image(role='first_frame')])
    def test_one_second_audio_alone_and_total_duration_constraints(self):
        w.estimate(self.body(prompt=''),[audio()])
        w.estimate(self.body(duration=15),[video(duration_ms=15000)])
        with self.assertRaises(v.VideoError):w.estimate(self.body(duration=16),[video(duration_ms=15000)])
        for refs in [[audio(duration_ms=999)],[video(duration_ms=15001)],[audio('a',duration_ms=8000),audio('b',duration_ms=8000)],
                     [image(str(n)) for n in range(11)],[video('a',width=4097)],[image(width=239)],[image(has_alpha=True)]]:
            with self.subTest(refs=refs),self.assertRaises(v.VideoError):w.estimate(self.body(),refs)
        with self.assertRaises(v.VideoError):w.estimate(self.body(prompt=''),[])
        with self.assertRaises(v.VideoError):w.estimate(self.body(prompt='@图片2'),[image()])
    def test_exact_cost_estimate_auto_upper_bound_and_free_audio(self):
        for res,price,reserve in [('480p','4','6'),('720p','7.5','12'),('1080p','15','23.5')]:
            q=w.estimate(self.body(resolution=res),[])
            self.assertEqual(q['estimated'],Decimal(price));self.assertEqual(q['reserved'],Decimal(reserve))
        q=w.estimate(self.body(resolution='720p',duration=-1),[video(duration_ms=15000)])
        self.assertEqual(q['estimated_usd'],Decimal('1.9725'));self.assertEqual(q['estimated'],Decimal('44'))
        self.assertEqual(w.estimate(self.body(audio=False),[audio()])['estimated_usd'],w.estimate(self.body(audio=True),[])['estimated_usd'])
    def test_real_image_audio_video_byte_limits_do_not_reuse_other_model_limits(self):
        for fmt,ext in [('PNG','png'),('BMP','bmp')]:
            buf=io.BytesIO();Image.new('RGB',(240,240)).save(buf,fmt)
            self.assertEqual(reference_metadata(buf.getvalue(),ext,w.MODEL)['width'],240)
        buf=io.BytesIO();Image.new('RGBA',(240,240)).save(buf,'PNG')
        with self.assertRaises(v.VideoError):reference_metadata(buf.getvalue(),'png',w.MODEL)
        buf=io.BytesIO()
        with wave.open(buf,'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(8000);f.writeframes(b'\0\0'*8000)
        self.assertEqual(reference_metadata(buf.getvalue(),'wav',w.MODEL)['duration_ms'],1000)
        # Wan does not impose H3's 23.976fps minimum.
        self.assertEqual(reference_metadata(Path('tests/fixtures/seedance-reference.mp4').read_bytes(),'mp4',w.MODEL)['fps'],12)
    def test_documents_page_limit_encryption_and_family_exclusion(self):
        for pages,valid in [(1,True),(50,True),(51,False)]:
            writer=PdfWriter();[writer.add_blank_page(100,100) for _ in range(pages)];buf=io.BytesIO();writer.write(buf)
            if valid:self.assertEqual(reference_metadata(buf.getvalue(),'pdf',w.MODEL)['pages'],pages)
            else:
                with self.assertRaises(v.VideoError):reference_metadata(buf.getvalue(),'pdf',w.MODEL)
        self.assertEqual(reference_metadata('测试文档'.encode(),'md',w.MODEL)['kind'],'document')
        with self.assertRaises(v.VideoError):reference_metadata(b'fake PDF','pdf',w.MODEL)
        with self.assertRaises(v.VideoError):reference_metadata(b'text','txt','MiniMax-H3')
        doc={'id':'d','kind':'document','size':1024,'pages':1}
        p=v.video_payload(self.body(prompt=''),[doc],['https://fixture.invalid/doc.pdf']);self.assertIn('file_url',p)
        with self.assertRaises(v.VideoError):w.estimate(self.body(link_url='https://fixture.invalid/page'),[doc])
    def test_office_file_pages_are_checked_when_available(self):
        buf=io.BytesIO()
        with zipfile.ZipFile(buf,'w') as z:
            z.writestr('word/document.xml','<document/>');z.writestr('docProps/app.xml','<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Pages>51</Pages></Properties>')
        with self.assertRaises(v.VideoError):reference_metadata(buf.getvalue(),'docx',w.MODEL)
    def test_independent_actual_cost_rpc(self):
        with patch.object(VideoStore,'__init__',return_value=None),patch.object(VideoStore,'rpc',return_value={'ok':True}) as rpc:
            VideoStore().apply_wan('owner','request','completed',cost=Decimal('.6575'))
        self.assertEqual(rpc.call_args.args[0],'apply_wan30_job');self.assertEqual(rpc.call_args.args[1]['p_cost_usd'],'0.6575')

    def test_cross_model_old_png_receipt_is_revalidated_from_bytes(self):
        from tests.test_video_references import VideoReferenceTests,response
        setup=VideoReferenceTests();setup.setUp()
        buf=io.BytesIO();Image.new('RGBA',(256,256)).save(buf,'PNG');data=buf.getvalue()
        setup.server._supabase_storage_request.return_value=response({'url':'/object/upload/sign/private-bucket/picture.png?token=fixture'},data=data)
        issued=setup.refs.issue(setup.owner,'picture.png',len(data),model='MiniMax-H3')
        ref=setup.refs.complete(setup.owner,issued['upload_ticket']);value=setup.refs.verify(ref['receipt'],setup.owner)
        value.pop('has_alpha',None)  # A pre-upgrade receipt did not record alpha.
        with self.assertRaises(v.VideoError):setup.refs.revalidate(value,w.MODEL)

    def test_document_upload_receipt_is_owned_and_contains_verified_page_count(self):
        from tests.test_video_references import VideoReferenceTests,response
        setup=VideoReferenceTests();setup.setUp()
        writer=PdfWriter();writer.add_blank_page(100,100);buf=io.BytesIO();writer.write(buf);data=buf.getvalue()
        setup.server._supabase_storage_request.return_value=response({'url':'/object/upload/sign/private-bucket/source.pdf?token=fixture'},data=data)
        issued=setup.refs.issue(setup.owner,'source.pdf',len(data),model=w.MODEL)
        ref=setup.refs.complete(setup.owner,issued['upload_ticket']);self.assertEqual(ref['pages'],1)
        self.assertEqual(setup.refs.verify(ref['receipt'],setup.owner)['kind'],'document')
        with self.assertRaises(v.VideoError):setup.refs.verify(ref['receipt'],'another-owner')
