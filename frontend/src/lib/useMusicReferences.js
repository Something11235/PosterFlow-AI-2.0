import { useEffect, useRef, useState } from "react";
import { musicAudioFile, uploadMusicReference } from "./musicReferences.js";

export function useMusicReferences(scope, options) {
  const [items, setItems] = useState([]), [message, setMessage] = useState("");
  const requests = useRef(new Map()), scopeRef = useRef(scope);
  useEffect(() => {
    scopeRef.current = scope;
    setItems([]); setMessage("");
    const pending = requests.current;
    return () => {
      for (const { controller, url, timer } of pending.values()) { controller?.abort(); clearTimeout(timer); URL.revokeObjectURL(url); }
      pending.clear();
    };
  }, [scope]);

  async function add(files, limit) {
    const batch = [], errors = [];
    for (const file of Array.from(files || [])) {
      if (requests.current.size + batch.length >= limit) { errors.push(`本次最多选择 ${limit} 段音频。`); break; }
      try {
        musicAudioFile(file);
        const fingerprint = `${file.name}:${file.size}:${file.lastModified}`;
        if ([...requests.current.values(), ...batch].some(item => item.fingerprint === fingerprint)) continue;
        batch.push({ id: crypto.randomUUID(), file, fingerprint, url: URL.createObjectURL(file), state: "uploading", name: file.name });
      } catch (error) { errors.push(error.message); }
    }
    setMessage([...new Set(errors)].join(" "));
    const startedScope = scope;
    for (const item of batch) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 120000);
      requests.current.set(item.id, { ...item, controller, timer });
      setItems(previous => [...previous, item]);
    }
    await Promise.allSettled(batch.map(async item => {
      const request = requests.current.get(item.id);
      try {
        const reference = await uploadMusicReference(item.file, options, request.controller.signal);
        if (request.controller.signal.aborted || startedScope !== scopeRef.current || !requests.current.has(item.id)) return;
        setItems(previous => previous.map(row => row.id === item.id ? { ...row, state: "ready", reference } : row));
      } catch (error) {
        if (startedScope !== scopeRef.current || !requests.current.has(item.id)) return;
        setItems(previous => previous.map(row => row.id === item.id ? { ...row, state: "failed", error: request.controller.signal.aborted ? "上传超时，请移除后重新添加。" : error.message } : row));
      } finally { clearTimeout(request.timer); }
    }));
  }
  function remove(id) {
    const item = requests.current.get(id);
    if (item) { item.controller.abort(); clearTimeout(item.timer); URL.revokeObjectURL(item.url); requests.current.delete(id); }
    setItems(previous => previous.filter(item => item.id !== id));
    setMessage("");
  }
  return { items, message, add, remove, busy: items.some(item => item.state === "uploading"), ready: items.filter(item => item.state === "ready").map(item => item.reference) };
}
