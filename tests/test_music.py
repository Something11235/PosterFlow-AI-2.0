import os
import unittest
from unittest.mock import Mock, patch

import requests

from backend import music_provider as provider, music_routes as routes, server

REQUEST_ID = "11111111-1111-4111-8111-111111111111"
USER_ID = "22222222-2222-4222-8222-222222222222"
TASK_ID = "task_test_0123456789"


class MusicProtocolTests(unittest.TestCase):
    def test_all_selected_versions_use_verified_fields(self):
        for version in provider.SUNO_VERSIONS:
            with self.subTest(version=version):
                self.assertEqual(provider.build_music_request({"model": "suno", "version": version, "prompt": "钢琴"})["version"], version)
        pro = provider.build_music_request({"model": "flowmusic", "version": "lyria-3-pro", "sound_prompt": "钢琴"})
        self.assertNotIn("version", pro)
        lyria = provider.build_music_request({"model": "flowmusic", "version": "lyria-3.5", "lyrics": "歌词"})
        self.assertEqual(lyria["version"], "lyria-3.5")

    def test_invalid_models_versions_and_privileged_fields_are_rejected(self):
        for parameters in ({"model": "tts"}, {"model": []}, {"model": "suno", "version": "v5", "prompt": "hi"}, {"prompt": "hi", "max_mode": True}, {"prompt": "hi", "endpoint": "https://evil.invalid"}, {"prompt": "hi", "price": 0}):
            with self.subTest(parameters=parameters), self.assertRaises(provider.MusicError):
                provider.build_music_request(parameters)

    def test_custom_fields_are_omitted_in_inspiration_mode(self):
        body = provider.build_music_request({"prompt": "钢琴", "custom": False, "title": "private", "style": "jazz", "auto_lyrics": True})
        self.assertNotIn("title", body)
        self.assertNotIn("style", body)
        self.assertNotIn("auto_lyrics", body)

    def test_unicode_limits_and_zero_weights(self):
        self.assertEqual(len(provider.build_music_request({"prompt": "🎵" * 3000, "style_weight": 0})["prompt"]), 3000)
        self.assertEqual(provider.build_music_request({"prompt": "钢琴", "weirdness_constraint": 0})["weirdness_constraint"], 0)
        with self.assertRaises(provider.MusicError):
            provider.build_music_request({"prompt": "🎵" * 3001})

    def test_invalid_numeric_and_boolean_inputs(self):
        for patch_body in ({"style_weight": True}, {"style_weight": float("nan")}, {"audio_weight": 1.1}, {"custom": "true"}, {"custom": True, "instrumental": True, "duration": 10.5}):
            with self.subTest(body=patch_body), self.assertRaises(provider.MusicError):
                provider.build_music_request({"prompt": "钢琴", **patch_body})

    def test_flow_inputs_and_site_limits(self):
        body = provider.build_music_request({"model": "flowmusic", "lyrics": "歌词", "bpm": "120", "length": 240})
        self.assertEqual(body["bpm"], "120")
        for values in ({"sound_prompt": ""}, {"lyrics": "歌", "length": 241}, {"lyrics": "歌", "length": True}, {"lyrics": "歌", "bpm": "0"}, {"lyrics": "歌", "bpm": 120}):
            with self.subTest(values=values), self.assertRaises(provider.MusicError):
                provider.build_music_request({"model": "flowmusic", **values})

    def test_custom_vocals_need_lyrics_but_instrumental_may_omit_them(self):
        with self.assertRaises(provider.MusicError):
            provider.build_music_request({"custom": True})
        self.assertNotIn("prompt", provider.build_music_request({"custom": True, "instrumental": True}))

    def test_results_keep_original_indexes_and_variable_song_counts(self):
        result = provider.normalize_task({"data": {"id": TASK_ID, "status": "completed", "progress": 100, "result": {"music": [{"audio_url": "https://cdn.apimart.ai/1", "duration_seconds": "181.7"}, {"audio_url": "http://127.0.0.1/private"}, {"audio_url": "https://cdn.apimart.ai/3", "lyrics": "<script>text</script>"}]}}}, TASK_ID)
        self.assertEqual([track["audio_index"] for track in result["tracks"]], [1, 3])
        self.assertEqual(result["tracks"][0]["duration"], 181.7)
        self.assertEqual(result["tracks"][1]["lyrics"], "<script>text</script>")

    def test_media_urls_reject_private_or_unsafe_targets(self):
        for url in ("javascript:alert(1)", "http://example.com/1", "https://user:pass@example.com/1", "https://127.0.0.1/a", "https://169.254.169.254/a", "https://localhost/a", "https://host.internal/a", "https://example.com:123/a"):
            with self.subTest(url=url): self.assertEqual(provider.safe_media_url(url), "")

    def test_unknown_status_does_not_become_success_at_100_percent(self):
        result = provider.normalize_task({"data": {"id": TASK_ID, "status": "new_unknown_status", "progress": 100}}, TASK_ID)
        self.assertEqual(result["status"], "unknown")

    def test_wrong_task_or_malformed_result_is_not_accepted(self):
        for data in ({"id": "someone_else", "status": "completed"}, {"id": TASK_ID, "result": {"music": {}}}):
            with self.assertRaises(provider.MusicError): provider.normalize_task({"data": data}, TASK_ID)

    def test_network_timeout_has_unknown_submission_outcome(self):
        with patch.object(provider.requests, "request", side_effect=requests.Timeout):
            with self.assertRaises(provider.MusicError) as caught: provider.submit_music("secret-test", {"model": "suno"})
        self.assertTrue(caught.exception.uncertain)
        self.assertNotIn("secret-test", str(caught.exception))

    def response(self, status, payload):
        response = Mock(status_code=status)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        import json
        response.iter_content.return_value = [json.dumps(payload).encode()]
        return response

    def test_submission_uses_only_apimart_and_never_follows_redirects(self):
        with patch.object(provider.requests, "request", return_value=self.response(200, {"code": 200, "data": [{"status": "submitted", "task_id": TASK_ID}]})) as call:
            self.assertEqual(provider.submit_music("test-secret", {"model": "suno"}), TASK_ID)
        self.assertEqual(call.call_args.args[1], "https://api.apimart.ai/v1/music/generations")
        self.assertFalse(call.call_args.kwargs["allow_redirects"])
        self.assertEqual(call.call_args.kwargs["headers"]["Authorization"], "Bearer test-secret")

    def test_explicit_rejection_is_safe_but_server_errors_are_uncertain(self):
        for status, uncertain in ((400, False), (401, False), (429, False), (500, True), (502, True)):
            with self.subTest(status=status), patch.object(provider.requests, "request", return_value=self.response(status, {"error": {"message": "secret data"}})):
                with self.assertRaises(provider.MusicError) as caught: provider.submit_music("test-key", {})
                self.assertEqual(caught.exception.uncertain, uncertain)
                self.assertNotIn("secret data", str(caught.exception))


    def test_custom_model_and_version_are_allowed_only_for_own_key(self):
        values = {"model": "provider/music-new", "version": "new-version", "parameter_format": "suno", "prompt": "钢琴"}
        with self.assertRaises(provider.MusicError): provider.build_music_request(values)
        body = provider.build_music_request(values, allow_custom=True)
        self.assertEqual(body["model"], "provider/music-new")
        self.assertEqual(body["version"], "new-version")
        self.assertNotIn("parameter_format", body)

    def test_empty_duration_is_represented_by_omitting_the_field(self):
        self.assertNotIn("length", provider.build_music_request({"model": "flowmusic", "lyrics": "歌词"}))
        self.assertNotIn("duration", provider.build_music_request({"model": "suno", "prompt": "钢琴"}))

    def test_custom_query_template_and_generation_host_must_match(self):
        endpoint, query = provider.custom_endpoints("https://music.example.invalid/v1/generations")
        self.assertEqual(query, "https://music.example.invalid/v1/tasks/{task_id}")
        for template in ("https://evil.invalid/task/{task_id}", "https://music.example.invalid/task/no-id", "https://music.example.invalid/task/{task_id}?key=secret"):
            with self.assertRaises(provider.MusicError): provider.custom_endpoints(endpoint, template)

    def test_dns_private_targets_are_blocked_before_connecting(self):
        with patch.object(provider.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("127.0.0.1", 443))]), patch.object(provider.urllib3, "HTTPSConnectionPool") as pool:
            with self.assertRaises(provider.MusicError): provider.pinned_custom_response("POST", "https://music.example.invalid/generate", {}, {})
            pool.assert_not_called()

    def test_custom_transport_pins_public_ip_preserving_tls_hostname(self):
        pool = Mock()
        pool.urlopen.return_value = Mock(status=200)
        with patch.object(provider.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("8.8.8.8", 443))]), patch.object(provider.urllib3, "HTTPSConnectionPool", return_value=pool) as connection:
            response = provider.pinned_custom_response("POST", "https://music.example.invalid/generate", {"x-api-key": "test"}, {})
            self.assertEqual(connection.call_args.args[0], "8.8.8.8")
            self.assertEqual(connection.call_args.kwargs["server_hostname"], "music.example.invalid")
            self.assertFalse(pool.urlopen.call_args.kwargs["redirect"])
            self.assertFalse(pool.urlopen.call_args.kwargs["retries"])
            self.assertEqual(pool.urlopen.call_args.kwargs["headers"]["Host"], "music.example.invalid")
            response.close()
            pool.close.assert_called_once()


class MusicRouteTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.headers = {"X-Billing-Mode": "own_key", "X-Music-Api-Key": "test-key", "X-Music-Endpoint": "https://music.example.invalid/v1/music/generations"}
        self.job = {"request_id": REQUEST_ID, "billing_mode": "own_key", "model": "suno", "version": "v6", "status": "submitted", "billing_status": "not_applicable", "provider_task_id": TASK_ID}
        self.store = Mock()
        self.store.begin.return_value = {"ok": True, "job": self.job, "existing": False}
        self.store.get.return_value = self.job
        self.store.apply.return_value = {"ok": True, "job": self.job}
        self.stack = __import__("contextlib").ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(routes, "MusicStore", return_value=self.store))
        self.stack.enter_context(patch.object(server, "optional_authenticated_user", return_value=None))
        server.REQUEST_RATE_WINDOWS.clear()

    def post(self, parameters=None):
        return self.client.post("/api/music/generations", headers=self.headers, json={"request_id": REQUEST_ID, "parameters": parameters or {"model": "suno", "prompt": "钢琴"}})

    def test_duplicate_intent_does_not_call_paid_provider_again(self):
        self.store.begin.return_value["existing"] = True
        with patch.object(routes, "submit_music") as paid:
            response = self.post()
        self.assertEqual(response.status_code, 200)
        paid.assert_not_called()

    def test_submission_does_not_charge_own_key_or_use_image_configuration(self):
        with patch.object(routes, "submit_music", return_value=TASK_ID) as paid:
            response = self.post()
        self.assertEqual(response.status_code, 202)
        self.assertEqual(paid.call_args.args[0], "test-key")
        self.assertEqual(self.store.begin.call_args.args[3], "own_key")
        self.assertNotIn("test-key", str(self.store.begin.call_args))
        self.assertNotIn("test-key", response.get_data(as_text=True))

    def test_bad_input_is_rejected_before_database_or_paid_request(self):
        with patch.object(routes, "submit_music") as paid:
            response = self.post({"model": "tts", "prompt": "hi"})
        self.assertEqual(response.status_code, 400)
        self.store.begin.assert_not_called(); paid.assert_not_called()

    def test_unknown_submission_is_recorded_without_refund(self):
        with patch.object(routes, "submit_music", side_effect=provider.MusicError("MUSIC_SUBMISSION_UNKNOWN", "unknown", 503, True)):
            response = self.post()
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.store.apply.call_args.args[2], "submission_unknown")

    def test_explicit_rejection_marks_failure(self):
        with patch.object(routes, "submit_music", side_effect=provider.MusicError("MUSIC_PROVIDER_REJECTED", "rejected", 502)):
            self.post()
        self.assertEqual(self.store.apply.call_args.args[2], "rejected")

    def test_platform_requires_login(self):
        with patch.dict(os.environ, {"APIMART_MUSIC_API_KEY": "platform-test"}):
            response = self.client.post("/api/music/generations", headers={"X-Billing-Mode": "platform"}, json={"request_id": REQUEST_ID, "parameters": {"prompt": "hi"}})
        self.assertEqual(response.status_code, 401)
        self.store.begin.assert_not_called()

    def test_guest_owner_scope_depends_on_key_and_not_browser_user_id(self):
        with patch.object(routes, "submit_music", return_value=TASK_ID): self.post()
        first = self.store.begin.call_args.args[0]
        self.headers["X-Music-Api-Key"] = "another-test-key"
        with patch.object(routes, "submit_music", return_value=TASK_ID): self.post()
        self.assertNotEqual(first, self.store.begin.call_args.args[0])

    def test_query_is_owner_scoped_and_settles_trusted_count(self):
        with patch.object(routes, "query_music", return_value={"status": "completed", "tracks": [{"audio_index": 1}, {"audio_index": 2}], "progress": 100, "error_code": None}):
            self.client.get(f"/api/music/tasks/{REQUEST_ID}", headers=self.headers)
        self.assertTrue(self.store.get.call_args.args[0].startswith("guest-"))
        self.assertEqual(self.store.apply.call_args.kwargs["count"], 2)

    def test_insufficient_settlement_balance_does_not_release_tracks(self):
        self.store.apply.return_value = {"job": {**self.job, "billing_mode": "platform", "billing_status": "awaiting_balance", "generated_count": 2}}
        with patch.object(routes, "query_music", return_value={"status": "completed", "tracks": [{"audio_index": 1}], "progress": 100, "error_code": None}):
            response = self.client.get(f"/api/music/tasks/{REQUEST_ID}", headers=self.headers)
        self.assertEqual(response.json["tracks"], [])

    def test_missing_media_is_not_an_automatic_refund(self):
        with patch.object(routes, "query_music", return_value={"status": "completed", "tracks": [], "progress": 100}):
            response = self.client.get(f"/api/music/tasks/{REQUEST_ID}", headers=self.headers)
        self.assertIn("warning", response.json); self.store.apply.assert_not_called()

    def test_cross_origin_submission_is_rejected(self):
        self.headers["Origin"] = "https://evil.invalid"
        self.assertEqual(self.post().status_code, 403)
        self.store.begin.assert_not_called()

    def test_private_no_store_and_no_sensitive_database_fields(self):
        self.store.jobs.return_value = [{**self.job, "request_fingerprint": "not-public", "owner_scope": "not-public"}]
        response = self.client.get("/api/music/tasks", headers=self.headers)
        self.assertEqual(response.headers["Cache-Control"], "private, no-store")
        self.assertNotIn("not-public", response.get_data(as_text=True))

    def test_scheduler_rejects_missing_credentials(self):
        self.assertEqual(self.client.post("/api/music/reconcile").status_code, 401)

    def test_platform_ignores_browser_provider_address_and_key(self):
        self.headers["X-Billing-Mode"] = "platform"
        with patch.dict(os.environ, {"APIMART_MUSIC_API_KEY": "platform-synthetic"}), patch.object(server, "optional_authenticated_user", return_value=Mock(id=USER_ID)), patch.object(routes, "submit_music", return_value=TASK_ID) as paid:
            response = self.post()
        self.assertEqual(response.status_code, 202)
        self.assertEqual(len(paid.call_args.args), 2)
        self.assertEqual(paid.call_args.args[0], "platform-synthetic")
        self.assertEqual(self.store.begin.call_args.args[0], f"user-{USER_ID}")

    def test_changing_provider_address_isolates_own_key_task_scope(self):
        with patch.object(routes, "submit_music", return_value=TASK_ID): self.post()
        first = self.store.begin.call_args.args[0]
        self.headers["X-Music-Endpoint"] = "https://another.example.invalid/generate"
        with patch.object(routes, "submit_music", return_value=TASK_ID): self.post()
        self.assertNotEqual(first, self.store.begin.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
