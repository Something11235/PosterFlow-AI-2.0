import React from "react";
import { ExternalLink, Sparkles } from "lucide-react";
import { SIFENG_MUSIC_PROMPT } from "../../lib/musicInspiration";
import { MUSIC_PROMPT_RESOURCE } from "../../lib/promptResources";

export default function MusicInspiration({ onChoose, onLoFi }) {
  return <div className="music-inspiration-actions">
    <div className="music-preset-actions">{onLoFi && <button type="button" className="studio-example" onClick={onLoFi}><Sparkles size={14} />试试深夜 Lo-fi 灵感</button>}<button type="button" className="studio-example" onClick={() => onChoose(SIFENG_MUSIC_PROMPT)}><Sparkles size={14} />司凤版音乐</button></div>
    <a className="music-prompt-resource" href={MUSIC_PROMPT_RESOURCE.href} target="_blank" rel="noopener noreferrer">{MUSIC_PROMPT_RESOURCE.label}<ExternalLink size={14} aria-hidden="true" /></a>
  </div>;
}
