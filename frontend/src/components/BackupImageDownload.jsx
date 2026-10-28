import React, { useEffect, useRef, useState } from "react";
import { ExternalLink, Loader2, RefreshCw } from "lucide-react";
import { fetchImageDownloadUrl } from "../lib/client";

export default function BackupImageDownload({ filename, authenticated = false, authHeaders }) {
  const [url, setUrl] = useState("");
  const [preparing, setPreparing] = useState(false);
  const [error, setError] = useState("");
  const requestRef = useRef(0);

  useEffect(() => {
    if (!url) return undefined;
    const timer = window.setTimeout(() => setUrl(""), 5 * 60 * 1000);
    return () => window.clearTimeout(timer);
  }, [url]);

  useEffect(() => {
    requestRef.current += 1;
    setUrl("");
    setPreparing(false);
    setError("");
    return () => { requestRef.current += 1; };
  }, [filename, authenticated, authHeaders]);

  async function prepareDownload() {
    if (preparing) return;
    const request = ++requestRef.current;
    setPreparing(true);
    setError("");
    try {
      const downloadUrl = await fetchImageDownloadUrl(filename, { authenticated, headers: authHeaders });
      if (request === requestRef.current) setUrl(downloadUrl);
    } catch {
      if (request === requestRef.current) setError("备用下载地址获取失败，请重试。");
    } finally {
      if (request === requestRef.current) setPreparing(false);
    }
  }

  const style = "inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-md border border-accent/40 bg-accent/10 px-3 text-sm text-accent transition hover:bg-accent/20 disabled:cursor-wait disabled:opacity-65";
  return <div className="min-w-0">
    {url ? <a href={url} target="_blank" rel="noopener noreferrer" referrerPolicy="no-referrer" download={filename} className={style}>
      <ExternalLink size={16} className="shrink-0" />备用下载：打开原图
    </a> : <button type="button" onClick={prepareDownload} disabled={preparing} aria-busy={preparing} className={style}>
      {preparing ? <Loader2 size={16} className="shrink-0 animate-spin" /> : <ExternalLink size={16} className="shrink-0" />}
      {preparing ? "正在准备备用下载…" : "备用下载"}
    </button>}
    {url && <button type="button" onClick={prepareDownload} disabled={preparing} className="mt-1 inline-flex min-h-8 items-center gap-1 text-xs text-text-muted hover:text-accent"><RefreshCw size={12}/>{preparing ? "正在更新地址…" : "链接失效？重新获取"}</button>}
    {error && <p role="alert" className="mt-2 text-xs leading-5 text-error">{error}</p>}
  </div>;
}
