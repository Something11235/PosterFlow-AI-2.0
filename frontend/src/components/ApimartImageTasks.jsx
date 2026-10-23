import React, { useCallback, useEffect, useRef, useState } from "react";
import { Loader2, RefreshCw } from "lucide-react";
import { APIMART_IMAGES_BASE, readImageTask } from "../lib/apimartImages";
import { apimartImageModel } from "../lib/provider";

const STATUS = { submitting: "提交中", submitted: "已受理", processing: "生成中", saving: "正在保存原图", completed: "已完成", failed: "未完成", submission_unknown: "提交结果待确认", unknown: "状态待确认" };
export default function ApimartImageTasks({ headers, enabled, onResult, onRefreshAccount }) {
  const [jobs, setJobs] = useState([]), [busy, setBusy] = useState(""), [message, setMessage] = useState("");
  const version = useRef(0), queryController = useRef(null);
  const refresh = useCallback(async signal => {
    if (!enabled) return;
    const requestVersion = version.current;
    const response = await fetch(`${APIMART_IMAGES_BASE}/tasks`, { headers, signal, cache: "no-store" });
    const data = await response.json();
    if (!response.ok || data.error) throw new Error(data.error || "暂时无法获取图片任务。");
    if (!signal?.aborted && requestVersion === version.current) setJobs(data.jobs || []);
  }, [enabled, headers]);
  useEffect(() => {
    const controller = new AbortController();
    version.current += 1;
    setJobs([]); setMessage(""); setBusy("");
    const run = () => refresh(controller.signal).catch(error => { if (!controller.signal.aborted) setMessage(error.message); });
    if (enabled) run();
    window.addEventListener("posterflow:image-tasks", run);
    return () => { version.current += 1; controller.abort(); queryController.current?.abort(); window.removeEventListener("posterflow:image-tasks", run); };
  }, [enabled, refresh]);
  if (!enabled) return null;
  const query = async job => {
    if (busy) return;
    const requestVersion = version.current;
    const controller = new AbortController(); queryController.current = controller;
    setBusy(job.request_id); setMessage("");
    try {
      const data = await readImageTask(job.request_id, headers, controller.signal);
      if (requestVersion !== version.current) return;
      setJobs(previous => previous.map(item => item.request_id === job.request_id ? data.job : item));
      if (data.images?.length) onResult(data.images);
      else setMessage(data.job?.status === "submission_unknown" || data.job?.status === "submitting" ? "尚无确认的上游任务编号，请先联系站主核对，不要重新生成。" : "已查询原任务，可稍后再次查询。不会重新生图。");
      await onRefreshAccount?.();
    } catch (error) { if (requestVersion === version.current) setMessage(error.message); }
    finally { if (requestVersion === version.current) setBusy(""); }
  };
  return <section aria-label="APIMart 图片任务" className="surface mb-4 rounded-lg border border-accent/20 p-4">
    <div className="flex flex-wrap items-center justify-between gap-2"><h3 className="text-sm font-semibold text-text-primary">图片任务 <span className="ml-2 text-xs font-normal text-text-muted">刷新页面后仍可查询</span></h3><button type="button" disabled={!!busy} onClick={() => refresh().catch(error => setMessage(error.message))} className="inline-flex min-h-10 items-center gap-2 text-xs text-accent"><RefreshCw size={14} />刷新列表</button></div>
    <p className="mt-1 text-xs leading-5 text-text-muted">新增模型每张 1 积分，先预留、保存成功后按实际张数结算。结果待确认或保存失败时请查询原任务，避免重复生成。</p>
    {message && <p role="status" className="mt-2 text-xs leading-5 text-gold">{message}</p>}
    {!!jobs.length && <ul className="mt-3 max-h-48 divide-y divide-border-subtle overflow-y-auto">{jobs.slice(0, 10).map(job => <li key={job.request_id} className="flex items-center justify-between gap-3 py-2"><div className="min-w-0"><p className="truncate text-xs text-text-secondary">{apimartImageModel(job.model)?.label || job.model}</p><p className="mt-1 text-xs text-text-muted">{STATUS[job.status] || "状态待确认"} · {job.requested_count} 张</p></div><button type="button" disabled={!!busy} onClick={() => query(job)} className="inline-flex min-h-10 shrink-0 items-center gap-1 rounded-md border border-accent/30 px-3 text-xs text-accent disabled:opacity-50">{busy === job.request_id && <Loader2 size={13} className="animate-spin" />}{job.status === "completed" ? "查看结果" : "查询任务"}</button></li>)}</ul>}
  </section>;
}
