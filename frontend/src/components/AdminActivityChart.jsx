import React, { useState } from "react";

export default function AdminActivityChart({ days=[],error }) {
  const [selectedDate,setSelectedDate]=useState("");
  const selected=days.find(day=>day.stat_date===selectedDate)||days.at(-1);
  const max=Math.max(1,...days.map(day=>Number(day.active_users)||0));
  const x=i=>44+(days.length<=1?277:i*554/(days.length-1));
  const y=value=>168-Number(value||0)/max*142;
  const d=days.map((day,i)=>`${i?"L":"M"}${x(i)},${y(day.active_users)}`).join(" ");
  const ticks=[...new Set([0,Math.floor(max/2),max])];
  return <section aria-label="每日活跃用户" className="rounded-lg border border-border-subtle bg-bg-primary/50 p-4">
    <div className="flex flex-wrap items-center justify-between gap-2"><h4 className="text-sm font-medium text-text-primary">每日活跃用户</h4><span className="text-xs text-text-muted">图像 + 音乐 + 视频 · 账号去重 · 北京时间</span></div>
    {error?<p role="alert" className="mt-4 text-xs text-gold">{error}</p>:days.length>0?<><svg viewBox="0 0 632 204" role="img" aria-label="每日活跃用户折线图，人数从零开始" className="mt-3 w-full">
      {ticks.map(value=><g key={value}><line x1="44" x2="598" y1={y(value)} y2={y(value)} stroke="#243142" strokeDasharray="3 5" /><text x="37" y={y(value)+4} textAnchor="end" fill="#8796aa" fontSize="10">{value}</text></g>)}
      <path d={d} fill="none" stroke="#4f8cff" strokeWidth="2.5" strokeLinejoin="round" />
      {days.map((day,i)=><g key={day.stat_date}><circle cx={x(i)} cy={y(day.active_users)} r={selected?.stat_date===day.stat_date?4:2.5} fill="#4f8cff" /><rect x={x(i)-Math.min(12,277/Math.max(1,days.length-1))} y="20" width={Math.min(24,554/Math.max(1,days.length-1))} height="156" fill="transparent" role="button" tabIndex="0" aria-label={`${day.stat_date} 活跃 ${day.active_users} 人`} onMouseEnter={()=>setSelectedDate(day.stat_date)} onFocus={()=>setSelectedDate(day.stat_date)} onClick={()=>setSelectedDate(day.stat_date)} onKeyDown={event=>{if(event.key==="Enter"||event.key===" "){event.preventDefault();setSelectedDate(day.stat_date);}}} /></g>)}
      {[0,Math.floor((days.length-1)/2),days.length-1].filter((v,i,a)=>v>=0&&a.indexOf(v)===i).map(i=><text key={i} x={x(i)} y="196" textAnchor="middle" fill="#8796aa" fontSize="11">{days[i]?.stat_date.slice(5)}</text>)}
    </svg><p aria-live="polite" className="text-xs text-text-secondary">{selected?.stat_date} · 活跃 {selected?.active_users} 人 · 生图 {selected?.image_active_users} 人 · 音乐 {selected?.music_active_users} 人 · 视频 {selected?.video_active_users || 0} 人</p></>:<p className="py-8 text-center text-xs text-text-muted">加载后显示活跃趋势</p>}
    <p className="mt-3 text-xs leading-5 text-text-muted">当天建立过图片、音乐或视频生成任务的已登录账号计为活跃，成功、失败、进行中均计入。同一账号每天只算一人；仅浏览、登录和游客不计入。各创作类型人数可能重叠；素材上传与审核不计入。</p>
  </section>;
}
