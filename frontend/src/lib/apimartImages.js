import { apimartImageModel } from "./provider.js";

export const APIMART_IMAGES_BASE = "/api/apimart-images";
export function requestImageModel(body, headers) {
  const values = new Headers(headers);
  return values.get("X-Billing-Mode") === "platform" ? body.platform_model : values.get("X-Provider-Model");
}
const sleep = delay => new Promise(resolve => setTimeout(resolve, delay));
const responseJson = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function boundedFetch(url, init, milliseconds) {
  const controller = new AbortController();
  const abort = () => controller.abort();
  if (init.signal?.aborted) abort();
  init.signal?.addEventListener("abort", abort, { once: true });
  const timer = setTimeout(abort, milliseconds);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    // Include the entire JSON body in the deadline, not only response headers.
    const body = await response.text();
    return new Response(body, { status: response.status, headers: response.headers });
  } finally {
    clearTimeout(timer);
    init.signal?.removeEventListener("abort", abort);
  }
}

export async function readImageTask(requestId, headers, signal) {
  const response = await boundedFetch(`${APIMART_IMAGES_BASE}/tasks/${encodeURIComponent(requestId)}`, { headers, signal, cache: "no-store" }, 230000);
  const data = await response.json();
  if (!response.ok || data.error) throw Object.assign(new Error(data.detail || data.error || "图片任务暂时无法查询。"), { code: data.code });
  return data;
}

// Legacy requests remain byte-for-byte on their existing routes. New model
// requests submit once, then only GET the durable task; never retry a paid POST.
export async function imageGenerationFetch(endpoint, init, { pollInterval = 4000, maxWait = 240000 } = {}) {
  const body = JSON.parse(init.body);
  if (!apimartImageModel(requestImageModel(body, init.headers))) return fetch(endpoint, init);
  let response;
  try {
    response = await boundedFetch(`${APIMART_IMAGES_BASE}/generations`, init, 90000);
  } catch {
    return responseJson({ error: "提交连接未完成，请在图片任务窗口查询原任务，不要重复生成。", code: "IMAGE_SUBMISSION_UNKNOWN" }, 503);
  } finally {
    window.dispatchEvent(new Event("posterflow:image-tasks"));
  }
  if (!response.ok) return response;
  let data = await response.json();
  const start = Date.now();
  while (data.job && !["completed", "failed", "submission_unknown", "submitting"].includes(data.job.status)) {
    if (Date.now() - start >= maxWait) return responseJson({ error: "任务仍在处理，可在图片任务窗口查询；请勿重复生成。", code: "IMAGE_TASK_PENDING" }, 202);
    await sleep(pollInterval);
    try {
      data = await readImageTask(body.request_id, init.headers);
    } catch (error) {
      return responseJson({ error: error.message + " 可在图片任务窗口继续查询，请勿重复生成。", code: error.code || "IMAGE_TASK_QUERY_FAILED" }, 503);
    }
  }
  window.dispatchEvent(new Event("posterflow:image-tasks"));
  if (data.job?.status !== "completed") return responseJson({ ...data, error: data.job?.status === "failed" ? "图片服务未完成本次任务，已按实际结果退回预留积分。" : "提交结果待确认，请保留原任务并核对服务商记录，不要重复生成。", code: data.job?.status === "failed" ? "APIMART_TASK_FAILED" : "IMAGE_SUBMISSION_UNKNOWN" }, 409);
  return responseJson({ ...data, prompt: body.prompt });
}
