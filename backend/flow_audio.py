"""Flow audio import -> cover, with durable one-time transition claims."""
import math
import re

try:
    from backend.music_provider import MusicError, FLOW_VERSIONS, TASK_ID, apimart_request, text
except ModuleNotFoundError:
    from music_provider import MusicError, FLOW_VERSIONS, TASK_ID, apimart_request, text


def flow_cover_request(data, count):
    allowed = {"model", "version", "prompt", "strength", "title"}
    if count != 1 or not isinstance(data, dict) or set(data) - allowed or data.get("model") != "flowmusic":
        raise MusicError("INVALID_MUSIC_INPUT", "Flow 音频改编需要 1 段音频，请使用该模式支持的参数。")
    version = data.get("version", "lyria-3-pro")
    if version not in FLOW_VERSIONS:
        raise MusicError("INVALID_MUSIC_VERSION", "请选择可用的 Flow Music 版本。")
    instruction = text(data.get("prompt", ""), "改编描述", 3000)
    if not instruction:
        raise MusicError("INVALID_MUSIC_INPUT", "请填写希望改编成的风格或效果。")
    strength = data.get("strength", .5)
    if type(strength) not in (int, float) or not math.isfinite(strength) or not 0 <= strength <= 1:
        raise MusicError("INVALID_MUSIC_INPUT", "改编强度须为 0–1 之间的数字。")
    body = {"model": "flowmusic", "instruction": instruction, "strength": strength}
    if version == "lyria-3.5":
        body["version"] = version
    title = text(data.get("title", ""), "歌曲标题", 200)
    if title:
        body["title"] = title
    return body


def submit_flow(key, path, body, auth_type="bearer"):
    result = apimart_request("POST", "/generations/" + path, key, body, auth_type=auth_type)
    data = result.get("data")
    if not isinstance(data, list) or len(data) != 1 or not isinstance(data[0], dict) or not TASK_ID.fullmatch(str(data[0].get("task_id", ""))):
        raise MusicError("MUSIC_SUBMISSION_UNKNOWN", "音乐服务已响应，但无法确认任务编号，请勿重复提交。", 502, True)
    return data[0]["task_id"]


def reconcile_flow_import(store, owner, job, result, key, auth_type="bearer"):
    """Called only while importing; an atomic claim permits at most one cover POST."""
    args = {"p_owner": owner, "p_request_id": job["request_id"], "p_expected_task": job["provider_task_id"]}
    status = result["status"]
    if status != "completed":
        event = "import_failed" if status == "failed" else "import_progress"
        updated = store.rpc("advance_flow_cover_job", {**args, "p_event": event, "p_error_code": result.get("error_code")})
        return {"job": updated["job"], "tracks": [], "progress": round(result["progress"] * .3), "credit_balance": updated.get("balance")}
    clips = result.get("clip_ids", []) or [track.get("clip_id") for track in result["tracks"]]
    clip = next((value for value in clips if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]{8,160}", value)), None)
    if not clip:
        return {"job": job, "tracks": [], "warning": "音频导入已完成，但暂未取得改编所需的素材编号，请刷新原任务。"}
    claimed = store.rpc("advance_flow_cover_job", {**args, "p_event": "claim_cover"})
    if not claimed.get("claimed"):
        return {"job": claimed["job"], "tracks": [], "credit_balance": claimed.get("balance")}
    # Claim commits before POST. A crash or uncertain response must not replay it.
    try:
        task_id = submit_flow(key, "coverFlowMusic", {**claimed["parameters"], "clip_id": clip}, auth_type)
    except MusicError as error:
        updated = store.rpc("advance_flow_cover_job", {**args, "p_event": "cover_unknown" if error.uncertain else "cover_rejected", "p_error_code": error.reason_code or error.code})
        return {"job": updated["job"], "tracks": [], "warning": error.message, "credit_balance": updated.get("balance")}
    updated = store.rpc("advance_flow_cover_job", {**args, "p_event": "cover_submitted", "p_task_id": task_id})
    return {"job": updated["job"], "tracks": [], "progress": 30}
