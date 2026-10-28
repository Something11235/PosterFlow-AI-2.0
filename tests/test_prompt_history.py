import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch
from backend import server
from backend.prompt_history import history_cursor, parse_history_cursor
from backend.supabase_service import SupabaseGateway


class PromptHistoryTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.user = Mock(id="authenticated-owner")
        self.gateway = Mock()
        self.row = {"id": "11111111-1111-4111-8111-111111111111", "prompt": "只返回提示词", "created_at": datetime.now(timezone.utc).isoformat(), "image_keys": ["private.png"], "provider": "private-host", "metadata": {"do_not_return": True}}
        self.gateway.prompt_history.return_value = [self.row]
        self.gateway.history_preview_jobs.return_value = []

    def get(self, query=""):
        with patch.object(server, "require_authenticated_user", return_value=self.user), patch.object(server, "SupabaseGateway", return_value=self.gateway):
            return self.client.get("/api/history" + query)

    def test_owner_is_server_identity_and_output_is_text_only(self):
        response = self.get("?user_id=forged-owner&client_id=forged-client")
        self.assertEqual(response.status_code, 200)
        entry = response.get_json()["entries"][0]
        self.assertEqual(set(entry), {"id", "prompt", "created_at"})
        self.assertNotIn("private", response.get_data(as_text=True))
        args = self.gateway.prompt_history.call_args.args
        self.assertEqual(args[0], "authenticated-owner")
        self.assertLess(abs((datetime.fromisoformat(args[1]) - (datetime.now(timezone.utc)-timedelta(days=7))).total_seconds()), 2)
        self.assertEqual(args[2:], (None, 51))
        self.assertEqual(response.headers["Cache-Control"], "private, no-store")

    def test_cursor_pages_by_time_and_id_without_offset(self):
        self.gateway.prompt_history.return_value = [self.row] * 51
        response = self.get()
        body = response.get_json()
        self.assertEqual(len(body["entries"]), 50)
        decoded = parse_history_cursor(body["next_cursor"])
        self.assertEqual(decoded[1], self.row["id"])
        self.assertEqual(self.get("?cursor="+body["next_cursor"]).status_code, 200)
        self.assertEqual(self.gateway.prompt_history.call_args.args[2], decoded)

    def test_invalid_cursors_do_not_reach_database(self):
        for value in ("invalid", "x"*600, history_cursor({**self.row, "id": "bad,id"}), history_cursor({**self.row, "created_at": "2026-10-21T12:00"})):
            self.assertEqual(self.get("?cursor="+value).status_code, 400)
        self.gateway.prompt_history.assert_not_called()

    def test_login_required_and_database_failure_is_not_empty_success(self):
        with patch.object(server, "require_authenticated_user", side_effect=server.ProviderError("AUTH_REQUIRED", "请先登录", 401)):
            self.assertEqual(self.client.get("/api/history").status_code, 401)
        self.gateway.prompt_history.side_effect = server.SupabaseError("UNAVAILABLE", "暂时不可用", 503)
        self.assertEqual(self.get().status_code, 503)

    def test_gateway_selects_only_text_and_keeps_cutoff_with_cursor(self):
        gateway = object.__new__(SupabaseGateway)
        cutoff = "2026-10-14T00:00:00+00:00"
        cursor = parse_history_cursor(history_cursor(self.row))
        with patch.object(gateway, "rpc", return_value=[]) as request:
            gateway.prompt_history("owner", cutoff, cursor)
        self.assertEqual(request.call_args.args[0], "get_prompt_history")
        params = request.call_args.args[1]
        self.assertEqual(params, {"p_user_id": "owner", "p_cutoff": cutoff, "p_before": cursor[0], "p_before_id": self.row["id"], "p_limit": 51})

    def test_music_history_never_returns_keys_endpoints_or_media(self):
        self.gateway.prompt_history.return_value = [{**self.row, "kind": "music", "parameters": {"model": "flowmusic", "lyrics": "歌词", "sound_prompt": "爵士", "api_key": "private-secret", "endpoint": "https://private.invalid", "audio_url": "https://private.invalid/track"}}]
        response = self.get()
        item = response.json["entries"][0]
        self.assertEqual(item["kind"], "music")
        self.assertEqual(item["parameters"], {"model": "flowmusic", "lyrics": "歌词", "sound_prompt": "爵士"})
        self.assertNotIn("private", response.get_data(as_text=True))

    def test_video_history_is_whitelisted_and_does_not_query_image_previews(self):
        self.gateway.prompt_history.return_value = [{**self.row, "kind": "video", "parameters": {
            "model": "seedance-2.0-mini", "prompt": "镜头推进", "duration": 5, "resolution": "480p", "seed": 0,
            "tools": [{"type":"web_search"}], "api_key": "private-secret", "video_urls": ["https://private.invalid/video"], "receipt":"private-proof"}}]
        response=self.get();item=response.json["entries"][0]
        self.assertEqual(item["kind"],"video");self.assertEqual(item["parameters"]["seed"],0)
        self.assertEqual(item["parameters"]["tools"],[{"type":"web_search"}])
        self.gateway.history_preview_jobs.assert_not_called()
        self.assertNotIn("private",response.get_data(as_text=True))


if __name__ == "__main__":
    unittest.main()
