import React, { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { ChevronDown, Download, Image, Loader2, RefreshCw, X } from "lucide-react";
import { fetchImageBlob } from "../lib/client";
import { saveBrowserFile } from "../lib/browserSave";
import BackupImageDownload from "./BackupImageDownload";

function thumbnailUrl(preview) {
  if (preview?.variant !== "thumbnail" || typeof preview.url !== "string" || preview.url.length > 4096) return "";
  try {
    const url = new URL(preview.url, window.location.origin);
    if (url.username || url.password) return "";
    if (url.origin === window.location.origin) return url.pathname.startsWith("/api/images/_thumb_") ? url.href : "";
    return url.protocol === "https:" ? url.href : "";
  } catch { return ""; }
}

export default function HistoryImagePreviews({ entryId, count, expiresAt, authHeaders }) {
  const [expanded, setExpanded] = useState(false);
  const [previews, setPreviews] = useState([]);
  const [cachedUntil, setCachedUntil] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState(null);
  const [downloading, setDownloading] = useState("");
  const [downloadError, setDownloadError] = useState("");
  const request = useRef(null);
  const scope = useRef(0);

  useEffect(() => {
    scope.current += 1;
    setExpanded(false); setPreviews([]); setCachedUntil(0); setLoading(false); setError("");
    setSelected(null); setDownloading(""); setDownloadError("");
    return () => { scope.current += 1; request.current?.abort(); request.current = null; };
  }, [entryId, authHeaders]);

  async function load() {
    if (request.current) return;
    if (Date.parse(expiresAt) <= Date.now()) { setPreviews([]); setError("预览已过期，提示词仍可使用。"); return; }
    const controller = new AbortController(); request.current = controller;
    let timedOut = false;
    const timeout = window.setTimeout(() => { timedOut = true; controller.abort(); }, 20000);
    setLoading(true); setError(""); setPreviews([]);
    try {
      const response = await fetch(`/api/history/${encodeURIComponent(entryId)}/previews`, { headers: authHeaders, credentials: "include", signal: controller.signal, cache: "no-store" });
      const data = await response.json();
      if (controller.signal.aborted) return;
      if (!response.ok) throw new Error(data.error || "预览图暂时无法读取，请稍后重试。");
      const urls = (Array.isArray(data.previews) ? data.previews : []).slice(0, 4).map(item => {
        const url = thumbnailUrl(item), filename = item?.filename;
        return url && typeof filename === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}\.png$/.test(filename) && !filename.startsWith("_thumb_") ? { url, filename } : null;
      }).filter(Boolean);
      setPreviews(urls);
      setCachedUntil(Math.min(Date.parse(expiresAt), Date.now() + Math.min(300, Math.max(1, Number(data.url_ttl_seconds) || 300)) * 1000));
      if (!urls.length) setError("暂无可用缩略图，可能已清理或该图片没有预览；提示词仍可使用。");
    } catch (reason) {
      if (timedOut && request.current === controller) setError("预览图连接超时，请稍后重试。提示词仍可使用。");
      else if (!controller.signal.aborted) setError(reason.message || "预览图暂时无法读取，请稍后重试。");
    } finally {
      window.clearTimeout(timeout);
      if (request.current === controller) { request.current = null; setLoading(false); }
    }
  }

  function toggle() {
    if (expanded) { setExpanded(false); return; }
    setExpanded(true);
    if (!previews.length || cachedUntil <= Date.now()) load();
  }

  async function download(filename) {
    if (downloading) return;
    const version = scope.current;
    setDownloading(filename); setDownloadError("");
    try {
      await saveBrowserFile(filename, async () => {
        const blob = await fetchImageBlob(filename, { authenticated: true, headers: authHeaders });
        if (version !== scope.current) throw new Error("账户或历史记录已切换，请重新下载。");
        return blob;
      });
    } catch (reason) {
      if (version === scope.current) setDownloadError(reason.message || "原图下载失败，请重试或使用备用下载。");
    } finally { if (version === scope.current) setDownloading(""); }
  }

  return <section className="mt-3 rounded-md border border-border-subtle bg-bg-primary/40 p-3" aria-label="历史图片预览">
    <button type="button" onClick={toggle} aria-expanded={expanded} className="flex min-h-10 w-full items-center justify-between gap-2 text-left text-xs text-accent">
      <span className="inline-flex items-center gap-2"><Image size={15} />{expanded ? "收起预览图" : `查看预览图（${count}）`}</span><ChevronDown size={15} className={expanded ? "rotate-180" : ""} />
    </button>
    {expanded && <div className="mt-2">
      <p className="mb-3 text-xs leading-5 text-text-muted">列表使用缩略图，点开后才加载原图；下载直接使用原图，可重复下载。预览保留 12 小时。</p>
      {loading && <p role="status" className="flex items-center gap-2 py-3 text-xs text-text-muted"><Loader2 size={15} className="animate-spin" />正在加载预览图…</p>}
      {error && <div role="status" className="mb-3 text-xs leading-6 text-text-muted">{error}<button type="button" disabled={loading} onClick={load} className="ml-2 inline-flex min-h-9 items-center gap-1 text-accent disabled:opacity-50"><RefreshCw size={13} />重试预览</button></div>}
      {downloadError && <p role="alert" className="mb-2 text-xs leading-5 text-error">{downloadError}</p>}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{previews.map((item, index) => <article key={item.filename} className="min-w-0 space-y-2">
        <button type="button" aria-label={`查看历史原图 ${index + 1}`} onClick={() => { setDownloadError(""); setSelected(item); }} className="block w-full rounded-md border border-border-subtle bg-bg-primary focus-visible:outline-2 focus-visible:outline-accent">
          <img src={item.url} alt={`历史图片预览 ${index + 1}`} loading="lazy" decoding="async" crossOrigin="anonymous" referrerPolicy="no-referrer" className="aspect-square w-full rounded-md object-contain" onLoad={event => { event.currentTarget.hidden = false; }} onError={event => { event.currentTarget.hidden = true; setError("缩略图暂时无法读取，请重试预览。不会自动加载原图。"); }} />
        </button>
        <button type="button" disabled={Boolean(downloading)} onClick={() => download(item.filename)} className="inline-flex min-h-10 w-full items-center justify-center gap-1 rounded-md border border-border-default px-2 text-xs text-accent disabled:opacity-50">{downloading === item.filename ? <Loader2 size={13} className="animate-spin"/> : <Download size={13}/>}下载原图</button>
      </article>)}</div>
    </div>}
    {selected && createPortal(<HistoryOriginalPreview filename={selected.filename} authHeaders={authHeaders} onClose={() => setSelected(null)} onDownload={() => download(selected.filename)} downloading={Boolean(downloading)} downloadError={downloadError}/>, document.body)}
  </section>;
}

function HistoryOriginalPreview({ filename, authHeaders, onClose, onDownload, downloading, downloadError }) {
  const [url, setUrl] = useState(""), [error, setError] = useState(""), [attempt, setAttempt] = useState(0);
  const close = useRef(onClose), closeButton = useRef(null); close.current = onClose;
  useEffect(() => {
    let alive = true, objectUrl = "";
    setUrl(""); setError("");
    fetchImageBlob(filename, { authenticated: true, headers: authHeaders, forceRefresh: attempt > 0 }).then(blob => {
      if (alive) { objectUrl = URL.createObjectURL(blob); setUrl(objectUrl); }
    }).catch(reason => { if (alive) setError(reason.message || "原图暂时无法读取，请重试。"); });
    return () => { alive = false; if (objectUrl) URL.revokeObjectURL(objectUrl); };
  }, [filename, authHeaders, attempt]);
  useEffect(() => {
    const focused = document.activeElement;
    closeButton.current?.focus();
    const escape = event => { if (event.key === "Escape") { event.preventDefault(); event.stopImmediatePropagation(); close.current(); } };
    document.addEventListener("keydown", escape, true);
    return () => { document.removeEventListener("keydown", escape, true); focused?.focus?.(); };
  }, []);
  return <div role="dialog" aria-modal="true" aria-label="历史原图预览" className="fixed inset-0 z-[160] flex flex-col bg-black/90 p-3 backdrop-blur-sm sm:p-5">
    <header className="flex shrink-0 items-center justify-between gap-3 py-2"><div className="min-w-0"><h2 className="font-semibold text-white">历史原图预览</h2><p className="truncate text-xs text-text-muted">{filename}</p></div><button type="button" ref={closeButton} onClick={onClose} aria-label="关闭历史原图预览" className="flex min-h-11 min-w-11 items-center justify-center rounded-md text-white hover:bg-white/10"><X size={20}/></button></header>
    <div className="flex min-h-0 flex-1 items-center justify-center overflow-auto rounded-lg border border-white/10 bg-bg-primary/60 p-3">
      {!url && !error && <p role="status" className="flex items-center gap-2 text-sm text-text-muted"><Loader2 size={17} className="animate-spin"/>正在加载原图…</p>}
      {error && <div className="space-y-3 text-center"><p role="alert" className="text-sm text-text-secondary">{error}</p><button type="button" onClick={() => setAttempt(value => value + 1)} className="min-h-11 rounded-md border border-accent/40 px-4 text-sm text-accent">重试原图</button></div>}
      {url && !error && <img src={url} alt="历史图片原图" className="max-h-full max-w-full object-contain" onError={() => setError("原图无法解码，请重试加载。")}/>}
    </div>
    <footer className="shrink-0 space-y-2 pt-3"><p className="text-center text-xs leading-5 text-text-muted">若网络不佳或下载失败，请点击“备用下载”。保留期内可重复下载，不重新生成、不扣积分。若迅雷提示资源无效，请关闭下载接管后使用浏览器保存。</p>{downloadError && <p role="alert" className="text-center text-xs text-error">{downloadError}</p>}<div className="mx-auto grid max-w-xl grid-cols-2 gap-2"><button type="button" disabled={downloading} onClick={onDownload} className="inline-flex min-h-11 items-center justify-center gap-2 rounded-md bg-accent px-3 text-sm text-white disabled:opacity-50">{downloading ? <Loader2 size={16} className="animate-spin"/> : <Download size={16}/>}下载原图</button><BackupImageDownload filename={filename} authenticated authHeaders={authHeaders}/></div></footer>
  </div>;
}
