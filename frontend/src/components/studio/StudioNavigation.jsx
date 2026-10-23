import React from "react";
import PromptReferences from "../PromptReferences";
import { Aperture, ArrowUpRight, ChartNoAxesCombined, ChevronRight, FilePenLine, Grid2X2, History, Image, LayoutGrid, Music2, UserRound, Video } from "lucide-react";

const NAV = [
  { id: "home", label: "创作总览", icon: LayoutGrid },
  { id: "image", label: "图像创作", icon: Image },
  { id: "music", label: "音乐创作", icon: Music2 },
  { id: "video", label: "视频创作", icon: Video, hint: "稍后开放" },
];

export default function StudioNavigation({ area, onAreaChange, session, account, accountLoading, onOpenAuth, onOpenAccount, onOpenMetrics, onOpenRecharge, onOpenHistory }) {
  const accountName = account?.profile?.username || session?.user?.email || "登录 / 注册";
  return (
    <aside className="studio-nav">
      <div className="studio-brand"><span className="studio-brand-mark"><Aperture size={26} strokeWidth={1.4} /></span><div><strong>PosterFlow<span>AI</span></strong><small>THE CREATIVE STUDIO</small></div></div>
      <div className="studio-mobile-account"><button type="button" onClick={session ? onOpenAccount : onOpenAuth} aria-label={session ? "账户中心" : "登录或注册"}><UserRound size={19} /></button>{session && account?.is_admin && <button type="button" onClick={onOpenMetrics} aria-label="管理员控制台"><ChartNoAxesCombined size={19} /></button>}</div>
      <p className="studio-nav-caption">工作空间 <span>01 —</span></p>
      <nav className="studio-primary-nav" aria-label="创作工作区">
        {NAV.map(item => <button type="button" key={item.id} aria-current={area === item.id ? "page" : undefined} onClick={() => onAreaChange(item.id)}><item.icon size={18} strokeWidth={1.7} /><span>{item.label}</span>{item.hint && <small>{item.hint}</small>}{area === item.id && <span className="studio-nav-dot" />}</button>)}
      </nav>
      <p className="studio-nav-caption studio-library-caption">资料与工具 <span>02 —</span></p>
      <nav className="studio-secondary-nav" aria-label="资料与工具">
        <button type="button" aria-current={area === "drafts" ? "page" : undefined} onClick={() => onAreaChange("drafts")}><FilePenLine size={18} />创作草稿</button>
        <button type="button" aria-current={area === "models" ? "page" : undefined} onClick={() => onAreaChange("models")}><Grid2X2 size={18} />模型一览</button>
        <PromptReferences />
        <button type="button" onClick={onOpenHistory}><History size={18} />历史记录</button>
        <button type="button" className="studio-mobile-tool" onClick={onOpenRecharge}><ArrowUpRight size={18} />购买积分</button>
      </nav>
      <div className="studio-nav-bottom">
        <div className="studio-credit-card"><span>平台积分 <Aperture size={14} /></span><strong>{session ? (accountLoading ? "同步中…" : account?.credits?.balance ?? "—") : "从灵感开始"}</strong><button type="button" onClick={onOpenRecharge}>购买积分 <ArrowUpRight size={15} /></button></div>
        {session && account?.is_admin && <button type="button" className="studio-admin-link" onClick={onOpenMetrics}><ChartNoAxesCombined size={17} />管理员控制台<ChevronRight size={14} /></button>}
        <button type="button" className="studio-account-link" onClick={session ? onOpenAccount : onOpenAuth} aria-label={session ? "账户中心" : "登录或注册"}><span className="studio-avatar">{session ? accountName.slice(0, 1).toUpperCase() : <UserRound size={16} />}</span><span>{accountName}<small>{session ? "管理你的账户" : "继续你的创作"}</small></span><ChevronRight size={15} /></button>
        <a className="studio-source-link" href="https://github.com/Something11235/PosterFlow-AI" target="_blank" rel="noreferrer">PosterFlow AI <ArrowUpRight size={12} /><span>本地新版</span></a>
      </div>
    </aside>
  );
}
