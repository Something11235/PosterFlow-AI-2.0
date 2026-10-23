"""Durable, owner-scoped music requests, separate from the image ledger."""
import hashlib
import hmac
import json
import os
import uuid

from flask import Blueprint, jsonify, request

try:
    from backend.music_provider import MusicError, build_music_request, custom_endpoints, query_music, submit_music
    from backend.supabase_service import SupabaseError, SupabaseGateway, is_supabase_configured
except ModuleNotFoundError:
    from music_provider import MusicError, build_music_request, custom_endpoints, query_music, submit_music
    from supabase_service import SupabaseError, SupabaseGateway, is_supabase_configured

SONG_CREDITS = 2
PUBLIC_JOB_FIELDS = ("request_id", "billing_mode", "model", "version", "status", "billing_status", "provider_task_id", "generated_count", "reserved_credits", "charged_credits", "error_code", "created_at")


def public_job(job):
    return {key: job.get(key) for key in PUBLIC_JOB_FIELDS}


class MusicStore:
    def __init__(self):
        self.gateway = SupabaseGateway()

    def rpc(self, name, body):
        result = self.gateway.rpc(name, body)
        if not isinstance(result, dict) or not result.get("ok"):
            code = result.get("code", "MUSIC_DATABASE_UNAVAILABLE") if isinstance(result, dict) else "MUSIC_DATABASE_UNAVAILABLE"
            messages = {"INSUFFICIENT_CREDITS": "积分不足，每首音乐需要 2 积分。", "EMAIL_UNVERIFIED": "请先完成邮箱验证。", "ACCOUNT_FROZEN": "账户当前不可用。", "MUSIC_REQUEST_CONFLICT": "该请求编号对应的参数不同，请保留原任务。", "MUSIC_NOT_FOUND": "未找到本人的音乐任务。"}
            raise MusicError(code, messages.get(code, "音乐任务处理暂时不可用。"), 404 if code == "MUSIC_NOT_FOUND" else 409)
        return result

    def begin(self, owner, user_id, request_id, mode, body, version):
        fingerprint = hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
        return self.rpc("begin_music_job", {"p_owner": owner, "p_user_id": user_id, "p_request_id": request_id, "p_mode": mode, "p_model": body["model"], "p_version": version, "p_fingerprint": fingerprint})

    def apply(self, owner, request_id, event, task_id=None, count=0, error_code=None):
        return self.rpc("apply_music_job", {"p_owner": owner, "p_request_id": request_id, "p_event": event, "p_task_id": task_id, "p_count": count, "p_error_code": error_code})

    def jobs(self, owner):
        return self.gateway._request("GET", "/rest/v1/music_jobs", params={"owner_scope": f"eq.{owner}", "select": ",".join(PUBLIC_JOB_FIELDS), "order": "created_at.desc,request_id.desc", "limit": "50"}) or []

    def get(self, owner, request_id):
        rows = self.gateway._request("GET", "/rest/v1/music_jobs", params={"owner_scope": f"eq.{owner}", "request_id": f"eq.{request_id}", "select": ",".join(PUBLIC_JOB_FIELDS), "limit": "1"})
        if not rows:
            raise MusicError("MUSIC_NOT_FOUND", "未找到本人的音乐任务。", 404)
        return rows[0]


def create_music_blueprint(require_user, optional_user, rate_limit, allowed_origins):
    bp = Blueprint("music", __name__, url_prefix="/api/music")

    @bp.after_request
    def private_response(response):
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    @bp.errorhandler(MusicError)
    def music_error(error):
        return jsonify(error=error.message, code=error.code, submission_unknown=error.uncertain), error.status

    @bp.errorhandler(SupabaseError)
    def database_error(_error):
        return jsonify(error="音乐任务数据库尚未就绪，请检查开发配置和音乐迁移。", code="MUSIC_DATABASE_UNAVAILABLE"), 503

    @bp.errorhandler(Exception)
    def other_error(error):
        if hasattr(error, "code") and hasattr(error, "status") and hasattr(error, "message"):
            return jsonify(error=error.message, code=error.code), error.status
        return jsonify(error="音乐请求暂未完成，请保留原请求编号后查询。", code="MUSIC_SERVICE_UNAVAILABLE"), 503

    def context():
        mode = request.headers.get("X-Billing-Mode", "platform")
        if mode not in {"platform", "own_key"}:
            raise MusicError("INVALID_BILLING_MODE", "请选择平台积分或自带 Key。")
        if mode == "platform":
            user = require_user()
            key = os.getenv("APIMART_MUSIC_API_KEY", "").strip()
            if not key:
                raise MusicError("MUSIC_NOT_CONFIGURED", "平台音乐服务尚未配置，可选择自带 APIMart Key。", 503)
            return mode, key, f"user-{user.id}", user.id, None, None, "bearer"
        key = request.headers.get("X-Music-Api-Key", "").strip()
        if not key or len(key) > 4096 or any(ord(char) < 33 or ord(char) > 126 for char in key):
            raise MusicError("MUSIC_KEY_REQUIRED", "请填写有效的 API Key。")
        endpoint, query_template = custom_endpoints(request.headers.get("X-Music-Endpoint", "").strip(), request.headers.get("X-Music-Query-Template", "").strip())
        auth_type = request.headers.get("X-Music-Auth-Type", "bearer")
        if auth_type not in {"bearer", "x-api-key"}:
            raise MusicError("MUSIC_AUTH_TYPE_INVALID", "请选择有效的鉴权方式。")
        user = optional_user()
        identity = f"user-{user.id}" if user else "guest"
        owner = identity + "-" + hashlib.sha256(json.dumps([key, endpoint, query_template, auth_type]).encode()).hexdigest()
        return mode, key, owner, user.id if user else None, endpoint, query_template, auth_type

    def normalize_id(value):
        try:
            return str(uuid.UUID(value))
        except (ValueError, TypeError, AttributeError) as exc:
            raise MusicError("INVALID_MUSIC_REQUEST", "音乐请求编号无效。") from exc

    def check_origin():
        origin = request.headers.get("Origin")
        if origin and origin.rstrip("/") not in {request.host_url.rstrip("/"), *allowed_origins}:
            raise MusicError("MUSIC_ORIGIN_FORBIDDEN", "请求来源不受支持。", 403)

    def reconcile(store, owner, job, key, query_template=None, auth_type="bearer"):
        if not job.get("provider_task_id"):
            return {"success": True, "job": public_job(job), "tracks": []}
        result = query_music(key, job["provider_task_id"], query_template, auth_type)
        status = result["status"]
        if status == "completed" and not result["tracks"]:
            # Do not turn missing/expired files into a refund or a new paid job.
            return {"success": True, "job": public_job(job), "tracks": [], "warning": "任务已完成，但暂未取得可播放结果，请保留任务编号后刷新。"}
        event = status if status in {"completed", "failed", "unknown"} else "processing"
        applied = store.apply(owner, job["request_id"], event, count=len(result["tracks"]), error_code=result["error_code"])
        updated = applied["job"]
        tracks = result["tracks"] if status == "completed" and updated["billing_status"] in {"settled", "not_applicable"} else []
        return {"success": True, "job": public_job(updated), "tracks": tracks, "progress": result["progress"], "credit_balance": applied.get("balance")}

    @bp.get("/config")
    def config():
        return jsonify(success=True, provider="APIMart", platform_configured=bool(os.getenv("APIMART_MUSIC_API_KEY", "").strip()) and is_supabase_configured(), database_configured=is_supabase_configured(), credits_per_song=SONG_CREDITS)

    @bp.get("/tasks")
    def tasks():
        _mode, _key, owner, _user_id, _endpoint, _query, _auth = context()
        return jsonify(success=True, jobs=[public_job(job) for job in MusicStore().jobs(owner)])

    @bp.post("/generations")
    def generate():
        check_origin()
        raw = request.get_json(silent=True)
        if not isinstance(raw, dict) or set(raw) - {"request_id", "parameters"}:
            raise MusicError("INVALID_MUSIC_INPUT", "音乐请求格式无效。")
        request_id = normalize_id(raw.get("request_id"))
        mode, key, owner, user_id, endpoint, query_template, auth_type = context()
        body = build_music_request(raw.get("parameters"), allow_custom=mode == "own_key")
        rate_limit("music-submit", owner, 8, 60)
        store = MusicStore()
        version = raw["parameters"].get("version", "v6" if body["model"] == "suno" else "lyria-3-pro" if body["model"] == "flowmusic" else "")
        reservation = store.begin(owner, user_id, request_id, mode, body, version)
        if reservation.get("existing"):
            return jsonify(success=True, job=public_job(reservation["job"]), tracks=[], credit_balance=reservation.get("balance"), idempotent=True)
        try:
            task_id = submit_music(key, body, endpoint, auth_type) if mode == "own_key" else submit_music(key, body)
        except MusicError as error:
            store.apply(owner, request_id, "submission_unknown" if error.uncertain else "rejected", error_code=error.code)
            raise
        # Save failure is deliberately not caught/refunded: APIMart accepted it.
        applied = store.apply(owner, request_id, "submitted", task_id=task_id)
        return jsonify(success=True, job=public_job(applied["job"]), tracks=[], credit_balance=applied.get("balance")), 202

    @bp.get("/tasks/<request_id>")
    def task(request_id):
        _mode, key, owner, _user_id, _endpoint, query_template, auth_type = context()
        rate_limit("music-query", owner, 120, 60)
        store = MusicStore()
        return jsonify(reconcile(store, owner, store.get(owner, normalize_id(request_id)), key, query_template, auth_type))

    @bp.post("/reconcile")
    def scheduled_reconcile():
        secret = os.getenv("MUSIC_RECONCILE_SECRET", "")
        if not secret or not hmac.compare_digest(request.headers.get("Authorization", ""), "Bearer " + secret):
            raise MusicError("AUTH_REQUIRED", "需要对账服务凭证。", 401)
        key = os.getenv("APIMART_MUSIC_API_KEY", "").strip()
        if not key:
            raise MusicError("MUSIC_NOT_CONFIGURED", "平台音乐服务尚未配置。", 503)
        store = MusicStore()
        jobs = store.gateway._request("GET", "/rest/v1/music_jobs", params={"billing_mode": "eq.platform", "billing_status": "in.(reserved,awaiting_balance)", "provider_task_id": "not.is.null", "select": "owner_scope," + ",".join(PUBLIC_JOB_FIELDS), "order": "last_checked_at.asc.nullsfirst", "limit": "20"}) or []
        processed = 0
        for job in jobs:
            try:
                reconcile(store, job["owner_scope"], job, key)
                processed += 1
            except (MusicError, SupabaseError):
                continue
        return jsonify(success=True, checked=processed)

    return bp
