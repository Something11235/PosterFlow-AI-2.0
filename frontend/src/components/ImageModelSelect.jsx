import React, { useId } from "react";
import { IMAGE_MODEL_OPTIONS, imageCreditCost, imagePricingLabel } from "../lib/provider";

const DISPLAY_NAMES = {
  "gpt-image-2.5-flare": "GPT Image 2.5 Flare",
  "gpt-image-2.5-sunburst": "GPT Image 2.5 Sunburst",
  "gpt-image-2": "GPT Image 2",
};

export default function ImageModelSelect({ model = "", billingMode = "platform", onModelChange, onOpenProvider, disabled = false, referenceCount = 0 }) {
  const id = useId();
  const customModel = model && !IMAGE_MODEL_OPTIONS.some(option => option.value === model);
  return <div className="mb-4 rounded-lg border border-border-subtle bg-bg-primary/40 p-3">
    <div className="mb-2 flex items-center justify-between gap-2">
      <label htmlFor={id} className="text-sm font-medium text-text-secondary">图片模型</label>
      <button type="button" onClick={onOpenProvider} className="min-h-8 rounded px-1 text-xs text-accent hover:text-accent-hover">服务设置</button>
    </div>
    <select id={id} value={model} onChange={event => onModelChange?.(event.target.value)} disabled={disabled}
      className="min-h-11 w-full min-w-0 rounded-lg border border-border-default bg-bg-primary px-3 text-base text-text-primary focus:border-accent/65 disabled:opacity-50">
      {!model && <option value="" disabled>请选择模型</option>}
      {customModel && <option value={model}>{model}</option>}
      {IMAGE_MODEL_OPTIONS.map(option => <option key={option.value} value={option.value}>{DISPLAY_NAMES[option.value] || option.label}</option>)}
    </select>
    <p className="mt-2 text-xs text-text-muted">{billingMode === "platform" ? "平台积分" : "自带 API Key"}</p>
    {model === "gemini-nano-banana-2.1" && billingMode === "platform" && <p className="mt-2 text-xs leading-5 text-text-muted">{imagePricingLabel(model)}。</p>}
    {model === "grok-imagine-image-2.0" && <p className="mt-2 text-xs leading-5 text-text-muted" aria-live="polite">{billingMode === "platform" ? `${referenceCount > 0 ? "参考图编辑" : "纯文生图"} · ${imageCreditCost(model, referenceCount)} 积分 / 张。` : "支持文字生成与参考图编辑。"}最多 3 张参考图。</p>}
  </div>;
}
