import React, { useState } from "react";
import { Check, ImagePlus, Loader2 } from "lucide-react";

const labels = { running: "生成中", completed: "已完成", failed: "未完成", pending: "待查询" };
export default function ImageTaskQueue({ tasks, onView, onQuery }) {
  const [querying, setQuerying] = useState("");
  if (!tasks.length) return null;
  const active = tasks.filter(task => task.active).length;
  return <details className="surface shrink-0 rounded-lg border border-accent/20" aria-label="本次生图任务">
    <summary className="flex min-h-11 cursor-pointer flex-wrap items-center gap-2 px-4 py-2 text-sm text-text-secondary">
      <ImagePlus size={16} className="text-accent" />本次生图任务
      <span className="text-xs text-text-muted">{active ? `${active} 个进行中 / 最多 3 个并行` : `${tasks.length} 个任务 · 点击查看结果`}</span>
    </summary>
    <p className="px-4 pb-2 text-xs text-text-muted">每次提交独立保存提示词和参数。切换工作区可继续运行；本次列表刷新后清空。</p>
    <ul className="max-h-40 divide-y divide-border-subtle overflow-y-auto px-4">{tasks.map(task => <li key={task.id} className="flex items-center gap-3 py-2">
      {task.active ? <Loader2 size={15} className="shrink-0 animate-spin text-accent" /> : <Check size={15} className="shrink-0 text-text-muted" />}
      <div className="min-w-0 flex-1"><p className="truncate text-xs text-text-primary" title={task.prompt}>{task.prompt}</p><p className="mt-1 truncate text-xs text-text-muted">{task.model} · {labels[task.status]}{task.images.length ? ` · ${task.images.length} 张` : ""}</p></div>
      <button type="button" disabled={task.active} onClick={() => onView(task)} className="min-h-10 shrink-0 whitespace-nowrap rounded-md border border-border-subtle px-3 text-xs text-accent disabled:opacity-40">{task.images.length ? "查看结果" : task.active ? "生成中" : "查看状态"}</button>
      {task.status === "pending" && <button type="button" disabled={!!querying} onClick={async () => { setQuerying(task.id); try { await onQuery(task); } finally { setQuerying(""); } }} className="min-h-10 shrink-0 whitespace-nowrap px-2 text-xs text-accent">{querying === task.id ? "查询中…" : "查询原任务"}</button>}
    </li>)}</ul>
  </details>;
}
