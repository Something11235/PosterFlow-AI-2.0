"""Optional, read-only upstream delivery. Stored originals remain the fallback."""
import json
import math
import re
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import quote, urlsplit

try:
    from backend import apimart_image_provider as provider
except ModuleNotFoundError:
    import apimart_image_provider as provider


def preferred_original(gateway, owner, filename, key, *, now=None):
    if not key or not owner.startswith('user-') or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,180}\.png', filename):
        return None
    now = time.time() if now is None else now
    cutoff = (datetime.fromtimestamp(now, timezone.utc) - timedelta(days=7)).isoformat()
    rows = gateway._request('GET', '/rest/v1/apimart_image_jobs', params={
        'owner_scope': 'eq.' + owner, 'billing_mode': 'eq.platform', 'status': 'eq.completed',
        'image_keys': 'cs.' + json.dumps([filename], separators=(',', ':')),
        'created_at': 'gt.' + cutoff, 'select': 'owner_scope,billing_mode,status,provider_task_id,image_keys', 'order': 'created_at.desc', 'limit': '1',
    }) or []
    if not rows:
        return None
    job = rows[0]
    names = job.get('image_keys')
    task = job.get('provider_task_id')
    if job.get('owner_scope') != owner or job.get('billing_mode') != 'platform' or job.get('status') != 'completed' or not isinstance(names, list) or filename not in names or not isinstance(task, str) or not provider.TASK_ID.fullmatch(task):
        return None
    payload = provider.api_request('GET', '/tasks/' + task + '?language=zh', key, timeout=(2, 3))
    row = payload.get('data')
    if not isinstance(row, dict) or row.get('status') != 'completed' or row.get('id', task) != task:
        return None
    result = row.get('result')
    images = result.get('images') if isinstance(result, dict) else None
    if not isinstance(images, list):
        return None
    links = []
    for image in images:
        value = image.get('url') if isinstance(image, dict) else image
        expiry = image.get('expires_at') if isinstance(image, dict) else None
        for url in value if isinstance(value, list) else [value]:
            if isinstance(url, str):
                links.append((url, expiry))
    if len(links) != len(names):
        return None
    url, expiry = links[names.index(filename)]
    if not isinstance(url, str) or len(url) > 4096 or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in url):
        return None
    if key in url or quote(key, safe='') in url:
        return None
    try:
        parsed = urlsplit(url)
        host = parsed.hostname or ''
        safe = parsed.scheme == 'https' and not parsed.username and not parsed.password and parsed.port in (None, 443) and not parsed.fragment and parsed.path.strip('/') and (host == 'apimart.ai' or host.endswith('.apimart.ai') or host == 'getapib.org' or host.endswith('.getapib.org'))
    except ValueError:
        return None
    if not safe:
        return None
    try:
        if isinstance(expiry, bool):
            return None
        expires = float(expiry)
        if not math.isfinite(expires) or expires <= now + 30:
            return None
    except (ValueError, TypeError, OverflowError):
        return None
    return {'url': url, 'expires_in': min(300, int(expires - now - 30)), 'variant': 'original', 'source': 'upstream'}
