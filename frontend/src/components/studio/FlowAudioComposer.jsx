import React from "react";
import MusicAudioReferences from "./MusicAudioReferences";
import MusicInspiration from "./MusicInspiration";

export default function FlowAudioComposer({ values, onChange, audio, canUpload, onLogin }) {
  const update = patch => onChange(previous => ({ ...previous, ...patch }));
  return <section className="music-audio-composer" aria-label="Flow 音频改编设置">
    <MusicAudioReferences limit={1} audio={audio} canUpload={canUpload} onLogin={onLogin} description="选择 1 段音频，改编成另一种风格" />
    <p className="music-config-note">以这段音频为改编对象，描述希望改变的曲风、乐器或氛围。平台模式下导入和改编属于同一次任务，成功共 2 积分；自带 Key 不扣网站积分。</p>
    <label className="studio-field"><span>改编描述</span><textarea aria-label="Flow 改编描述" rows={5} maxLength={3000} value={values.prompt || ""} onChange={event => update({ prompt: event.target.value })} placeholder="例如：改成轻快爵士，保留旋律走向，突出钢琴与低音提琴…" /></label>
    <MusicInspiration onChoose={prompt => update({ prompt })} />
    <label className="studio-field"><span>改编强度 · {Math.round(Number(values.strength === "" || values.strength == null ? .5 : values.strength) * 100)}%</span><input aria-label="改编强度" type="range" min="0" max="1" step="0.05" value={values.strength === "" || values.strength == null ? .5 : values.strength} onChange={event => update({ strength: event.target.value })} /><small>越高改动越大；先从 50% 开始，再按试听效果调整。</small></label>
    <label className="studio-field"><span>歌曲标题（可选）</span><input aria-label="Flow 改编歌曲标题" maxLength={200} value={values.title || ""} onChange={event => update({ title: event.target.value })} /></label>
  </section>;
}
