import React from "react";
import MusicAudioReferences from "./MusicAudioReferences";
import MusicInspiration from "./MusicInspiration";

function Field({ label, children, hint }) {
  const control = typeof children.type === "string" ? React.cloneElement(children, { "aria-label": children.props["aria-label"] || label, "aria-description": hint }) : children;
  return <label className="studio-field"><span>{label}</span>{control}{hint && <small>{hint}</small>}</label>;
}
export default function SunoAudioComposer({ operation, values, onChange, audio, canUpload, onLogin }) {
  const custom = operation === "inspo" || values.custom, limit = operation === "inspo" ? 4 : 1;
  const update = patch => onChange(previous => ({ ...previous, ...patch }));
  return <section className="music-audio-composer" aria-label="音频素材与创作设置">
    <MusicAudioReferences limit={limit} description={operation === "inspo" ? "用 1–4 段音频启发新作品" : "选择 1 段音频，改编成另一种风格"} audio={audio} canUpload={canUpload} onLogin={onLogin} />
    <p className="music-config-note">{operation === "inspo" ? "借鉴素材的旋律、节奏或氛围，创作一首新歌；可以结合多段音频提供灵感。" : "以这段音频为改编对象，生成翻唱或另一种风格的版本；可描述改编方向，或选择自定义歌词。"}</p>
    {operation === "upload_cover" && <div className="studio-segments" aria-label="音频改编模式"><button type="button" aria-pressed={!values.custom} onClick={() => update({ custom: false })}>描述改编方向</button><button type="button" aria-pressed={values.custom} onClick={() => update({ custom: true })}>自定义歌词</button></div>}
    <Field label={operation === "inspo" ? "内容或歌词（可选）" : custom ? values.instrumental ? "歌词（可选）" : "歌词（必填）" : "改编描述"}><textarea aria-label={operation === "inspo" ? "参考创作内容" : "改编内容"} rows={5} value={values.prompt} onChange={event => update({ prompt: event.target.value })} placeholder={operation === "inspo" ? "补充歌曲主题、歌词或想保留的特点…" : custom ? "写下改编后的歌词…" : "例如：改成轻快爵士，保留旋律走向，突出钢琴与低音提琴…"} /></Field>
    {!custom && <MusicInspiration onChoose={prompt => update({ prompt })} />}
    {custom && <><Field label="歌曲标题（可选）"><input value={values.title || ""} onChange={event => update({ title: event.target.value })} /></Field><Field label="音乐风格（可选）"><textarea rows={2} value={values.style || ""} onChange={event => update({ style: event.target.value })} placeholder="例如：ambient、原声吉他、温暖女声" /></Field><MusicInspiration onChoose={style => update({ style })} /></>}
    {operation === "upload_cover" && <label className="studio-toggle"><span><strong>纯音乐</strong><small>开启后生成无人声改编</small></span><input type="checkbox" checked={values.instrumental} onChange={event => update({ instrumental: event.target.checked })} /><span className="studio-switch" aria-hidden="true" /></label>}
    <details className="music-advanced"><summary>更多音频创作参数</summary><div className="music-advanced-body">
      {custom && <><Field label="排除风格（可选）"><input value={values.negative_tags || ""} onChange={event => update({ negative_tags: event.target.value })} /></Field><Field label="人声"><select value={values.vocal_gender || ""} onChange={event => update({ vocal_gender: event.target.value })}><option value="">自动</option><option value="Female">女声</option><option value="Male">男声</option></select></Field>
        {[["style_weight", "风格权重"], ["weirdness_constraint", "创意度"], ["audio_weight", "音频参考强度"]].map(([key, label]) => <Field key={key} label={label} hint="0–1；留空使用默认值。"><input type="number" min="0" max="1" step="0.01" value={values[key] ?? ""} onChange={event => update({ [key]: event.target.value })} /></Field>)}
        <label className="music-check"><input type="checkbox" checked={Boolean(values.auto_lyrics)} onChange={event => update({ auto_lyrics: event.target.checked })} />允许模型润色歌词</label>
        {operation === "upload_cover" && <Field label="目标时长（秒）"><input type="number" min="10" max="360" value={values.duration ?? ""} placeholder="自动" onChange={event => update({ duration: event.target.value })} /></Field>}</>}
      <Field label="风格变化" hint="从 off 到 max，变化程度逐档提高；自动使用服务默认值，不代表参考音频的保留比例。"><select value={values.variety || ""} onChange={event => update({ variety: event.target.value })}>{["", "off", "normal", "high", "extra", "max"].map(value => <option key={value} value={value}>{value || "自动"}</option>)}</select></Field>
      <Field label="音频格式"><select value={values.audio_format || ""} onChange={event => update({ audio_format: event.target.value })}>{["", "mp3", "m4a", "wav"].map(value => <option key={value} value={value}>{value || "自动"}</option>)}</select></Field>
    </div></details>
    {operation === "inspo" && <p className="music-reference-note">参考音频用于启发旋律、节奏和风格；新作品与原素材的细节可能不同。</p>}
  </section>;
}
