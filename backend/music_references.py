"""Owner-bound, verified temporary audio. No public bucket or arbitrary URLs."""
import base64
import hashlib
import hmac
import io
import json
import math
import re
import time
import uuid
import wave
from urllib.parse import urlsplit

from tinytag import TinyTag

try:
    from backend.music_provider import MusicError
except ModuleNotFoundError:
    from music_provider import MusicError

MAX_BYTES = 20 * 1024 * 1024
MAX_SECONDS = 480
RETENTION_SECONDS = 12 * 3600
REFERENCE_ID = re.compile(r"^[0-9]{10}-[a-f0-9]{32}\.(mp3|wav)$")


def audio_metadata(data, extension):
    if not data or len(data) > MAX_BYTES:
        raise MusicError("MUSIC_REFERENCE_SIZE", "音频文件须大于 0，且不超过 20 MB。")
    try:
        if extension == "wav":
            with wave.open(io.BytesIO(data), "rb") as audio:
                frames, rate = audio.getnframes(), audio.getframerate()
                expected = frames * audio.getnchannels() * audio.getsampwidth()
                if not rate or expected > MAX_BYTES or len(audio.readframes(frames)) != expected:
                    raise ValueError("truncated WAV")
                duration = frames / rate
        elif extension == "mp3" and (data.startswith(b"ID3") or data[0] == 255 and data[1] & 224 == 224):
            tag = TinyTag.get(file_obj=io.BytesIO(data), tags=False, image=False)
            if not (tag.mime_type or "").startswith("audio/mpeg"):
                raise ValueError("not MP3")
            duration = float(tag.duration or 0)
        else:
            raise ValueError("unsupported audio")
    except Exception as exc:
        raise MusicError("MUSIC_REFERENCE_INVALID", "音频无法读取，请使用有效的 MP3 或 PCM WAV 文件。") from exc
    if not math.isfinite(duration) or not 1 <= duration <= MAX_SECONDS:
        raise MusicError("MUSIC_REFERENCE_DURATION", "本站参考音频须为 1 秒至 8 分钟，请先剪短音频。")
    return {"duration": round(duration, 3), "size": len(data), "content_type": "audio/mpeg" if extension == "mp3" else "audio/wav"}


class MusicReferences:
    def __init__(self, server):
        self.server = server

    @property
    def available(self):
        return bool(self.server.SUPABASE_STORAGE_ENABLED and self.server.SUPABASE_STORAGE_SERVICE_KEY)

    def _secret(self):
        secret = self.server.SUPABASE_STORAGE_SERVICE_KEY
        if not self.server.SUPABASE_STORAGE_ENABLED or not secret:
            raise MusicError("MUSIC_REFERENCE_UNAVAILABLE", "音频素材服务尚未配置。", 503)
        return hashlib.sha256(("posterflow-audio-reference-v1:" + secret).encode()).digest()

    def _token(self, payload):
        body = base64.urlsafe_b64encode(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).decode().rstrip("=")
        return body + "." + hmac.new(self._secret(), body.encode(), hashlib.sha256).hexdigest()

    def verify(self, token, owner, stage="verified", allow_expired=False):
        try:
            if not isinstance(token, str) or len(token) > 4096:
                raise ValueError()
            body, signature = token.split(".")
            if not re.fullmatch(r"[A-Za-z0-9_-]+", body) or not hmac.compare_digest(signature, hmac.new(self._secret(), body.encode(), hashlib.sha256).hexdigest()):
                raise ValueError()
            value = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
            if value.get("v") != 1 or value.get("stage") != stage or value.get("owner") != hashlib.sha256(owner.encode()).hexdigest():
                raise ValueError()
            if not REFERENCE_ID.fullmatch(value.get("id", "")) or type(value.get("size")) is not int or not 0 < value["size"] <= MAX_BYTES:
                raise ValueError()
            if type(value.get("issued")) is not int or value["issued"] > time.time() + 30 or value.get("expires") != value["issued"] + (7200 if stage == "upload" else RETENTION_SECONDS):
                raise ValueError()
            if stage == "verified" and (not isinstance(value.get("sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", value["sha256"])):
                raise ValueError()
        except (ValueError, TypeError, KeyError, AttributeError):
            raise MusicError("MUSIC_REFERENCE_INVALID", "音频素材无效或不属于当前服务，请重新添加。") from None
        if not allow_expired and value["expires"] <= time.time() + (900 if stage == "verified" else 0):
            raise MusicError("MUSIC_REFERENCE_EXPIRED", "音频素材已过期或临近清理，请重新添加后生成。")
        return value

    @staticmethod
    def path(value):
        return f"posterflow/music-{value['owner']}/audio-references/{value['id']}"

    def _request(self, method, path, **kwargs):
        self._secret()
        try:
            return self.server._supabase_storage_request(method, path, allow_redirects=False, **kwargs)
        except Exception as exc:
            raise MusicError("MUSIC_REFERENCE_STORAGE", "音频素材服务暂时无法完成请求，请稍后重试。", 503) from exc

    def _safe_url(self, raw):
        if not isinstance(raw, str) or not raw:
            raise MusicError("MUSIC_REFERENCE_STORAGE", "音频素材未返回有效的临时地址。", 503)
        url = raw if raw.startswith("https://") else self.server.SUPABASE_STORAGE_URL + raw if raw.startswith("/storage/v1/") else self.server._supabase_storage_url(raw)
        parsed, expected = urlsplit(url), urlsplit(self.server.SUPABASE_STORAGE_URL)
        if parsed.scheme != "https" or parsed.netloc != expected.netloc or parsed.username or parsed.password or parsed.fragment or not parsed.path.startswith("/storage/v1/object/"):
            raise MusicError("MUSIC_REFERENCE_STORAGE", "音频素材临时地址无效。", 503)
        return url

    def issue(self, owner, filename, size, content_type):
        if not isinstance(filename, str) or type(size) is not int or not 0 < size <= MAX_BYTES:
            raise MusicError("MUSIC_REFERENCE_SIZE", "音频文件须大于 0，且不超过 20 MB。")
        name = re.split(r"[\\/]", filename)[-1]
        name = re.sub(r"[\x00-\x1f\x7f]", "", name)[:120]
        ext = name.rsplit(".", 1)[-1].lower()
        if ext not in {"mp3", "wav"} or content_type not in {"audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/wave", ""}:
            raise MusicError("MUSIC_REFERENCE_TYPE", "参考音频目前支持 MP3、WAV。")
        issued = int(time.time())
        value = {"v": 1, "stage": "upload", "owner": hashlib.sha256(owner.encode()).hexdigest(), "id": f"{issued}-{uuid.uuid4().hex}.{ext}", "name": name, "size": size, "issued": issued, "expires": issued + 7200}
        path = self.server._supabase_object_path(self.path(value))
        with self._request("POST", "/object/upload/sign/" + path, headers={"Content-Type": "application/json", "x-upsert": "false"}, json={}) as response:
            url = self._safe_url(response.json().get("url"))
        return {"upload_ticket": self._token(value), "signed_url": url, "content_type": "audio/mpeg" if ext == "mp3" else "audio/wav"}

    def complete(self, owner, ticket):
        value = self.verify(ticket, owner, "upload")
        path = self.server._supabase_object_path(self.path(value))
        with self._request("GET", "/object/authenticated/" + path, headers={"Accept": "application/octet-stream"}, stream=True, _allow_missing=True) as response:
            if int(response.headers.get("Content-Length", "0")) > min(MAX_BYTES, value["size"]):
                raise MusicError("MUSIC_REFERENCE_SIZE", "上传后的音频大小不符合要求，请重新添加。")
            chunks, size = [], 0
            for chunk in response.iter_content(65536):
                size += len(chunk)
                if size > MAX_BYTES or size > value["size"]:
                    raise MusicError("MUSIC_REFERENCE_SIZE", "上传后的音频大小不符合要求，请重新添加。")
                chunks.append(chunk)
        data = b"".join(chunks)
        if len(data) != value["size"]:
            raise MusicError("MUSIC_REFERENCE_INVALID", "音频上传未完成，请重新添加。")
        info = audio_metadata(data, value["id"].rsplit(".", 1)[1])
        value.update(stage="verified", expires=value["issued"] + RETENTION_SECONDS, sha256=hashlib.sha256(data).hexdigest(), duration=info["duration"])
        return {"id": value["id"], "name": value["name"], **info, "expires_at": value["expires"], "receipt": self._token(value)}

    def urls(self, values):
        urls = []
        for value in values:
            remaining = int(value["expires"] - time.time())
            if remaining < 900:
                raise MusicError("MUSIC_REFERENCE_EXPIRED", "音频素材即将清理，请重新添加。")
            path = self.server._supabase_object_path(self.path(value))
            with self._request("POST", "/object/sign/" + path, headers={"Content-Type": "application/json"}, json={"expiresIn": min(3600, remaining)}) as response:
                result = response.json()
                urls.append(self._safe_url(result.get("signedURL") or result.get("signedUrl") or result.get("signed_url")))
        return urls
