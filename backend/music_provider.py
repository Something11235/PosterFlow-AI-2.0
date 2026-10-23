"""APIMart music only. Image providers are deliberately independent."""
import ipaddress
import json
import math
import re
import socket
from urllib.parse import urlsplit

import requests
import urllib3

API_BASE = "https://api.apimart.ai/v1/music"
SUNO_VERSIONS = ("v6", "v6-wild", "v6-mini")
FLOW_VERSIONS = ("lyria-3-pro", "lyria-3.5")
TASK_ID = re.compile(r"^[A-Za-z0-9_-]{8,160}$")


class MusicError(Exception):
    def __init__(self, code, message, status=400, uncertain=False):
        super().__init__(message)
        self.code, self.message, self.status, self.uncertain = code, message, status, uncertain


def text(value, name, maximum):
    if not isinstance(value, str):
        raise MusicError("INVALID_MUSIC_INPUT", f"{name}必须是文字。")
    value = value.strip()
    if len(value) > maximum:
        raise MusicError("INVALID_MUSIC_INPUT", f"{name}不能超过 {maximum} 个字符。")
    return value


def flag(data, name, default=False):
    value = data.get(name, default)
    if not isinstance(value, bool):
        raise MusicError("INVALID_MUSIC_INPUT", f"{name}必须是布尔值。")
    return value


def integer(value, name, low, high):
    if type(value) is not int or not low <= value <= high:
        raise MusicError("INVALID_MUSIC_INPUT", f"{name}须为 {low}–{high} 的整数。")
    return value


def build_music_request(data, allow_custom=False):
    if not isinstance(data, dict):
        raise MusicError("INVALID_MUSIC_INPUT", "音乐参数必须是对象。")
    model = data.get("model", "suno")
    if not isinstance(model, str):
        raise MusicError("INVALID_MUSIC_INPUT", "音乐模型标识必须是文字。")
    custom_model = model not in {"suno", "flowmusic"} or (allow_custom and "parameter_format" in data)
    if custom_model:
        if not allow_custom or not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}", model):
            raise MusicError("INVALID_MUSIC_INPUT", "请填写有效的自定义音乐模型标识。")
        parameter_format = data.get("parameter_format")
        if parameter_format not in {"suno", "flowmusic"}:
            raise MusicError("INVALID_MUSIC_INPUT", "请选择自定义模型的参数格式。")
        normalized = {key: value for key, value in data.items() if key not in {"model", "version", "parameter_format"}}
        normalized.update(model=parameter_format, version="v6" if parameter_format == "suno" else "lyria-3-pro")
        body = build_music_request(normalized)
        body["model"] = model
        body.pop("version", None)
        version = text(data.get("version", ""), "模型版本", 128)
        if version:
            body["version"] = version
        return body
    common = {"model", "version", "title"}
    allowed = common | ({"custom", "instrumental", "prompt", "style", "vocal_gender", "negative_tags", "auto_lyrics", "style_weight", "weirdness_constraint", "audio_weight", "variety", "audio_format", "duration"} if model == "suno" else {"sound_prompt", "lyrics", "bpm", "length", "seed"})
    if model not in {"suno", "flowmusic"} or set(data) - allowed:
        raise MusicError("INVALID_MUSIC_INPUT", "音乐模型或请求字段不受支持。")
    version = data.get("version", "v6" if model == "suno" else "lyria-3-pro")
    if version not in (SUNO_VERSIONS if model == "suno" else FLOW_VERSIONS):
        raise MusicError("INVALID_MUSIC_VERSION", "请选择可用的音乐版本。")
    body = {"model": model}
    # The documented standard Flow route omits version; 3.5 is explicit.
    if model == "suno" or version == "lyria-3.5":
        body["version"] = version
    if model == "flowmusic":
        for name, label, limit in (("sound_prompt", "音乐描述", 6000), ("lyrics", "歌词", 6000), ("title", "歌曲标题", 200), ("seed", "随机种子", 128)):
            value = text(data.get(name, ""), label, limit)
            if value:
                body[name] = value
        if not body.get("sound_prompt") and not body.get("lyrics"):
            raise MusicError("INVALID_MUSIC_INPUT", "请填写音乐描述或歌词。")
        if "length" in data:
            body["length"] = integer(data["length"], "时长", 1, 240)
        bpm = data.get("bpm", "")
        if bpm != "":
            if not isinstance(bpm, str) or not re.fullmatch(r"[0-9]{1,4}(?:\.[0-9]{1,2})?", bpm) or float(bpm) < 1:
                raise MusicError("INVALID_MUSIC_INPUT", "BPM 须为不小于 1 的数字。")
            body["bpm"] = bpm
        return body
    custom, instrumental = flag(data, "custom"), flag(data, "instrumental")
    body.update(custom=custom, instrumental=instrumental)
    prompt = text(data.get("prompt", ""), "歌词" if custom else "音乐描述", 5000 if custom else 3000)
    if not prompt and (not custom or not instrumental):
        raise MusicError("INVALID_MUSIC_INPUT", "请填写歌词，或开启纯音乐。" if custom else "请填写音乐描述。")
    if prompt:
        body["prompt"] = prompt
    if custom:
        for name, label, limit in (("title", "歌曲标题", 80), ("style", "音乐风格", 1000), ("negative_tags", "排除风格", 1000)):
            value = text(data.get(name, ""), label, limit)
            if value:
                body[name] = value
        if "auto_lyrics" in data:
            body["auto_lyrics"] = flag(data, "auto_lyrics")
        if "duration" in data:
            body["duration"] = integer(data["duration"], "时长", 10, 360)
    elif "duration" in data:
        raise MusicError("INVALID_MUSIC_INPUT", "Suno 目标时长仅适用于自定义模式。")
    for name in ("style_weight", "weirdness_constraint", "audio_weight"):
        if name in data:
            value = data[name]
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 1:
                raise MusicError("INVALID_MUSIC_INPUT", "音乐权重须在 0–1 之间。")
            body[name] = value
    for name, choices in (("vocal_gender", ("Male", "Female")), ("variety", ("off", "normal", "high", "extra", "max")), ("audio_format", ("mp3", "m4a", "wav"))):
        value = data.get(name, "")
        if value:
            if value not in choices:
                raise MusicError("INVALID_MUSIC_INPUT", "音乐参数选项无效。")
            body[name] = value
    return body


def safe_media_url(value):
    if not isinstance(value, str) or len(value) > 8192:
        return ""
    try:
        parsed = urlsplit(value)
        host = parsed.hostname or ""
        if parsed.scheme != "https" or not host or parsed.username or parsed.password or parsed.port not in (None, 443):
            return ""
        if host.lower() == "localhost" or "." not in host or host.lower().endswith((".local", ".internal", ".localhost")):
            return ""
        try:
            if not ipaddress.ip_address(host).is_global:
                return ""
        except ValueError:
            pass
        return value
    except ValueError:
        return ""


def normalize_task(payload, task_id):
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict) or data.get("id") != task_id:
        raise MusicError("MUSIC_BAD_RESPONSE", "音乐任务响应无效，请稍后刷新。", 502)
    raw_status = str(data.get("status", "unknown"))
    status = raw_status if raw_status in {"submitted", "pending", "processing", "completed", "failed", "unknown"} else "unknown"
    progress = data.get("progress", 0)
    progress = max(0, min(100, progress)) if type(progress) in (int, float) and math.isfinite(progress) else 0
    result = data.get("result")
    music = result.get("music", []) if isinstance(result, dict) else []
    if not isinstance(music, list) or len(music) > 64:
        raise MusicError("MUSIC_BAD_RESPONSE", "音乐结果格式无效，请保留任务编号。", 502)
    tracks = []
    seen = set()
    for index, track in enumerate(music, 1):
        if not isinstance(track, dict):
            continue
        url = safe_media_url(track.get("audio_url")) or safe_media_url(track.get("wav_url"))
        if not url or url in seen or track.get("status") in {"error", "failed"}:
            continue
        seen.add(url)
        duration = track.get("duration", track.get("duration_seconds", 0))
        try:
            duration = float(duration)
        except (TypeError, ValueError):
            duration = 0
        tracks.append({
            "audio_index": index, "title": str(track.get("title") or f"音乐 {index}")[:200],
            "lyrics": str(track.get("lyrics") or "")[:20000],
            "tags": str(track.get("display_tags") or track.get("tags") or "")[:1000],
            "duration": duration if math.isfinite(duration) and duration >= 0 else 0,
            "audio_url": url, "wav_url": safe_media_url(track.get("wav_url")),
            "image_url": safe_media_url(track.get("image_url")),
        })
    return {"provider_task_id": task_id, "status": status, "progress": progress, "tracks": tracks,
            "error_code": "MUSIC_TASK_FAILED" if status == "failed" else None}


def custom_endpoints(endpoint, query_template=""):
    if not isinstance(endpoint, str) or not endpoint or len(endpoint) > 2048 or "{" in endpoint or "}" in endpoint:
        raise MusicError("MUSIC_ENDPOINT_INVALID", "请填写完整的音乐生成接口地址。")
    query_template = query_template or endpoint.rstrip("/").rsplit("/", 1)[0] + "/tasks/{task_id}"
    if not isinstance(query_template, str) or query_template.count("{task_id}") != 1 or len(query_template) > 2048:
        raise MusicError("MUSIC_ENDPOINT_INVALID", "任务查询地址须包含一次 {task_id}。")
    for url in (endpoint, query_template.replace("{task_id}", "task_example")):
        try:
            parsed = urlsplit(url)
            if not safe_media_url(url) or parsed.query or parsed.fragment or "{" in url or "}" in url:
                raise ValueError()
        except ValueError as exc:
            raise MusicError("MUSIC_ENDPOINT_INVALID", "音乐接口须为公网 HTTPS 地址，不包含查询参数或凭据。") from exc
    if urlsplit(endpoint).netloc.lower() != urlsplit(query_template).netloc.lower():
        raise MusicError("MUSIC_ENDPOINT_INVALID", "生成和查询接口须使用同一服务商域名。")
    return endpoint, query_template


def pinned_custom_response(method, url, headers, body):
    parsed = urlsplit(url)
    host = parsed.hostname.encode("idna").decode("ascii")
    try:
        addresses = sorted({item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
        if not addresses or any(not ipaddress.ip_address(address).is_global for address in addresses):
            raise MusicError("MUSIC_ENDPOINT_PRIVATE", "音乐接口不能指向本机或私网。")
    except socket.gaierror as exc:
        raise MusicError("MUSIC_DNS_UNAVAILABLE", "暂时无法解析音乐服务域名。", 502) from exc
    # Pin the validated public IP while retaining certificate/SNI hostname.
    # No DNS re-resolution, proxy forwarding, redirects or automatic POST retry.
    pool = urllib3.HTTPSConnectionPool(addresses[0], port=443, assert_hostname=host, server_hostname=host, timeout=urllib3.Timeout(connect=8, read=35), retries=False)
    try:
        raw = pool.urlopen(method, parsed.path or "/", headers={**headers, "Host": host}, body=json.dumps(body).encode() if body is not None else None, preload_content=False, redirect=False, retries=False)
    except urllib3.exceptions.HTTPError as exc:
        pool.close()
        raise requests.ConnectionError("Music provider transport unavailable") from exc
    response = requests.Response()
    response.status_code, response.raw = raw.status, raw
    original_close = response.close
    def close():
        try:
            original_close()
        finally:
            pool.close()
    response.close = close
    return response


def apimart_request(method, path, key, body=None, endpoint=None, auth_type="bearer"):
    headers = {"Content-Type": "application/json"}
    headers["Authorization" if auth_type == "bearer" else "x-api-key"] = f"Bearer {key}" if auth_type == "bearer" else key
    response = None
    try:
        response = pinned_custom_response(method, endpoint, headers, body) if endpoint else requests.request(method, API_BASE + path, headers=headers, json=body, timeout=(8, 35), allow_redirects=False, stream=True)
    except requests.RequestException as exc:
        raise MusicError("MUSIC_SUBMISSION_UNKNOWN" if method == "POST" else "MUSIC_QUERY_UNAVAILABLE", "暂时无法确认提交结果，请保留请求编号并查询，勿重复生成。" if method == "POST" else "音乐任务查询暂时不可用，请稍后刷新。", 503, method == "POST") from exc
    with response:
        chunks, size = [], 0
        try:
            for chunk in response.iter_content(65536):
                size += len(chunk)
                if size > 2 * 1024 * 1024:
                    raise ValueError("large response")
                chunks.append(chunk)
            payload = json.loads(b"".join(chunks))
        except (ValueError, requests.RequestException) as exc:
            raise MusicError("MUSIC_BAD_RESPONSE", "音乐服务响应异常，请保留请求编号。", 502, method == "POST") from exc
        if not 200 <= response.status_code < 300 or not isinstance(payload, dict) or payload.get("code") != 200:
            # Only explicit request rejection is safe to refund. A 5xx, proxy
            # error or malformed success may follow an accepted paid request.
            rejected = response.status_code in {400, 401, 402, 403, 404, 422, 429} and isinstance(payload, dict) and isinstance(payload.get("error"), dict)
            raise MusicError("MUSIC_PROVIDER_REJECTED" if rejected else "MUSIC_PROVIDER_UNAVAILABLE", "音乐服务未受理本次请求，请检查 Key、余额、模型权限和输入。" if rejected else "音乐服务暂时无法确认结果，请保留请求编号。", 502, method == "POST" and not rejected)
        return payload


def submit_music(key, body, endpoint=None, auth_type="bearer"):
    payload = apimart_request("POST", "/generations", key, body, endpoint, auth_type)
    data = payload.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict) or not TASK_ID.fullmatch(str(data[0].get("task_id", ""))):
        raise MusicError("MUSIC_SUBMISSION_UNKNOWN", "音乐服务已响应，但无法确认任务编号，请勿重复生成。", 502, True)
    return data[0]["task_id"]


def query_music(key, task_id, query_template=None, auth_type="bearer"):
    if not TASK_ID.fullmatch(task_id):
        raise MusicError("INVALID_MUSIC_TASK", "音乐任务编号无效。")
    endpoint = query_template.replace("{task_id}", task_id) if query_template else None
    return normalize_task(apimart_request("GET", f"/tasks/{task_id}?language=zh", key, endpoint=endpoint, auth_type=auth_type), task_id)
