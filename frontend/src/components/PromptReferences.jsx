import React from "react";
import { BookOpen, ChevronDown, ExternalLink } from "lucide-react";

const LINKS = [
  { label: "GPT Image 2 提示词库", href: "https://gpt-image2.canghe.ai/" },
  { label: "GPT Image 2 灵感社区", href: "https://awesome.gptimage2.asia/" },
];

export default function PromptReferences() {
  return <details className="studio-prompt-library">
    <summary><BookOpen size={18} aria-hidden="true" /><span>创作灵感</span><ChevronDown size={14} className="studio-prompt-chevron" aria-hidden="true" /></summary>
    <div>{LINKS.map(link => <a key={link.href} href={link.href} target="_blank" rel="noopener noreferrer"><span>{link.label}</span><ExternalLink size={14} aria-hidden="true" /></a>)}</div>
  </details>;
}
