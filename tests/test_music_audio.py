"""Offline media/protocol/owner and money-boundary tests. Never calls a provider."""
import io
import json
import time
import unittest
import wave
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from flask import Flask

from backend import music_operations as ops, music_routes as routes
from backend.music_provider import MusicError
from backend.music_references import MusicReferences, audio_metadata, MAX_BYTES

USER = "22222222-2222-4222-8222-222222222222"
REQ = "11111111-1111-4111-8111-111111111111"
TASK = "task_audio_fixture_12345678"


def wav(seconds=2):
    data = io.BytesIO()
    with wave.open(data, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(8000)
        f.writeframes(b"\0\0" * int(seconds * 8000))
    return data.getvalue()


def response(data=None, content=b""):
    r = Mock(headers={"Content-Length": str(len(content))})
    r.__enter__ = Mock(return_value=r); r.__exit__ = Mock(return_value=False)
    r.json.return_value = data
    r.iter_content.return_value = [content]
    return r


class ReferenceTests(unittest.TestCase):
    def setUp(self):
        self.server = SimpleNamespace(SUPABASE_STORAGE_ENABLED=True, SUPABASE_STORAGE_SERVICE_KEY="offline-test-secret",
            SUPABASE_STORAGE_URL="https://fixture.supabase.co", _supabase_storage_url=lambda p: "https://fixture.supabase.co/storage/v1"+p,
            _supabase_object_path=lambda p: "private-bucket/"+p, _supabase_storage_request=Mock())
        self.refs = MusicReferences(self.server)
        self.owner = "user-"+USER

    def issue(self, content):
        self.server._supabase_storage_request.return_value = response({"url": "/object/upload/sign/private-bucket/fixture?token=offline"})
        return self.refs.issue(self.owner, "recording.wav", len(content), "audio/wav")

    def test_real_wav_duration_and_truncation_are_checked_from_bytes(self):
        self.assertEqual(audio_metadata(wav(), "wav")["duration"], 2)
        for data in (b"not audio", wav()[:-10], b"RIFF"+b"\0"*50):
            with self.subTest(data=data[:8]), self.assertRaises(MusicError): audio_metadata(data, "wav")
        for seconds in (.5, 481):
            with self.assertRaises(MusicError): audio_metadata(wav(seconds), "wav")
        with self.assertRaises(MusicError): audio_metadata(b"x"*(MAX_BYTES+1), "mp3")

    def test_real_mp3_is_verified_with_the_decoder_instead_of_its_filename(self):
        fixture = Path(__file__).resolve().parents[1] / "artifacts/suno-tools-20261024/fixtures/tone.mp3"
        info = audio_metadata(fixture.read_bytes(), "mp3")
        self.assertAlmostEqual(info["duration"], 2, delta=.15)
        for content in (wav(), b"ID3not-a-valid-mp3", b"\xff"):
            with self.subTest(content=content[:8]), self.assertRaises(MusicError): audio_metadata(content,"mp3")

    def test_complete_owner_proof_and_public_url_are_bound_to_verified_bytes(self):
        content = wav(); issued = self.issue(content)
        self.assertTrue(issued["signed_url"].startswith("https://fixture.supabase.co/"))
        with self.assertRaises(MusicError): self.refs.verify(issued["upload_ticket"], "other", "upload")
        with self.assertRaises(MusicError): self.refs.verify(issued["upload_ticket"], self.owner)
        self.server._supabase_storage_request.return_value = response(content=content)
        verified = self.refs.complete(self.owner, issued["upload_ticket"])
        value = self.refs.verify(verified["receipt"], self.owner)
        self.assertEqual(value["duration"], 2)
        self.assertEqual(value["expires"]-value["issued"], 43200)
        self.assertEqual(len(value["sha256"]), 64)
        with self.assertRaises(MusicError): self.refs.verify(verified["receipt"][:-1]+"x", self.owner)
        self.server._supabase_storage_request.return_value = response({"signedURL": "/object/sign/private-bucket/fixture?token=offline"})
        self.refs.urls([value])
        call = self.server._supabase_storage_request.call_args
        self.assertEqual(call.kwargs["json"], {"expiresIn": 3600})
        self.assertFalse(call.kwargs["allow_redirects"])
        self.assertIn("audio-references/", call.args[1])

    def test_oversize_type_and_cloud_size_mismatch_never_become_verified(self):
        for name, size, mime in (("a.exe", 10, "audio/wav"), ("a.wav", 0, "audio/wav"), ("a.wav", True, "audio/wav"), ("a.wav", MAX_BYTES+1, "audio/wav")):
            with self.subTest(name=name, size=size), self.assertRaises(MusicError): self.refs.issue(self.owner, name, size, mime)
        self.server._supabase_storage_request.assert_not_called()
        ticket = self.issue(wav())
        self.server._supabase_storage_request.return_value = response(content=wav()+b"overflow")
        with self.assertRaises(MusicError): self.refs.complete(self.owner, ticket["upload_ticket"])

    def test_signed_urls_cannot_escape_the_configured_private_storage(self):
        for url in ("https://evil.invalid/object/a", "https://fixture.supabase.co.evil.invalid/storage/v1/object/a", "https://user:secret@fixture.supabase.co/storage/v1/object/a", "https://fixture.supabase.co/storage/v1/object/a#secret", "https://fixture.supabase.co/other/a"):
            with self.subTest(url=url), self.assertRaises(MusicError): self.refs._safe_url(url)

    def test_expired_proof_can_only_be_used_to_find_an_existing_intent(self):
        issued = self.issue(wav())
        self.server._supabase_storage_request.return_value = response(content=wav())
        reference = self.refs.complete(self.owner, issued["upload_ticket"])
        with patch("backend.music_references.time.time", return_value=time.time()+43200):
            with self.assertRaises(MusicError): self.refs.verify(reference["receipt"], self.owner)
            self.refs.verify(reference["receipt"], self.owner, allow_expired=True)


class AudioProtocolTests(unittest.TestCase):
    def test_inspo_maps_the_documented_fields_and_zero_weights(self):
        body = ops.operation_request("inspo", {"model":"suno", "prompt":"歌词", "style":"jazz", "weirdness_constraint":0, "audio_weight":0}, 4)
        self.assertEqual(body["tags"], "jazz"); self.assertEqual(body["weirdness"], 0)
        self.assertEqual(body["audio_weight"], 0)
        for field in ("custom", "instrumental", "gpt_description", "duration_s", "style", "weirdness_constraint"):
            self.assertNotIn(field, body)
        for extra in ({"custom": True}, {"duration":120}, {"audio_urls":["https://arbitrary.invalid"]}, {"max_mode":True}, {"audio_weight":True}):
            with self.subTest(extra=extra), self.assertRaises(MusicError): ops.operation_request("inspo", extra, 1)

    def test_cover_modes_and_audio_count_validation(self):
        simple = ops.operation_request("upload_cover", {"prompt":"轻快爵士", "instrumental":True}, 1)
        self.assertEqual(simple["gpt_description"], "轻快爵士")
        self.assertNotIn("prompt", simple)
        custom = ops.operation_request("upload_cover", {"custom":True,"prompt":"歌词", "style":"rock", "duration":120}, 1)
        self.assertEqual(custom["duration_s"], 120); self.assertEqual(custom["tags"], "rock")
        with self.assertRaises(MusicError): ops.operation_request("upload_cover", {"custom":True,"instrumental":False},1)
        self.assertNotIn("prompt", ops.operation_request("upload_cover", {"custom":True,"instrumental":True},1))
        for operation, data, count in (("inspo",{},0),("inspo",{},5),("upload_cover",{"prompt":"a"},2),("extend",{},1),("upload_cover",{},1),("upload_cover",{"prompt":"a","style":"rock"},1)):
            with self.subTest(operation=operation, count=count), self.assertRaises(MusicError): ops.operation_request(operation,data,count)

    def test_paid_post_is_single_fixed_endpoint_without_extra_import_task(self):
        with patch.object(ops,"apimart_request",return_value={"code":200,"data":[{"task_id":TASK}]}) as paid:
            self.assertEqual(ops.submit_operation("test-key","inspo",{"model":"suno"},["https://fixture.invalid/a"]), TASK)
        paid.assert_called_once()
        self.assertEqual(paid.call_args.args[1], "/generations/inspo")
        self.assertEqual(paid.call_args.args[3]["audio_urls"], ["https://fixture.invalid/a"])
        with patch.object(ops,"apimart_request") as paid, self.assertRaises(MusicError):
            ops.submit_operation("test-key","upload_cover",{},["https://fixture.invalid/a"],endpoint="https://other.invalid/v1/music/generations")
        paid.assert_not_called()


class AudioRouteTests(unittest.TestCase):
    def setUp(self):
        self.refs = Mock(available=True)
        self.value = {"id":"fixture-audio", "sha256":"a"*64, "expires":int(time.time())+3600}
        self.refs.verify.return_value = self.value
        self.refs.urls.return_value = ["https://fixture.invalid/a?token=private-source"]
        user = SimpleNamespace(id=USER)
        app = Flask(__name__)
        app.register_blueprint(routes.create_music_blueprint(lambda:user, lambda:user, lambda *a:None, [], self.refs))
        self.client = app.test_client()
        self.headers = {"X-Billing-Mode":"own_key", "X-Music-Api-Key":"private-key", "X-Music-Endpoint":"https://api.apimart.ai/v1/music/generations"}
        self.gateway = Mock(); self.gateway.rpc.return_value = {"email_verified":True,"profile":{"status":"active"}}
        self.store = Mock(); self.store.gateway._request.return_value = []
        self.job = {"request_id":REQ,"operation":"inspo","reference_count":1,"status":"submitted","provider_task_id":TASK}
        self.store.rpc.return_value = {"ok":True,"existing":False,"job":self.job}
        self.store.apply.return_value = {"ok":True,"job":self.job}
        self.stack = __import__("contextlib").ExitStack(); self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(routes,"SupabaseGateway",return_value=self.gateway))
        self.stack.enter_context(patch.object(routes,"MusicStore",return_value=self.store))
        self.paid = self.stack.enter_context(patch.object(routes,"submit_operation",return_value=TASK))

    def post(self, **extra):
        return self.client.post("/api/music/operations/inspo",headers=self.headers,json={"request_id":REQ,"parameters":{"model":"suno","style":"jazz"},"references":["verified-receipt"],**extra})

    def test_only_normalized_text_and_count_enter_atomic_reservation(self):
        r=self.post(); self.assertEqual(r.status_code,202)
        self.paid.assert_called_once()
        body=self.store.rpc.call_args.args[1]
        self.assertEqual(body["p_reference_count"],1)
        self.assertEqual(body["p_parameters"]["operation"],"inspo")
        for secret in ("private-key", "verified-receipt", "private-source", "audio_url"):
            self.assertNotIn(secret,json.dumps(body)); self.assertNotIn(secret,r.get_data(as_text=True))
        self.assertEqual(r.headers["Cache-Control"],"private, no-store")

    def test_expired_duplicate_intent_returns_existing_without_sign_or_paid_post(self):
        fingerprint=ops.operation_fingerprint("inspo",ops.operation_request("inspo",{"model":"suno","style":"jazz"},1),[self.value])
        self.value["expires"]=0
        self.store.gateway._request.return_value=[{**self.job,"request_fingerprint":fingerprint}]
        r=self.post(); self.assertEqual(r.status_code,200); self.assertTrue(r.json["idempotent"])
        self.paid.assert_not_called(); self.refs.urls.assert_not_called(); self.store.rpc.assert_not_called()

    def test_source_failure_or_expiry_happens_before_money_and_paid_post(self):
        self.refs.urls.side_effect=MusicError("MUSIC_REFERENCE_STORAGE","temporary",503)
        self.assertEqual(self.post().status_code,503)
        self.paid.assert_not_called(); self.store.rpc.assert_not_called()
        self.value["expires"]=0
        self.assertEqual(self.post().status_code,400)
        self.store.rpc.assert_not_called()

    def test_unknown_submission_never_refunds_or_reposts(self):
        self.paid.side_effect=MusicError("MUSIC_SUBMISSION_UNKNOWN","unknown",503,True)
        self.assertEqual(self.post().status_code,503)
        self.paid.assert_called_once()
        self.assertEqual(self.store.apply.call_args.args[2],"submission_unknown")

    def test_atomic_duplicate_or_save_failure_never_issues_second_post(self):
        self.store.rpc.return_value["existing"]=True
        self.assertEqual(self.post().status_code,200); self.paid.assert_not_called()
        self.store.rpc.return_value["existing"]=False
        self.store.apply.side_effect=RuntimeError("save failure")
        self.assertEqual(self.post().status_code,503); self.paid.assert_called_once()
        self.assertEqual(self.store.apply.call_count,1)
        self.assertEqual(self.store.apply.call_args.args[2],"submitted")

    def test_unverified_frozen_cross_origin_or_arbitrary_url_never_reserve(self):
        self.gateway.rpc.return_value["email_verified"]=False
        self.assertEqual(self.post().status_code,403)
        self.gateway.rpc.return_value={"email_verified":True,"profile":{"status":"frozen"}}
        self.assertEqual(self.post().status_code,403)
        self.headers["Origin"]="https://evil.invalid"
        self.assertEqual(self.post().status_code,403)
        self.headers.pop("Origin"); self.headers["X-Music-Endpoint"]="https://evil.invalid/v1/music/generations"
        self.assertEqual(self.post().status_code,400)
        self.paid.assert_not_called(); self.store.rpc.assert_not_called()

    def test_upload_urls_require_login_even_when_using_own_key(self):
        app=Flask("guest"); app.register_blueprint(routes.create_music_blueprint(lambda:None,lambda:None,lambda *a:None,[],self.refs))
        r=app.test_client().post("/api/music/references/uploads",headers=self.headers,json={"filename":"a.wav","size":100,"content_type":"audio/wav"})
        self.assertEqual(r.status_code,401); self.refs.issue.assert_not_called()


if __name__ == "__main__": unittest.main()
