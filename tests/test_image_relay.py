import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from backend import image_relay, server

USER = "11111111-1111-4111-8111-111111111111"
PNG = b"\x89PNG\r\n\x1a\n" + b"a" * (image_relay.CHUNK_BYTES + 35)


class ImageRelayTests(unittest.TestCase):
    def read(self, offset=0, content=PNG, extra=None, version=None, chunks=None, status=206):
        part = content[offset:offset + image_relay.CHUNK_BYTES]
        response = Mock(status_code=status, headers={"Content-Range": f"bytes {offset}-{offset + len(part)-1}/{len(content)}", "ETag": '"image-v1"'})
        response.iter_content.return_value = chunks if chunks is not None else [part]
        if extra:
            response.headers.update(extra)
        headers = {"X-Image-Version": version or '"image-v1"'} if offset else {}
        with patch.object(server, "require_authenticated_user", return_value=SimpleNamespace(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(server, "_storage_backend", return_value="supabase"), patch.object(server, "_supabase_storage_request", return_value=response) as storage:
            result = server.app.test_client().get(f"/api/images/test.png/content?offset={offset}", headers=headers)
        return result, response, storage

    def test_owned_chunks_reconstruct_exact_original_and_stay_bounded(self):
        parts = []
        for offset in (0, image_relay.CHUNK_BYTES):
            result, upstream, storage = self.read(offset)
            self.assertEqual(result.status_code, 200)
            parts.append(result.data)
            self.assertLessEqual(len(result.data), image_relay.CHUNK_BYTES)
            self.assertEqual(result.headers["Cache-Control"], "private, no-store")
            self.assertEqual(result.headers["X-Image-Size"], str(len(PNG)))
            self.assertIn("user-" + USER + "/images/test.png", storage.call_args.args[1])
            self.assertEqual(storage.call_args.kwargs["headers"]["Range"], f"bytes={offset}-{offset+image_relay.CHUNK_BYTES-1}")
            self.assertFalse(storage.call_args.kwargs["allow_redirects"])
            upstream.close.assert_called_once()
        self.assertEqual(b"".join(parts), PNG)

    def test_unauthenticated_requests_cannot_read_storage(self):
        with patch.object(server, "require_authenticated_user", side_effect=server.ProviderError("AUTH_REQUIRED", "请先登录", 401)), patch.object(server, "_supabase_storage_request") as storage:
            self.assertEqual(server.app.test_client().get("/api/images/test.png/content").status_code, 401)
            storage.assert_not_called()

    def test_bad_offsets_names_and_missing_version_stop_before_storage(self):
        with patch.object(server, "require_authenticated_user", return_value=SimpleNamespace(id=USER)), patch.object(server, "_supabase_storage_request") as storage:
            for path in ("test.png/content?offset=-1", "test.png/content?offset=1", "test.png/content?offset=999999999999", "test.png/content?offset=1048576", "_thumb_test.png/content", "a..png/content"):
                self.assertEqual(server.app.test_client().get("/api/images/" + path).status_code, 400)
            storage.assert_not_called()

    def test_bad_ranges_versions_and_oversized_totals_are_rejected(self):
        for headers in ({"Content-Range": ""}, {"Content-Range": "bytes 0-1048575/999999999"}, {"Content-Range": "bytes 1-1048576/2097152"}, {"ETag": 'W/"weak"'}):
            result, upstream, _ = self.read(extra=headers)
            self.assertEqual(result.status_code, 502)
            upstream.iter_content.assert_not_called()
            upstream.close.assert_called_once()
        result, _, _ = self.read(image_relay.CHUNK_BYTES, version='"other"')
        self.assertEqual(result.status_code, 502)

    def test_invalid_file_and_truncated_read_never_return_fake_image(self):
        result, upstream, _ = self.read(content=b"<html>error</html>")
        self.assertEqual(result.status_code, 502)
        upstream.close.assert_called_once()
        for chunks in ([b"short"], [PNG], []):
            result, upstream, _ = self.read(chunks=chunks)
            self.assertEqual(result.status_code, 502)
            upstream.close.assert_called_once()
        result, upstream, _ = self.read(status=200)
        self.assertEqual(result.status_code, 502)
        upstream.iter_content.assert_not_called()

    def test_missing_object_returns_404_without_private_path(self):
        with patch.object(server, "require_authenticated_user", return_value=SimpleNamespace(id=USER)), patch.object(server, "enforce_rate_limit"), patch.object(server, "_storage_backend", return_value="supabase"), patch.object(server, "_supabase_storage_request", side_effect=server.ProviderError("STORAGE_FILE_MISSING", "图片不存在", 404)):
            result = server.app.test_client().get("/api/images/test.png/content")
        self.assertEqual(result.status_code, 404)
        self.assertNotIn(USER, result.get_data(as_text=True))

    def test_read_deadline_aborts_and_closes_instead_of_returning_partial_bytes(self):
        with patch.object(image_relay.time, "monotonic", side_effect=[0, 31]):
            result, upstream, _ = self.read()
        self.assertEqual(result.status_code, 502)
        upstream.close.assert_called_once()
