import io
import json
import unittest
from unittest.mock import Mock, patch

import requests
from PIL import Image
from backend import apimart_image_provider as provider, apimart_image_routes as routes, server

USER = "11111111-1111-4111-8111-111111111111"
REQUEST = "22222222-2222-4222-8222-222222222222"
TASK = "task_image_test_0123456789"


def response(payload, status=200):
    result = Mock(status_code=status)
    result.iter_content.return_value = [json.dumps(payload).encode()]
    return result


class ImageProtocolTests(unittest.TestCase):
    def test_documented_models_and_fields(self):
        for model in provider.MODELS:
            body = provider.build_request(model, {"prompt": "猫", "count": 1, "size": "landscape_16_9"})
            self.assertEqual(body["n"], 1)
            self.assertNotIn("quality", body)
            self.assertNotIn("input_references", body)
            self.assertEqual(body.get("aspect_ratio") or body.get("size"), "16:9")
        self.assertEqual(provider.build_request("grok-imagine-image-2.0", {"prompt": "@图1 @图3", "resolution": "2K"}, ["one", "two", "three"])["prompt"], "<IMAGE_0> <IMAGE_2>")

    def test_model_capabilities_reject_before_paid_calls(self):
        invalid = [
            ("grok-imagine-2.0-ext", {"prompt": "cat"}, ["ref"]),
            ("grok-imagine-image-2.0", {"prompt": "cat"}, ["ref"] * 4),
            ("nano-banana-pro", {"prompt": "cat", "count": 2}, []),
            ("grok-imagine-2.0-ext", {"prompt": "cat", "size": "wide_21_9"}, []),
            ("grok-imagine-image-2.0", {"prompt": "cat", "resolution": "4K"}, []),
            ("gemini-nano-banana-2.1", {"prompt": "cat", "mask_b64": "mask"}, []),
        ]
        for model, data, references in invalid:
            with self.subTest(model=model, data=data), self.assertRaises(provider.ImageTaskError):
                provider.build_request(model, data, references)

    def test_provider_body_whitelist_omits_secrets_and_callbacks(self):
        body = provider.build_request("nano-banana-pro", {"prompt": "cat", "api_key": "sentinel", "webhook": "https://invalid.test", "quality": "high", "provider": "override"})
        self.assertEqual(set(body), {"model", "prompt", "n", "size", "resolution"})
        self.assertNotIn("sentinel", json.dumps(body))

    def test_both_submission_shapes_and_idempotency(self):
        for payload in ({"code": 200, "data": [{"task_id": TASK}]}, {"code": 202, "data": {"id": TASK}}):
            with patch.object(provider.requests, "request", return_value=response(payload)) as request:
                self.assertEqual(provider.submit("synthetic-key", {}, REQUEST), TASK)
                kwargs = request.call_args.kwargs
                self.assertEqual(kwargs["headers"]["Idempotency-Key"], REQUEST)
                self.assertEqual(kwargs["headers"]["X-APIMart-Response-Version"], "2026-07-27")
                self.assertFalse(kwargs["allow_redirects"])
                request.assert_called_once()

    def test_timeout_500_and_409_do_not_claim_rejection_or_resubmit(self):
        for status in (500, 409, 302):
            with patch.object(provider.requests, "request", return_value=response({}, status)) as request:
                with self.assertRaises(provider.ImageTaskError) as error:
                    provider.submit("synthetic-key", {}, REQUEST)
                self.assertTrue(error.exception.uncertain)
                request.assert_called_once()
        with patch.object(provider.requests, "request", side_effect=requests.Timeout("secret-url")):
            with self.assertRaises(provider.ImageTaskError) as error:
                provider.submit("synthetic-key", {}, REQUEST)
            self.assertNotIn("secret-url", str(error.exception))
            self.assertTrue(error.exception.uncertain)

    def test_rejected_post_and_wrong_task_response(self):
        with patch.object(provider.requests, "request", return_value=response({}, 402)):
            with self.assertRaises(provider.ImageTaskError) as error:
                provider.submit("synthetic-key", {}, REQUEST)
            self.assertFalse(error.exception.uncertain)
        with patch.object(provider, "api_request", return_value={"data": {"id": "different-task", "status": "completed"}}):
            with self.assertRaises(provider.ImageTaskError):
                provider.query("synthetic-key", TASK)

    def test_documented_url_array_task_shape(self):
        with patch.object(provider, "api_request", return_value={"data": {"id": TASK, "status": "completed", "result": {"images": [{"url": ["https://upload.apimart.ai/a.png", "https://upload.apimart.ai/b.png"]}]}}}):
            result = provider.query("synthetic-key", TASK)
        self.assertEqual(len(result["urls"]), 2)

    def test_media_fetch_has_no_credentials_and_rejects_private_hosts(self):
        stream = io.BytesIO(); Image.new("RGB", (8, 8), "red").save(stream, format="PNG")
        pool = Mock(); pool.urlopen.return_value = Mock(status=200)
        pool.urlopen.return_value.stream.return_value = [stream.getvalue()]
        with patch.object(provider.socket, "getaddrinfo", return_value=[(None, None, None, None, ("8.8.8.8", 443))]), patch.object(provider.urllib3, "HTTPSConnectionPool", return_value=pool):
            result = provider.download_image("https://upload.apimart.ai/a.png?token=synthetic")
        self.assertTrue(result.startswith(b"\x89PNG"))
        self.assertEqual(pool.urlopen.call_args.kwargs["headers"], {"Host": "upload.apimart.ai"})
        self.assertFalse(pool.urlopen.call_args.kwargs["redirect"])
        for url in ("http://example.test/image.png", "https://user:key@example.test/image.png", "https://example.test:1234/image.png"):
            with self.assertRaises(provider.ImageTaskError):
                provider.download_image(url)
        with patch.object(provider.socket, "getaddrinfo", return_value=[(None, None, None, None, ("127.0.0.1", 443))]):
            with self.assertRaises(provider.ImageTaskError):
                provider.download_image("https://example.test/image.png")


class ImageRouteTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.headers = {"X-Billing-Mode": "platform"}
        self.job = {"id": "33333333-3333-4333-8333-333333333333", "request_id": REQUEST, "model": "nano-banana-pro", "billing_mode": "platform", "status": "submitted", "requested_count": 1, "image_keys": [], "provider_task_id": TASK, "created_at": "2026-10-23T00:00:00+00:00"}
        self.body = {"platform_model": "nano-banana-pro", "request_id": REQUEST, "prompt": "cat"}

    def test_duplicate_submit_never_calls_provider_twice(self):
        store = Mock()
        store.begin.return_value = {"ok": True, "existing": True, "job": self.job, "balance": 9}
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(provider, "submit") as submit:
            result = self.client.post("/api/apimart-images/generations", json=self.body, headers=self.headers)
        self.assertEqual(result.status_code, 200)
        submit.assert_not_called()

    def test_model_override_and_reference_limit_do_not_reserve(self):
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore") as store:
            result = self.client.post("/api/apimart-images/generations", json=self.body, headers={**self.headers, "X-Provider-Api-Key": "synthetic-other"})
            self.assertEqual(result.status_code, 400)
            result = self.client.post("/api/apimart-images/generations", json={**self.body, "count": 2}, headers=self.headers)
            self.assertEqual(result.status_code, 400)
            store.assert_not_called()

    def test_unknown_submission_is_retained_not_refunded(self):
        store = Mock()
        store.begin.return_value = {"existing": False, "job": self.job, "balance": 9}
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(provider, "submit", side_effect=provider.ImageTaskError("UNCERTAIN", "uncertain", 503, True)):
            result = self.client.post("/api/apimart-images/generations", json=self.body, headers=self.headers)
        self.assertEqual(result.status_code, 503)
        self.assertEqual(store.apply.call_args.args[2], "submission_unknown")

    def test_read_failure_releases_save_lease_without_refund(self):
        store = Mock(); store.jobs.return_value = [self.job]
        store.apply.return_value = {"claimed": True, "job": self.job}
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(provider, "query", return_value={"status": "completed", "urls": ["https://upload.apimart.ai/a.png"]}), patch.object(provider, "download_image", side_effect=provider.ImageTaskError("READ_FAILED", "not saved", 503)):
            result = self.client.get("/api/apimart-images/tasks/" + REQUEST, headers=self.headers)
        self.assertEqual(result.status_code, 503)
        self.assertEqual([call.args[2] for call in store.apply.call_args_list], ["claim", "retry"])

    def test_unknown_owner_and_reconcile_auth_do_not_read_media(self):
        store = Mock();store.jobs.return_value = []
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key", "APIMART_IMAGE_RECONCILE_SECRET": ""}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(provider, "query") as query:
            self.assertEqual(self.client.get("/api/apimart-images/tasks/" + REQUEST, headers=self.headers).status_code, 404)
            self.assertEqual(self.client.post("/api/apimart-images/reconcile").status_code, 401)
            query.assert_not_called()

    def test_completed_images_are_saved_before_exact_count_settlement(self):
        store = Mock(); store.jobs.return_value = [{**self.job, "requested_count": 2}]
        saved_job = {**self.job, "status": "completed", "image_keys": ["one.png", "two.png"]}
        store.apply.side_effect = [{"claimed": True, "job": self.job}, {"job": saved_job, "balance": 8}]
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(provider, "query", return_value={"status": "completed", "urls": ["https://upload.apimart.ai/a.png", "https://upload.apimart.ai/b.png"]}), patch.object(provider, "download_image", return_value=b"image-bytes"), patch.object(server, "store_generated_image") as save:
            result = self.client.get("/api/apimart-images/tasks/" + REQUEST, headers=self.headers)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(save.call_count, 2)
        self.assertEqual(store.apply.call_args.args[2], "completed")
        self.assertEqual(len(store.apply.call_args.kwargs["p_images"]), 2)
        self.assertEqual(result.json["credit_balance"], 8)

    def test_unexpected_output_count_never_overcharges(self):
        store = Mock();store.jobs.return_value = [self.job]
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(provider, "query", return_value={"status": "completed", "urls": ["a", "b"]}), patch.object(provider, "download_image") as download:
            result = self.client.get("/api/apimart-images/tasks/" + REQUEST, headers=self.headers)
        self.assertEqual(result.status_code, 503)
        store.apply.assert_not_called()
        download.assert_not_called()

    def test_reference_upload_failure_refunds_without_submitting_generation(self):
        store = Mock();store.begin.return_value = {"existing": False, "job": self.job}
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(routes, "ImageStore", return_value=store), patch.object(server, "validate_reference_images_b64", return_value=["synthetic-base64"]), patch.object(provider, "upload_reference", side_effect=provider.ImageTaskError("UPLOAD_FAILED", "upload failed", 502)), patch.object(provider, "submit") as submit:
            result = self.client.post("/api/apimart-images/generations", json=self.body, headers=self.headers)
        self.assertEqual(result.status_code, 502)
        self.assertEqual(store.apply.call_args.args[2], "failed")
        submit.assert_not_called()

    def test_expired_previous_image_is_rejected_before_reservation(self):
        with patch.dict("os.environ", {"APIMART_IMAGE_API_KEY": "synthetic-key"}), patch.object(server, "require_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(server, "stored_image_to_base64", return_value=None), patch.object(routes, "ImageStore") as store:
            result = self.client.post("/api/apimart-images/generations", json={**self.body, "previous_image": "expired.png"}, headers=self.headers)
        self.assertEqual(result.status_code, 400)
        self.assertEqual(result.json["code"], "PREVIOUS_IMAGE_MISSING")
        store.assert_not_called()


if __name__ == "__main__":
    unittest.main()
