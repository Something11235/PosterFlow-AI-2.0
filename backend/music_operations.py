"""Documented Suno audio operations; request identity never contains signed URLs."""
import hashlib
import json

try:
    from backend.music_provider import MusicError, SUNO_VERSIONS, text, flag, integer, API_BASE, apimart_request, TASK_ID
except ModuleNotFoundError:
    from music_provider import MusicError, SUNO_VERSIONS, text, flag, integer, API_BASE, apimart_request, TASK_ID

OPERATIONS = {"inspo": ("参考音频创作", "/generations/inspo", 4), "upload_cover": ("音频改编", "/generations/uploadCover", 1)}


def operation_request(operation, data, count):
    if operation not in OPERATIONS or not isinstance(data, dict) or not 1 <= count <= OPERATIONS[operation][2]:
        raise MusicError("INVALID_MUSIC_OPERATION", "参考创作需要 1–4 段音频，音频改编需要 1 段音频。")
    common = {"model", "version", "prompt", "title", "style", "negative_tags", "vocal_gender", "style_weight", "weirdness_constraint", "audio_weight", "auto_lyrics", "variety", "audio_format"}
    if data.get("model", "suno") != "suno" or set(data) - (common | ({"custom", "instrumental", "duration"} if operation == "upload_cover" else set())):
        raise MusicError("INVALID_MUSIC_INPUT", "此音频创作方式不支持所选参数。")
    version = data.get("version", "v6")
    if version not in SUNO_VERSIONS:
        raise MusicError("INVALID_MUSIC_VERSION", "请选择可用的 Suno 版本。")
    body = {"model": "suno", "version": version}
    custom = operation == "inspo" or flag(data, "custom")
    prompt = text(data.get("prompt", ""), "歌词或创作描述", 5000 if custom else 3000)
    if operation == "upload_cover":
        body.update(custom=custom, instrumental=flag(data, "instrumental"))
        if not custom and not prompt:
            raise MusicError("INVALID_MUSIC_INPUT", "请描述希望改编成的风格或效果。")
        if custom and not body["instrumental"] and not prompt:
            raise MusicError("INVALID_MUSIC_INPUT", "请填写改编歌词，或开启纯音乐。")
    if prompt:
        body["prompt" if custom else "gpt_description"] = prompt
    if custom:
        for source, target, limit in (("title", "title", 80), ("style", "tags", 1000), ("negative_tags", "negative_tags", 1000)):
            value = text(data.get(source, ""), source, limit)
            if value:
                body[target] = value
        for source, target in (("style_weight", "style_weight"), ("weirdness_constraint", "weirdness"), ("audio_weight", "audio_weight")):
            if source in data:
                value = data[source]
                if type(value) not in (int, float) or not 0 <= value <= 1:
                    raise MusicError("INVALID_MUSIC_INPUT", "音乐权重须为 0–1 之间的数字。")
                body[target] = value
        if "auto_lyrics" in data:
            body["auto_lyrics"] = flag(data, "auto_lyrics")
        if data.get("vocal_gender"):
            if data["vocal_gender"] not in {"Male", "Female"}:
                raise MusicError("INVALID_MUSIC_INPUT", "人声选项无效。")
            body["vocal_gender"] = data["vocal_gender"]
        if operation == "upload_cover" and "duration" in data:
            body["duration_s"] = integer(data["duration"], "目标时长", 10, 360)
    elif any(key in data for key in {"title", "style", "negative_tags", "style_weight", "weirdness_constraint", "audio_weight", "auto_lyrics", "vocal_gender", "duration"}):
        raise MusicError("INVALID_MUSIC_INPUT", "这些参数仅适用于自定义歌词改编。")
    for key, choices in (("variety", {"off", "normal", "high", "extra", "max"}), ("audio_format", {"mp3", "m4a", "wav"})):
        if data.get(key):
            if data[key] not in choices:
                raise MusicError("INVALID_MUSIC_INPUT", "音乐创作选项无效。")
            body[key] = data[key]
    return body


def operation_fingerprint(operation, body, references):
    identity = {"operation": operation, "body": body, "references": [{"id": r["id"], "sha256": r["sha256"]} for r in references]}
    return hashlib.sha256(json.dumps(identity, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def submit_operation(key, operation, body, urls, endpoint=None, auth_type="bearer"):
    payload = {**body, **({"audio_urls": urls} if operation == "inspo" else {"audio_url": urls[0]})}
    path = OPERATIONS[operation][1]
    # A user-supplied general provider is not evidence it implements Suno tools.
    if endpoint and endpoint.rstrip("/") != API_BASE + "/generations":
        raise MusicError("MUSIC_OPERATION_UNSUPPORTED", "当前音乐服务未配置音频创作功能。")
    result = apimart_request("POST", path, key, payload, auth_type=auth_type)
    data = result.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict) or not TASK_ID.fullmatch(str(data[0].get("task_id", ""))):
        raise MusicError("MUSIC_SUBMISSION_UNKNOWN", "音乐服务已响应，但无法确认任务编号，请勿重复生成。", 502, True)
    return data[0]["task_id"]
