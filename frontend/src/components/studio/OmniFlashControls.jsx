import React from 'react';
import {SlidersHorizontal} from 'lucide-react';

export function OmniTaskControls({values,onChange,jobs}){
  return <>
    <label className="studio-field"><span>视频创作方式</span><select aria-label="视频创作方式" value={values.task || 'auto'} onChange={e=>onChange({task:e.target.value})}>
      <option value="auto">自动判断</option><option value="text_to_video">文生视频</option><option value="image_to_video">图生视频</option><option value="reference_to_video">多主体参考创作</option><option value="edit">视频编辑</option><option value="extend">视频续写</option>
    </select><small>首尾帧由模型自动判断；编辑或续写需添加视频，或选择已完成任务。</small></label>
    <label className="studio-field"><span>继续已有 Omni 任务</span><select aria-label="继续已有 Omni 任务" value={values.continue_request_id || ''} onChange={e=>onChange({continue_request_id:e.target.value})}>
      <option value="">不使用 · 从提示词或上传素材开始</option>{jobs.map(j=><option key={j.request_id} value={j.request_id}>{new Date(j.created_at).toLocaleString('zh-CN',{hour12:false})} · {j.history_prompt?.slice(0,30) || j.request_id.slice(0,8)}</option>)}
    </select><small>只能引用本人已完成并结算的本型号任务；不能同时上传参考视频。每次编辑或续写均单独计费。</small></label>
  </>;
}

export default function OmniFlashControls({values,onChange}){
  return <section className="video-generation-controls video-composer-card" aria-label="视频生成参数">
    <h2 className="video-section-title"><SlidersHorizontal size={18} aria-hidden="true" />生成参数</h2>
    <fieldset className="video-ratios"><legend>画幅</legend><div role="group" aria-label="画幅">{['16:9','9:16'].map(ratio=><button type="button" className="video-ratio" key={ratio} aria-pressed={values.aspect_ratio===ratio} onClick={()=>onChange({aspect_ratio:ratio})}>{ratio}</button>)}</div><p className="music-reference-note">首尾帧建议使用相同比例，并与画幅一致；视频编辑时输出比例通常跟随源视频。</p></fieldset>
    <div className="video-duration-quality"><label className="studio-field"><span>清晰度</span><select aria-label="清晰度" value={values.resolution} onChange={e=>onChange({resolution:e.target.value})}>{['360p','720p','1080p','4k'].map(r=><option key={r} value={r}>{r.toUpperCase()}</option>)}</select></label>
      <div className="studio-field"><span>生成时长 · 自动</span><p className="music-reference-note">由模型决定，通常约 3–10 秒，输出 24 FPS 并包含声音；可在提示词中描述节奏和声音要求。</p></div>
    </div>
  </section>;
}
