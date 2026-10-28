import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from backend import server
from backend.prompt_history import history_preview_metadata
from backend.supabase_service import SupabaseGateway, SupabaseError

USER = "11111111-1111-4111-8111-111111111111"
JOB = "22222222-2222-4222-8222-222222222222"


class HistoryPreviewTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.now = datetime.now(timezone.utc)
        self.row = {"id": JOB, "created_at": (self.now-timedelta(hours=1)).isoformat(), "image_keys": ["one.png", "two.png"]}
        self.gateway = Mock()
        self.gateway.history_preview_jobs.return_value = [self.row]

    def preview(self, extra=""):
        with patch.object(server, "optional_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "SupabaseGateway", return_value=self.gateway), patch.object(server, "_storage_backend", return_value="supabase"), patch.object(server, "_supabase_create_signed_url", return_value="https://storage.example/_thumb_one.png") as sign, patch.object(server, "_storage_download") as download, patch.object(server, "store_generated_image") as store:
            response = self.client.get("/api/history/" + JOB + "/previews" + extra)
        return response, sign, download, store

    def test_recent_previews_sign_only_existing_thumbnail_paths_in_owner_scope(self):
        response, sign, download, store = self.preview("?user_id=forged-owner&filename=foreign.png")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["retention_hours"], 12)
        self.assertEqual(response.json["max_edge"], 512)
        self.assertEqual(len(response.json["previews"]), 2)
        self.assertTrue(all(item["variant"] == "thumbnail" for item in response.json["previews"]))
        self.assertEqual([item["filename"] for item in response.json["previews"]], ["one.png", "two.png"])
        self.assertEqual([call.args[0] for call in sign.call_args_list], [f"posterflow/user-{USER}/images/_thumb_one.png", f"posterflow/user-{USER}/images/_thumb_two.png"])
        self.assertTrue(all(call.kwargs["expires_in"] <= 300 for call in sign.call_args_list))
        self.assertEqual(self.gateway.history_preview_jobs.call_args.args[:2], (USER, [JOB]))
        self.assertEqual(response.headers["Cache-Control"], "private, no-store")
        download.assert_not_called(); store.assert_not_called()

    def test_twelve_hour_boundary_future_and_invalid_names_have_no_preview(self):
        for created in (self.now-timedelta(hours=12), self.now-timedelta(days=1), self.now+timedelta(seconds=1)):
            self.assertIsNone(history_preview_metadata({**self.row, "created_at": created.isoformat()}, self.now))
        for names in (["../foreign.png"], ["nested/foreign.png"], ["_thumb_one.png"], ["https://private/image.png"], [None], "one.png"):
            self.assertIsNone(history_preview_metadata({**self.row, "image_keys": names}, self.now))
        metadata = history_preview_metadata({**self.row, "image_keys": ["one.png", "one.png", "two.png"]}, self.now)
        self.assertEqual(metadata["filenames"], ["one.png", "two.png"])

    def test_expired_or_unowned_job_is_unavailable_without_signing(self):
        for rows in ([], [{**self.row, "created_at": (self.now-timedelta(hours=12)).isoformat()}], [{**self.row, "id": USER}]):
            self.gateway.history_preview_jobs.return_value = rows
            response, sign, download, store = self.preview()
            self.assertEqual(response.status_code, 404)
            sign.assert_not_called(); download.assert_not_called(); store.assert_not_called()

    def test_missing_thumbnails_never_fall_back_to_original_or_backfill(self):
        with patch.object(server, "optional_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "SupabaseGateway", return_value=self.gateway), patch.object(server, "_storage_backend", return_value="supabase"), patch.object(server, "_supabase_create_signed_url", side_effect=server.ProviderError("MISSING", "missing", 404)) as sign, patch.object(server, "_storage_download") as download, patch.object(server, "create_image_preview") as create:
            response = self.client.get(f"/api/history/{JOB}/previews")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["previews"], [])
        self.assertEqual(sign.call_count, 2)
        self.assertTrue(all("/_thumb_" in call.args[0] for call in sign.call_args_list))
        download.assert_not_called(); create.assert_not_called()

    def test_short_signed_lifetime_does_not_exceed_remaining_history_window(self):
        self.gateway.history_preview_jobs.return_value = [{**self.row, "created_at": (self.now-timedelta(hours=12)+timedelta(seconds=45)).isoformat()}]
        response, sign, _, _ = self.preview()
        self.assertEqual(response.status_code, 200)
        self.assertLessEqual(sign.call_args.kwargs["expires_in"], 45)
        self.assertGreater(sign.call_args.kwargs["expires_in"], 0)

    def test_auth_and_uuid_validation_precede_database(self):
        with patch.object(server, "require_authenticated_user", side_effect=server.ProviderError("AUTH_REQUIRED", "请先登录", 401)), patch.object(server, "SupabaseGateway") as gateway:
            self.assertEqual(self.client.get(f"/api/history/{JOB}/previews").status_code, 401)
            gateway.assert_not_called()
        with patch.object(server, "optional_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "SupabaseGateway") as gateway:
            self.assertEqual(self.client.get("/api/history/not-a-uuid/previews").status_code, 400)
            gateway.assert_not_called()

    def test_history_list_exposes_only_count_and_expiry_without_signing(self):
        self.gateway.prompt_history.return_value = [{"id": JOB, "created_at": self.row["created_at"], "prompt": "图像提示词"}]
        with patch.object(server, "optional_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "SupabaseGateway", return_value=self.gateway), patch.object(server, "_supabase_create_signed_url") as sign:
            response = self.client.get("/api/history?user_id=forged-owner")
        entry = response.json["entries"][0]
        self.assertEqual(entry["preview_count"], 2)
        self.assertNotIn("one.png", response.get_data(as_text=True))
        self.assertEqual(set(entry), {"id", "created_at", "prompt", "preview_count", "preview_expires_at"})
        sign.assert_not_called()

    def test_preview_metadata_failure_does_not_break_text_history(self):
        self.gateway.prompt_history.return_value = [{"id": JOB, "created_at": self.row["created_at"], "prompt": "图像提示词"}]
        self.gateway.history_preview_jobs.side_effect = SupabaseError("UNAVAILABLE", "unavailable", 503)
        with patch.object(server, "optional_authenticated_user", return_value=Mock(id=USER)), patch.object(server, "SupabaseGateway", return_value=self.gateway):
            response = self.client.get("/api/history")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["previews_unavailable"])
        self.assertEqual(response.json["entries"][0]["prompt"], "图像提示词")

    def test_gateway_limits_metadata_to_owner_ids_cutoff_and_small_columns(self):
        gateway = object.__new__(SupabaseGateway)
        cutoff = (self.now-timedelta(hours=12)).isoformat()
        with patch.object(gateway, "_request", return_value=[]) as request:
            self.assertEqual(gateway.history_preview_jobs(USER, [], cutoff), [])
            request.assert_not_called()
            gateway.history_preview_jobs(USER, [JOB, JOB], cutoff)
            params = request.call_args.kwargs["params"]
            self.assertEqual(params["user_id"], "eq."+USER)
            self.assertEqual(params["id"], "in.("+JOB+")")
            self.assertEqual(params["created_at"], "gt."+cutoff)
            self.assertEqual(params["select"], "id,created_at,image_keys")
            self.assertEqual(params["limit"], "1")
            with self.assertRaises(ValueError):
                gateway.history_preview_jobs(USER, ["forged),or(user_id.not.is.null)"], cutoff)
