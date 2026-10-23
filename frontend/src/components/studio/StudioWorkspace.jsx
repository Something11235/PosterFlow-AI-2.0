import React, { useEffect, useRef, useState } from "react";
import { ArrowDownToLine, ArrowRight, ArrowUpRight, Check, ChevronRight, FilePenLine, Image, Layers3, Music2, Plus, Search, SlidersHorizontal, Trash2, Video } from "lucide-react";
import StudioArt from "./StudioArt";
import MusicWorkspace from "./MusicWorkspace";
import { defaultFlow, defaultSuno } from "../../lib/music";
import { buildStudioDraft, defaultMusic, MODEL_CATALOG, STUDIO_AREAS, VIDEO_MODELS } from "../../lib/studioCatalog";

const ICONS = { image: Image, video: Video, music: Music2 };
const PAGE_TITLES = { home: "创作总览", video: "视频创作", music: "音乐创作", drafts: "创作草稿", models: "模型一览" };
const areaForKind = kind => kind;
const timeLabel = value => new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(value));

function DraftItem({ draft, onEdit, onDelete, onInspect }) {
  const Icon = ICONS[draft.kind];
  return <article className="studio-draft-item"><span className={`studio-draft-icon studio-tone-${areaForKind(draft.kind)}`}><Icon size={19} /></span><div><h3>{draft.title}</h3><p>{draft.body.model} <span>·</span> {timeLabel(draft.createdAt)}</p></div><span className="studio-draft-state">本地草稿</span><div className="studio-draft-actions"><button type="button" onClick={() => onEdit(draft)}>编辑<ChevronRight size={14} /></button><button type="button" onClick={() => onInspect(draft)} aria-label={`查看草稿参数：${draft.title}`}><SlidersHorizontal size={16} /></button><button type="button" onClick={() => onDelete(draft.id)} aria-label={`删除草稿：${draft.title}`}><Trash2 size={16} /></button></div></article>;
}

export default function StudioWorkspace({ area, onAreaChange, onStartImage, username, identity, authHeaders, session, account, accountLoading, onLogin, onAccountRefresh }) {
  // App keys this workspace by identity, clearing all drafts on login/logout.
  // Drafts never enter persistent browser storage or the cloud text history.
  const [drafts, onDraftsChange] = useState([]);
  const [idea, setIdea] = useState("");
  const [ideaArea, setIdeaArea] = useState("image");
  const [music, setMusic] = useState(defaultMusic);
  const [modelFilter, setModelFilter] = useState("all");
  const [modelSearch, setModelSearch] = useState("");
  const [, setMessageState] = useState(null);
  const [inspected, setInspected] = useState(null);
  const inspectorRef = useRef(null);
  const scrollRef = useRef(null);
  const activeKind = area;
  const setMessage = value => setMessageState(value ? { ...value, area, kind: activeKind } : null);
  const activeValues = music;
  const navigate = next => { setMessage(null); setInspected(null); onAreaChange(next); };
  const filteredModels = MODEL_CATALOG.filter(model => (modelFilter === "all" || model.area === modelFilter) && `${model.name} ${model.id} ${model.maker}`.toLowerCase().includes(modelSearch.trim().toLowerCase()));

  useEffect(() => {
    if (!inspected) return;
    inspectorRef.current?.scrollIntoView({ behavior: "instant", block: "start" });
    inspectorRef.current?.focus({ preventScroll: true });
  }, [inspected]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 0, behavior: "instant" });
    if (window.matchMedia("(max-width: 1023px)").matches) window.scrollTo({ top: 0, behavior: "instant" });
  }, [area]);

  function start(kind, text) {
    setMessage(null);
    setInspected(null);
    if (kind === "image") { onStartImage(text); return; }
    if (kind === "music" && text) setMusic({ ...defaultSuno(), prompt: text });
    onAreaChange(kind);
  }
  function saveDraft(event) {
    event?.preventDefault();
    try {
      if (drafts.length >= 30) throw new Error("本次会话最多保留 30 份草稿，请先导出或删除部分草稿。");
      const draft = { ...buildStudioDraft(activeKind, activeValues), id: crypto.randomUUID(), createdAt: new Date().toISOString() };
      onDraftsChange(previous => [draft, ...previous]);
      setMessage({ success: true, text: "草稿已保留在本次会话，尚未提交生成或扣除积分。" });
      return "草稿已保留在本次会话，尚未提交生成或扣除积分。";
    } catch (error) { setMessage({ success: false, text: error.message }); return error.message; }
  }
  function editDraft(draft) {
    setInspected(null);
    const body = draft.body;
    if (draft.kind === "music") setMusic({ ...(body.model === "flowmusic" ? defaultFlow() : defaultSuno()), ...body });
    onAreaChange(areaForKind(draft.kind));
    setMessage(null);
  }
  function deleteDraft(id) {
    onDraftsChange(previous => previous.filter(item => item.id !== id));
    if (inspected?.id === id) setInspected(null);
  }
  function exportDraft(draft) {
    const blob = new Blob([JSON.stringify({ version: 1, preview: true, ...draft }, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob), link = document.createElement("a");
    link.href = url; link.download = `posterflow-draft-${draft.id}.json`; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  const draftProps = { onEdit: editDraft, onDelete: deleteDraft, onInspect: setInspected };

  return <div className="studio-workspace" data-studio-area={area}>
    <header className="studio-topbar"><div><span className="studio-breadcrumb">工作空间</span><ChevronRight size={13} /><strong>{PAGE_TITLES[area]}</strong></div><div><span className="studio-local-badge"><span />本地新版预览</span><button type="button" className="studio-top-drafts" onClick={() => navigate("drafts")}><FilePenLine size={15} />草稿{drafts.length > 0 && <span>{drafts.length}</span>}</button></div></header>
    <div ref={scrollRef} className="studio-scroll">
      {area === "home" && <div className="studio-page studio-home">
        <section className="studio-intro"><div><p className="studio-eyebrow">YOUR NEXT IDEA STARTS HERE <span>↗</span></p><h1>让想象，<span>拥有更多表达。</span></h1><p className="studio-intro-copy">{username ? `${username}，欢迎回来。` : "欢迎来到你的创作空间。"}从一段文字出发，探索图像、音乐与视频。</p></div><div className="studio-edition"><span>POSTERFLOW STUDIO</span><strong>One idea.<br /><em>More possibilities.</em></strong><small>创作，由你定义。 / 2026</small></div></section>
        <section className="studio-media-grid" aria-label="选择创作类型">{STUDIO_AREAS.map((item, index) => { const Icon = ICONS[item.id]; return <button type="button" key={item.id} className={`studio-media-card studio-tone-${item.id}`} onClick={() => start(item.id, "")}><div className="studio-card-top"><span>0{index + 1} / {item.en}</span><span className={item.id === "image" ? "studio-card-live" : ""}>{item.status}</span></div><div className="studio-card-art"><StudioArt kind={item.id} /><span className="studio-art-caption">CONCEPT ART / 示意设计</span></div><div className="studio-card-bottom"><div><h2><Icon size={18} strokeWidth={1.7} />{item.label}</h2><p>{item.description}</p></div><span className="studio-card-arrow"><ArrowUpRight size={20} /></span></div></button>; })}</section>
        <section className="studio-idea-box" aria-labelledby="studio-idea-heading"><div className="studio-section-heading"><div><span className="studio-section-number">01</span><h2 id="studio-idea-heading">从一个想法开始</h2></div><span>把脑海里的那一幕，写下来。</span></div><div className="studio-idea-input"><textarea aria-label="你的创作灵感" placeholder="如果现在能创造任何东西，你想做什么？" value={idea} onChange={event => setIdea(event.target.value)} rows={2} /><div className="studio-idea-bottom"><div className="studio-idea-tabs">{STUDIO_AREAS.filter(item => item.id !== "video").map(item => { const Icon = ICONS[item.id]; return <button type="button" key={item.id} aria-pressed={ideaArea === item.id} onClick={() => setIdeaArea(item.id)}><Icon size={14} />{item.short}</button>; })}</div><button type="button" className="studio-primary" onClick={() => start(ideaArea, idea)}>进入创作<ArrowRight size={16} /></button></div></div></section>
        <div className="studio-home-bottom"><section className="studio-recent"><div className="studio-section-heading"><div><span className="studio-section-number">02</span><h2>最近的草稿</h2></div><button type="button" onClick={() => navigate("drafts")}>查看全部<ArrowUpRight size={14} /></button></div>{drafts.length ? drafts.slice(0, 2).map(draft => <DraftItem key={draft.id} draft={draft} {...draftProps} />) : <div className="studio-empty-inline"><FilePenLine size={23} /><div><strong>你的下一个作品，正在酝酿</strong><p>先为下一首音乐，保存一份草稿。</p></div><button type="button" onClick={() => navigate("music")} aria-label="创建音乐草稿"><Plus size={19} /></button></div>}<p className="studio-footnote">本次会话保留 · 刷新后清空 · 可导出参数草稿</p></section><section className="studio-route-card"><div><Layers3 size={18} /><span>新版进展</span><small>WORK IN PROGRESS</small></div><h3>先找到表达方式，<br />再连接创作能力。</h3><p>图像沿用现有服务。音乐支持 APIMart 生成、试听与下载。视频先保留模型预览，生成能力稍后开放。</p><button type="button" onClick={() => navigate("models")}>探索首批模型<ArrowRight size={15} /></button></section></div>
        <footer className="studio-footer"><span>POSTERFLOW — A SPACE FOR YOUR IDEAS.</span><span>图像 · 音乐 · 视频</span></footer>
      </div>}

      <MusicWorkspace active={area === "music"} identity={identity} authHeaders={authHeaders} session={session} account={account} accountLoading={accountLoading} onLogin={onLogin} onAccountRefresh={onAccountRefresh} values={music} onChange={setMusic} onSaveDraft={saveDraft} />

      {area === "video" && <div className="studio-page studio-video-preview">
        <div className="studio-page-title"><div><p className="studio-eyebrow">VIDEO / COMING NEXT</p><h1>先为下一个故事，选好模型。</h1><p>视频入口已保留。本阶段仅展示模型，暂未开放生成。</p></div><span className="studio-outline-badge">模型预览</span></div>
        <div className="studio-video-banner"><div><Video size={24} /><h2>视频创作，稍后启程。</h2><p>先专注图像与音乐。视频模型保留在这里，等待下一阶段接入。</p></div><StudioArt kind="video" /></div>
        <div className="studio-model-grid" aria-label="视频模型预览">{VIDEO_MODELS.map(model => <article className="studio-model-card studio-tone-video" key={model.id}><div><span className="studio-model-icon"><Video size={21} /></span><small>视频 / {model.maker}</small></div><h2>{model.name}</h2><p>暂未开放生成</p><footer><span>模型预览</span></footer></article>)}</div>
      </div>}

      {area === "drafts" && <div className="studio-page"><div className="studio-page-title"><div><p className="studio-eyebrow">IDEAS IN PROGRESS</p><h1>还没完成的，也值得保留。</h1><p>本次会话的 {drafts.length} 份创作草稿。刷新页面后清空，需要保留时请导出。</p></div><button type="button" className="studio-primary" onClick={() => navigate("music")}><Plus size={17} />新建草稿</button></div><section className="studio-draft-list">{drafts.length ? drafts.map(draft => <DraftItem key={draft.id} draft={draft} {...draftProps} />) : <div className="studio-empty-state"><FilePenLine size={35} strokeWidth={1.3} /><h2>留一个位置，给下一个灵感</h2><p>前往音乐工作区，保存第一份草稿。</p><button type="button" className="studio-secondary" onClick={() => navigate("home")}>探索创作类型<ArrowRight size={16} /></button></div>}</section></div>}

      {area === "models" && <div className="studio-page">
        <div className="studio-page-title"><div><p className="studio-eyebrow">A CURATED STARTING POINT</p><h1>选对工具，让灵感更进一步。</h1><p>图像、音乐与视频，按创作类型查看。预览模型尚未接通生成。</p></div><span className="studio-outline-badge">{MODEL_CATALOG.length} 个模型 · 分阶段接入</span></div>
        <div className="studio-model-toolbar"><div className="studio-model-filters">{[{ id: "all", short: "全部" }, ...STUDIO_AREAS].map(item => <button type="button" key={item.id} aria-pressed={modelFilter === item.id} onClick={() => setModelFilter(item.id)}>{item.short}</button>)}</div><label className="studio-model-search"><Search size={16} /><input aria-label="搜索候选模型" placeholder="搜索模型名称" value={modelSearch} onChange={event => setModelSearch(event.target.value)} /></label></div>
        <div className="studio-model-grid">{filteredModels.map(model => {
          const Icon = ICONS[model.area];
          return <article className={`studio-model-card studio-tone-${model.area}`} key={model.id}>
            <div><span className="studio-model-icon"><Icon size={21} /></span><small>{STUDIO_AREAS.find(item => item.id === model.area).short} / {model.maker}</small></div><h2>{model.name}</h2><p>{model.summary}</p><footer><span>{model.provider === "apimart" ? "已接入 · 需配置图片服务" : model.available ? "现有图像功能" : model.area === "music" ? "音乐创作 · 2 积分 / 首" : "模型预览 · 规划接入"}</span></footer>
          </article>;
        })}</div>
        {!filteredModels.length && <div className="studio-empty-state"><Search size={28} /><h2>没有找到匹配的模型</h2><p>试试其他名称，或选择全部创作类型。</p><button type="button" className="studio-secondary" onClick={() => { setModelSearch(""); setModelFilter("all"); }}>清除筛选</button></div>}
        <p className="studio-help">现有图像工作区继续使用原图片服务配置。模型预览不会替换已配置模型。</p>
      </div>}

      {inspected && <section ref={inspectorRef} tabIndex={-1} className="studio-inspector" aria-label="草稿参数预览"><div className="studio-panel-heading"><span>草稿参数 · 尚未提交</span><button type="button" onClick={() => setInspected(null)}>收起<Check size={15} /></button></div><p>此文件可供后续接入核对，不包含 API Key。</p><pre>{JSON.stringify({ method: "POST", endpoint: inspected.endpoint, encoding: inspected.encoding, body: inspected.body }, null, 2)}</pre><button type="button" className="studio-secondary" onClick={() => exportDraft(inspected)}><ArrowDownToLine size={16} />导出这份草稿</button></section>}
    </div>
  </div>;
}
