import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArrowDownToLine, Check, CircleHelp, Copy, FilePenLine, KeyRound, LoaderCircle, Music2, RefreshCw, Sparkles } from "lucide-react";
import { buildMusicParameters, defaultFlow, defaultSuno, downloadMusic, FLOW_VERSIONS, musicApi, musicLength, musicShouldPoll, readMusicSession, saveMusicSession, SUNO_VERSIONS } from "../../lib/music";
import "./music.css";

const STATUS = { submitting: "正在提交", submitted: "已受理", pending: "等待生成", processing: "生成中", completed: "生成完成", failed: "生成失败", unknown: "状态待确认", submission_unknown: "提交结果待确认" };
function Field({ label, hint, children }) {
  const control = typeof children.type === "string" ? React.cloneElement(children, { "aria-label": label, "aria-description": hint }) : children;
  return <label className="studio-field"><span>{label}</span>{control}{hint && <small>{hint}</small>}</label>;
}
function Select({ value, onChange, label, options }) {
  return <select aria-label={label} value={value} onChange={event => onChange(event.target.value)}>{options.map(option => typeof option === "string" ? <option key={option} value={option}>{option}</option> : <option key={option.value} value={option.value}>{option.label}</option>)}</select>;
}
const mergeJobs = (previous, jobs) => [...new Map([...previous, ...jobs].map(job => [job.request_id, job])).values()].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 50);

export default function MusicWorkspace({ active, identity, authHeaders, session, account, accountLoading, onLogin, onAccountRefresh, values, onChange, onSaveDraft }) {
  const [mode, setMode] = useState(() => readMusicSession(identity, "mode") === "own_key" ? "own_key" : "platform");
  const [key, setKey] = useState(() => readMusicSession(identity, "key"));
  const [keyInput, setKeyInput] = useState(key);
  const [configNotice, setConfigNotice] = useState(null);
  const [endpoint, setEndpoint] = useState(() => readMusicSession(identity, "endpoint"));
  const [endpointInput, setEndpointInput] = useState(endpoint);
  const [queryTemplate, setQueryTemplate] = useState(() => readMusicSession(identity, "queryTemplate"));
  const [queryInput, setQueryInput] = useState(queryTemplate);
  const [authType, setAuthType] = useState(() => readMusicSession(identity, "authType") || "bearer");
  const [authInput, setAuthInput] = useState(authType);
  const [config, setConfig] = useState(null);
  const [jobs, setJobs] = useState([]);
  const [selected, setSelected] = useState("");
  const [result, setResult] = useState(null);
  const [message, setMessage] = useState("");
  const [submissionError, setSubmissionError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [querying, setQuerying] = useState(false);
  const [downloading, setDownloading] = useState("");
  const [listRevision, setListRevision] = useState(0);
  const pending = useRef(null);
  const queryingRef = useRef(null);
  const forms = useRef({ suno: defaultSuno(), flowmusic: defaultFlow(), custom: { ...defaultSuno(), ...defaultFlow(), model: "custom", custom_model: "", custom_version: "", parameter_format: "suno" } });
  const prompts = useRef({ inspiration: "", custom: "" });
  const options = useMemo(() => ({ mode, key, endpoint, queryTemplate, authType, authHeaders }), [mode, key, endpoint, queryTemplate, authType, authHeaders]);
  const current = jobs.find(job => job.request_id === selected);
  const shouldPoll = musicShouldPoll(current);
  const update = patch => onChange(previous => ({ ...previous, ...patch }));
  const isCustom = values.model === "custom";
  const isSuno = values.model === "suno" || (isCustom && values.parameter_format !== "flowmusic");

  useEffect(() => {
    if (!active) return;
    const controller = new AbortController();
    musicApi("/config", { signal: controller.signal }).then(data => { if (!controller.signal.aborted) setConfig(data); }).catch(error => { if (!controller.signal.aborted) setMessage(error.message); });
    return () => controller.abort();
  }, [active]);

  useEffect(() => {
    setJobs([]); setSelected(""); setResult(null); setMessage(""); setSubmissionError(null);
    return () => { pending.current?.abort(); queryingRef.current?.abort(); };
  }, [options]);

  useEffect(() => {
    if (!active || !config?.database_configured || (mode === "platform" ? !session || !config.platform_configured : !key)) return;
    const controller = new AbortController();
    musicApi("/tasks", { ...options, signal: controller.signal }).then(data => {
      if (controller.signal.aborted) return;
      setJobs(previous => mergeJobs(previous, data.jobs || []));
      const remembered = readMusicSession(identity, `selected.${mode}`);
      setSelected(previous => previous || (data.jobs?.some(job => job.request_id === remembered) ? remembered : data.jobs?.[0]?.request_id || ""));
    }).catch(error => { if (!controller.signal.aborted) setMessage(error.message); });
    return () => controller.abort();
  }, [active, config, options, mode, key, session, identity, listRevision]);

  const refresh = useCallback(async requestId => {
    if (!requestId || queryingRef.current) return;
    const controller = new AbortController();
    queryingRef.current = controller;
    setQuerying(true);
    try {
      const data = await musicApi(`/tasks/${encodeURIComponent(requestId)}`, { ...options, signal: controller.signal });
      if (controller.signal.aborted) return;
      setJobs(previous => mergeJobs(previous, [data.job]));
      setResult({ ...data, requestId });
      setMessage(data.warning || "");
      if (data.credit_balance != null) onAccountRefresh();
    } catch (error) {
      if (!controller.signal.aborted) setMessage(error.name === "AbortError" ? "查询超时，请稍后刷新原任务。" : error.message);
    } finally {
      if (queryingRef.current === controller) { queryingRef.current = null; setQuerying(false); }
    }
  }, [options, onAccountRefresh]);

  useEffect(() => {
    if (!active || !selected) return;
    let stopped = false, timer;
    let attempts = 0;
    const tick = async () => {
      if (stopped) return;
      if (document.visibilityState === "visible") { await refresh(selected); attempts += 1; }
      if (!stopped && shouldPoll && attempts < 90) timer = setTimeout(tick, Math.min(15000, 5000 + attempts * 300));
    };
    timer = setTimeout(tick, 3000);
    return () => { stopped = true; clearTimeout(timer); queryingRef.current?.abort(); };
  }, [active, selected, shouldPoll, refresh]);

  function switchModel(model) {
    forms.current[values.model] = values;
    onChange(forms.current[model]);
    setMessage("");
  }
  function switchMode(custom) {
    if (values.custom === custom) return;
    prompts.current[values.custom ? "custom" : "inspiration"] = values.prompt;
    update({ custom, prompt: prompts.current[custom ? "custom" : "inspiration"] });
  }
  function changeBilling(next) {
    if (busy) return;
    if (next === "platform" && values.model === "custom") onChange(defaultSuno());
    setMode(next); setConfigNotice(null); saveMusicSession(identity, "mode", next);
  }
  function saveKey() {
    const next = keyInput.trim();
    if (!next || /\s/.test(next)) { setConfigNotice({ kind: "error", text: "请填写有效的 API Key，不能包含空格或换行。" }); return; }
    try {
      const target = new URL(endpointInput.trim());
      if (target.protocol !== "https:" || target.username || target.password || target.search || target.hash) throw new Error();
      if (queryInput && (queryInput.match(/\{task_id\}/g) || []).length !== 1) throw new Error();
    } catch { setConfigNotice({ kind: "error", text: "请填写完整的 HTTPS 生成接口；查询地址可留空，如有填写须包含一次 {task_id}。" }); return; }
    setKey(next); setEndpoint(endpointInput.trim()); setQueryTemplate(queryInput.trim()); setAuthType(authInput);
    const saved = [saveMusicSession(identity, "key", next), saveMusicSession(identity, "endpoint", endpointInput.trim()), saveMusicSession(identity, "queryTemplate", queryInput.trim()), saveMusicSession(identity, "authType", authInput)].every(Boolean);
    setConfigNotice({ kind: saved ? "success" : "warning", text: saved ? "配置已保存在当前浏览器会话。可继续选择模型并填写音乐描述；生成时才会验证接口和 Key。" : "浏览器无法保存，配置仅在当前页面生效。" });
    setListRevision(value => value + 1);
  }
  async function generate(event) {
    event.preventDefault();
    if (pending.current) return;
    let parameters;
    try { parameters = buildMusicParameters(values, { allowCustom: mode === "own_key" }); } catch (error) { setMessage(error.message); return; }
    if (mode === "platform" && !session) { onLogin(); return; }
    if (mode === "own_key" && !key) { setMessage("请先保存 API Key。"); return; }
    const requestId = crypto.randomUUID(), controller = new AbortController();
    pending.current = controller;
    setBusy(true); setMessage(""); setSubmissionError(null); setResult(null); setSelected(requestId);
    saveMusicSession(identity, `selected.${mode}`, requestId);
    const placeholder = { request_id: requestId, billing_mode: mode, model: values.model, version: isCustom ? values.custom_version : values.version, status: "submitting", created_at: new Date().toISOString() };
    setJobs(previous => mergeJobs(previous, [placeholder]));
    try {
      const data = await musicApi("/generations", { ...options, body: { request_id: requestId, parameters }, signal: controller.signal });
      if (controller.signal.aborted) return;
      setJobs(previous => mergeJobs(previous, [data.job]));
      if (mode === "platform") onAccountRefresh();
    } catch (error) {
      if (controller.signal.aborted) return;
      setJobs(previous => mergeJobs(previous, [{ ...placeholder, status: "submission_unknown" }]));
      setSubmissionError({ requestId, message: error.name === "AbortError" ? "提交等待超时，请保留当前请求编号，勿重复生成。" : error.message });
      // A GET recovers an accepted intent; never replay the paid POST.
      await refresh(requestId);
    } finally {
      if (pending.current === controller) { pending.current = null; setBusy(false); }
    }
  }
  async function download(track, format) {
    const id = `${track.audio_index}-${format}`;
    setDownloading(id); setMessage("");
    try { await downloadMusic(format === "wav" ? track.wav_url : track.audio_url, track.title, format); }
    catch (error) { setMessage(error.name === "AbortError" ? "下载超时，可以打开音频链接后保存。" : error.message); }
    finally { setDownloading(""); }
  }
  function selectTask(job) {
    queryingRef.current?.abort();
    setSelected(job.request_id); setResult(null); setMessage("");
    saveMusicSession(identity, `selected.${mode}`, job.request_id);
  }
  const platformBlocked = mode === "platform" && (!config?.platform_configured || (session && (accountLoading || !account || !account.email_verified || account.profile?.status === "frozen" || Number(account.credits?.balance) < 2)));
  const disabled = busy || !config?.database_configured || platformBlocked || (mode === "own_key" && !key);
  const tracks = result?.requestId === selected ? result.tracks || [] : [];

  return <div className="studio-page studio-tone-music music-workspace" hidden={!active}>
    <div className="studio-page-title"><div><p className="studio-eyebrow">MUSIC WORKSPACE</p><h1>给灵感，一段旋律。</h1><p>从一句描述或一段歌词开始，用 Suno 与 Flow Music 创作。</p></div><span className="studio-outline-badge">2 积分 / 首</span></div>
    <div className="music-layout"><form className="studio-editor-panel music-editor" onSubmit={generate}>
      <div className="studio-panel-heading"><span><Music2 size={17} />创作设置</span><small>01 / CREATE</small></div>
      <div className="studio-form-body">
        <div className="studio-segments" aria-label="音乐服务方式"><button type="button" disabled={busy} aria-pressed={mode === "platform"} onClick={() => changeBilling("platform")}>平台积分</button><button type="button" disabled={busy} aria-pressed={mode === "own_key"} onClick={() => changeBilling("own_key")}>自定义API Key</button></div>
        {mode === "platform" ? <div className="music-service-note"><span>网站积分 <strong>{!session ? "登录后可用" : accountLoading ? "加载中…" : account?.credits?.balance ?? "暂不可用"}</strong></span><p>每首 2 积分，先预留 2 积分，完成后按实际首数结算。多首结果余额不足时，补足后刷新领取。</p>{!session && <button type="button" className="studio-secondary" onClick={onLogin}>登录账户</button>}</div> : <div className="music-key-box"><Field label="API Key" hint="Key 只保存在当前浏览器会话，不扣网站积分。"><input type="password" aria-label="API Key" autoComplete="off" spellCheck={false} value={keyInput} onChange={event => { setKeyInput(event.target.value); setConfigNotice(null); }} /></Field><Field label="音乐生成接口地址" hint="填写服务商的完整 HTTPS 生成接口；支持兼容的异步音乐协议。"><input type="url" aria-label="音乐生成接口地址" value={endpointInput} onChange={event => { setEndpointInput(event.target.value); setConfigNotice(null); }} spellCheck={false} /></Field><Field label="任务查询地址（可选）" hint="用 {task_id} 表示任务编号。留空时使用生成接口同级的 tasks/{task_id}。"><input type="text" aria-label="任务查询地址" value={queryInput} onChange={event => { setQueryInput(event.target.value); setConfigNotice(null); }} spellCheck={false} /></Field><Field label="鉴权方式"><Select label="音乐鉴权方式" value={authInput} onChange={value => { setAuthInput(value); setConfigNotice(null); }} options={[{ value: "bearer", label: "Bearer Token" }, { value: "x-api-key", label: "x-api-key" }]} /></Field><div className="music-inline-actions"><button type="button" className="studio-secondary" onClick={saveKey} disabled={busy}>{configNotice?.kind === "success" ? <Check size={15} /> : <KeyRound size={15} />}{configNotice?.kind === "success" ? "已保存" : "保存配置"}</button><button type="button" className="studio-text-button" disabled={busy} onClick={() => { setKey(""); setKeyInput(""); setEndpoint(""); setEndpointInput(""); setQueryTemplate(""); setQueryInput(""); setAuthType("bearer"); setAuthInput("bearer"); setConfigNotice({ kind: "info", text: "配置已清除。" }); for (const name of ["key", "endpoint", "queryTemplate", "authType"]) saveMusicSession(identity, name, ""); }}>清除</button></div>{configNotice && <p className="music-config-feedback" data-kind={configNotice.kind} role={configNotice.kind === "error" ? "alert" : "status"}>{configNotice.text}</p>}</div>}
        {config && !config.database_configured && <p className="music-config-note">音乐服务尚未完成开发配置，可以先编辑并保存草稿。</p>}
        {mode === "platform" && config?.database_configured && !config.platform_configured && <p className="music-config-note">平台音乐服务尚未配置，可使用自定义API Key。</p>}
        <div className="music-field-pair"><Field label="音乐模型"><Select label="音乐模型" value={values.model} onChange={switchModel} options={[{ value: "suno", label: "Suno" }, { value: "flowmusic", label: "Flow Music" }, ...(mode === "own_key" ? [{ value: "custom", label: "自定义模型" }] : [])]} /></Field>{isCustom ? <Field label="参数格式"><Select label="参数格式" value={values.parameter_format || "suno"} onChange={parameter_format => update({ parameter_format })} options={[{ value: "suno", label: "Suno 格式" }, { value: "flowmusic", label: "Flow Music 格式" }]} /></Field> : <Field label="模型版本"><Select label="模型版本" value={values.version || (isSuno ? "v6" : "lyria-3-pro")} onChange={version => update({ version })} options={isSuno ? SUNO_VERSIONS : FLOW_VERSIONS} /></Field>}</div>
        {isCustom && <><Field label="自定义模型标识" hint="填写服务商支持的模型名称，请按该模型选择参数格式。"><input aria-label="自定义模型标识" value={values.custom_model || ""} onChange={event => update({ custom_model: event.target.value })} /></Field><Field label="自定义版本（可选）"><input aria-label="自定义版本" value={values.custom_version || ""} onChange={event => update({ custom_version: event.target.value })} /></Field></>}
        {isSuno ? <>
          <div className="studio-segments" aria-label="音乐创作模式"><button type="button" aria-pressed={!values.custom} onClick={() => switchMode(false)}>灵感成曲</button><button type="button" aria-pressed={values.custom} onClick={() => switchMode(true)}>自定义歌词</button></div>
          {values.custom && <Field label="歌曲标题（可选）" hint={`${musicLength(values.title)} / 80 字符`}><input value={values.title} onChange={event => update({ title: event.target.value })} /></Field>}
          <Field label={values.custom ? "歌词" : "音乐描述"} hint={`${musicLength(values.prompt)} / ${values.custom ? 5000 : 3000} 字符${values.custom && values.instrumental ? " · 纯音乐可留空" : ""}`}><textarea rows={7} value={values.prompt} placeholder={values.custom ? "[Verse]\n写下你的歌词…" : "描述音乐风格、情绪、乐器或主题…"} onChange={event => update({ prompt: event.target.value })} /></Field>
          {!values.custom && <button type="button" className="studio-example" onClick={() => update({ prompt: "适合深夜工作的 Lo-fi 纯音乐，温暖电钢琴、轻柔鼓点和雨声。" })}><Sparkles size={14} />试试深夜 Lo-fi 灵感</button>}
          {values.custom && <Field label="音乐风格（可选）" hint={`${musicLength(values.style)} / 1000 字符`}><textarea rows={2} value={values.style} placeholder="例如：indie pop、原声吉他、温暖女声" onChange={event => update({ style: event.target.value })} /></Field>}
          <label className="studio-toggle"><span><strong>纯音乐</strong><small>开启后生成无人声作品</small></span><input type="checkbox" checked={values.instrumental} onChange={event => update({ instrumental: event.target.checked })} /><span className="studio-switch" aria-hidden="true" /></label>
          <details className="music-advanced"><summary>更多创作参数</summary><div className="music-advanced-body">
            <div className="music-field-pair"><Field label="人声"><Select label="人声" value={values.vocal_gender || ""} onChange={vocal_gender => update({ vocal_gender })} options={[{ value: "", label: "自动" }, { value: "Female", label: "女声" }, { value: "Male", label: "男声" }]} /></Field><Field label="音频格式"><Select label="音频格式" value={values.audio_format || ""} onChange={audio_format => update({ audio_format })} options={[{ value: "", label: "自动" }, "mp3", "m4a", "wav"]} /></Field></div>
            {values.custom && <><Field label="目标时长（秒）" hint="可留空；10–360 秒，实际时长以生成结果为准。"><input type="number" min="10" max="360" step="1" placeholder="自动" value={values.duration ?? ""} onChange={event => update({ duration: event.target.value })} /></Field><Field label="排除风格（可选）"><input value={values.negative_tags || ""} onChange={event => update({ negative_tags: event.target.value })} /></Field><label className="music-check"><input type="checkbox" checked={Boolean(values.auto_lyrics)} onChange={event => update({ auto_lyrics: event.target.checked })} />允许模型改写歌词</label></>}
            <Field label="风格变化"><Select label="风格变化" value={values.variety || ""} onChange={variety => update({ variety })} options={[{ value: "", label: "自动" }, "off", "normal", "high", "extra", "max"]} /></Field>
            {[["style_weight", "风格权重"], ["weirdness_constraint", "创意度"], ["audio_weight", "音频权重"]].map(([name, label]) => <Field key={name} label={label} hint="0–1；留空使用模型默认值。"><input type="number" min="0" max="1" step="0.01" value={values[name] ?? ""} onChange={event => update({ [name]: event.target.value })} /></Field>)}
          </div></details>
        </> : <>
          <Field label="歌曲标题（可选）"><input value={values.title || ""} onChange={event => update({ title: event.target.value })} /></Field>
          <Field label="音乐描述" hint={`${musicLength(values.sound_prompt)} / 6000 字符（本站上限）`}><textarea rows={4} value={values.sound_prompt || ""} placeholder="描述曲风、情绪和乐器…" onChange={event => update({ sound_prompt: event.target.value })} /></Field>
          <Field label="歌词（可选）" hint={`${musicLength(values.lyrics)} / 6000 字符（本站上限）；音乐描述与歌词至少填写一项。`}><textarea rows={5} value={values.lyrics || ""} onChange={event => update({ lyrics: event.target.value })} /></Field>
          <div className="music-field-pair"><Field label="目标时长（秒）" hint="可留空，自动决定；指定时为 1–240 秒。"><input type="number" min="1" max="240" step="1" placeholder="自动" value={values.length ?? ""} onChange={event => update({ length: event.target.value })} /></Field><Field label="BPM（可选）" hint="不小于 1"><input type="number" min="1" step="0.01" value={values.bpm || ""} onChange={event => update({ bpm: event.target.value })} /></Field></div>
          <Field label="随机种子（可选）"><input value={values.seed || ""} onChange={event => update({ seed: event.target.value })} /></Field>
        </>}
        {message && <p role="alert" className="studio-form-message"><CircleHelp size={16} />{message}</p>}
      </div>
      <div className="studio-form-footer music-submit"><button type="button" className="studio-secondary" onClick={() => setMessage(onSaveDraft())}><FilePenLine size={16} />存草稿</button><button type="submit" className="studio-primary" disabled={disabled}>{busy ? <LoaderCircle className="music-spin" size={16} /> : <Music2 size={16} />}{busy ? "正在提交…" : "生成音乐"}<small>{mode === "platform" ? "2 积分 / 首" : "使用自己的 Key"}</small></button></div>
    </form>
    <section className="music-output" aria-label="音乐任务与作品"><div className="studio-panel-heading"><span><Music2 size={17} />我的音乐任务</span><button type="button" className="studio-text-button" disabled={busy} onClick={() => setListRevision(value => value + 1)}><RefreshCw size={15} />刷新列表</button></div>
      {jobs.length > 0 && <div className="music-task-tabs" aria-label="选择音乐任务">{jobs.map(job => <button type="button" key={job.request_id} aria-pressed={job.request_id === selected} onClick={() => selectTask(job)}><strong>{job.model === "flowmusic" ? "Flow Music" : "Suno"} · {job.version}</strong><span>{STATUS[job.status] || "状态待确认"}</span><small>{new Date(job.created_at).toLocaleString("zh-CN", { hour12: false })}</small></button>)}</div>}
      {current ? <div className="music-task-detail"><div className="music-task-status"><span>{STATUS[current.status] || "状态待确认"}</span><button type="button" className="studio-secondary" disabled={querying || busy} onClick={() => refresh(selected)}><RefreshCw className={querying ? "music-spin" : ""} size={15} />{querying ? "查询中…" : "刷新状态"}</button></div><p className="music-task-id">请求编号：{current.request_id}</p>{current.provider_task_id && <p className="music-task-id">服务商任务：{current.provider_task_id}</p>}
        {musicShouldPoll(current) && <><p className="music-waiting">正在等待音乐服务返回结果，完成后会在这里展示。</p>{result?.requestId === selected && <progress aria-label="音乐生成进度" max="100" value={result.progress || 0} />}</>}
        {submissionError?.requestId === selected && <p role="alert" className="studio-form-message">{submissionError.message}</p>}
        {["submitting", "submission_unknown", "unknown"].includes(current.status) && <p className="music-config-note">{current.provider_task_id ? "保留当前请求编号并刷新查询；查询不会重复生成。" : "尚未取得服务商任务编号，刷新只会核对本站记录。请先在服务商后台核对这次请求是否受理，再决定是否重新生成。"}</p>}
        {current.billing_status === "awaiting_balance" && <p role="status" className="music-config-note">已生成 {current.generated_count} 首，共需 {current.generated_count * 2} 积分，已预留 {current.reserved_credits} 积分。请补足余额后刷新状态领取。</p>}
        {current.status === "failed" && <p role="status" className="music-config-note">本次音乐生成失败。{current.billing_status === "refunded" ? "预留的网站积分已退回。" : "网站未扣积分，请在服务商后台核对上游记录。"}</p>}
        {current.billing_status === "settled" && <p className="music-settled"><Check size={15} />{current.generated_count} 首 · 已扣 {current.charged_credits} 积分</p>}
        {tracks.map(track => <article className="music-track" key={track.audio_index}><div className="music-track-title"><span className="music-track-art"><Music2 size={24} /></span><div><h2>{track.title}</h2><p>音轨 {track.audio_index} · {Math.floor(track.duration / 60)}:{String(Math.floor(track.duration % 60)).padStart(2, "0")}{track.tags ? ` · ${track.tags}` : ""}</p></div></div><audio controls preload="none" crossOrigin="anonymous" src={track.audio_url} aria-label={`播放 ${track.title}`} onPlay={event => { document.querySelectorAll(".music-track audio").forEach(audio => { if (audio !== event.currentTarget) audio.pause(); }); }} /><div className="music-inline-actions"><button type="button" className="studio-secondary" disabled={Boolean(downloading)} onClick={() => download(track, "audio")}><ArrowDownToLine size={15} />下载音频</button>{track.wav_url && <button type="button" className="studio-secondary" disabled={Boolean(downloading)} onClick={() => download(track, "wav")}>下载 WAV</button>}<a href={track.audio_url} target="_blank" rel="noopener noreferrer" referrerPolicy="no-referrer">打开音频</a></div>{track.lyrics && <details className="music-lyrics"><summary>查看歌词</summary><pre>{track.lyrics}</pre><button type="button" className="studio-secondary" onClick={async () => { try { await navigator.clipboard.writeText(track.lyrics); setMessage("歌词已复制。"); } catch { setMessage("复制失败，请选择歌词后手动复制。"); } }}><Copy size={15} />复制歌词</button></details>}</article>)}
      </div> : <div className="music-empty"><span className="music-empty-icon"><Music2 size={44} strokeWidth={1.25} /></span><p className="studio-eyebrow">YOUR NEXT TRACK</p><h2>让脑海里的声音<br />成为一首音乐。</h2><p>选择模型、写下描述或歌词。<br />生成后即可试听、查看歌词和下载。</p><div className="music-empty-steps"><span>01 写下灵感</span><span>02 生成音乐</span><span>03 试听与下载</span></div></div>}
    </section></div>
  </div>;
}
