import { buildMusicParameters, defaultSuno } from "./music.js";
// User-selected model roadmap. Candidate IDs are local UI identities, not
// verified provider identifiers or entitlements. No documentation links.
export const STUDIO_AREAS = [
  { id: "image", label: "图像创作", short: "图像", en: "IMAGE", description: "把灵感变成可见的画面", status: "已有功能", model: "GPT Image · Nano Banana · Grok", prompt: "一颗悬浮在深蓝色空间中的透明玻璃球，冰蓝色折射，极简产品摄影，柔和侧光。" },
  { id: "music", label: "音乐创作", short: "音乐", en: "MUSIC", description: "为想象写一段专属旋律", status: "创作与试听", model: "suno · flowmusic", prompt: "适合深夜工作时聆听的纯音乐，温暖的电钢琴、轻柔鼓点、模拟合成器，lo-fi 氛围。" },
  { id: "video", label: "视频创作", short: "视频", en: "VIDEO", description: "先选好模型，让故事等待启程", status: "模型预览", model: "Wan · Seedance · MiniMax", prompt: "" },
];

export const IMAGE_MODELS = [
  { id: "gpt-image-2.5-flare", name: "GPT Image 2.5 Flare", maker: "GPT Image", summary: "沿用现有图像工作区", available: true },
  { id: "gpt-image-2.5-sunburst", name: "GPT Image 2.5 Sunburst", maker: "GPT Image", summary: "沿用现有图像工作区", available: true },
  { id: "gpt-image-2", name: "GPT Image 2", maker: "GPT Image", summary: "沿用现有图像工作区", available: true },
  { id: "nano-banana-2.1", name: "Nano Banana 2.1", maker: "Nano Banana", summary: "新增图像模型 · 规划接入" },
  { id: "nano-banana-pro", name: "Nano Banana Pro", maker: "Nano Banana", summary: "新增图像模型 · 规划接入" },
  { id: "grok-imagine-image-2.0", name: "grok-imagine-image-2.0", maker: "Grok", summary: "新增图像模型 · 规划接入" },
  { id: "grok-imagine-2.0-ext", name: "grok-imagine-2.0-ext", maker: "Grok", summary: "新增图像模型 · 规划接入" },
];
export const MUSIC_MODELS = [
  { id: "suno", name: "suno", maker: "Suno", summary: "灵感成曲 · 自定义歌词 · 纯音乐", draftReady: true },
  { id: "flowmusic", name: "flowmusic", maker: "Flowmusic", summary: "Lyria 3 Pro · Lyria 3.5 · 风格与歌词成曲", draftReady: true },
];
export const VIDEO_MODELS = [
  { id: "wan3.0-video", name: "wan3.0-video", maker: "Wan" },
  { id: "seedance-2.5", name: "seedance-2.5", maker: "Seedance" },
  { id: "seedance-2.0", name: "seedance-2.0", maker: "Seedance" },
  { id: "minimax-h3", name: "MiniMax-H3", maker: "MiniMax" },
  { id: "minimax-h3-max", name: "MiniMax-H3-Max", maker: "MiniMax" },
];
export const MODEL_CATALOG = [
  ...IMAGE_MODELS.map(model => ({ ...model, area: "image" })),
  ...MUSIC_MODELS.map(model => ({ ...model, area: "music" })),
  ...VIDEO_MODELS.map(model => ({ ...model, area: "video", summary: "视频模型预览 · 暂未开放生成" })),
];
export const textLength = value => Array.from(String(value || "")).length;
export const defaultMusic = defaultSuno;

// Music drafts and real requests share the same field whitelist. Video stays preview-only.
export function buildStudioDraft(kind, values) {
  if (kind === "video") throw new Error("视频当前仅提供模型预览，暂未开放生成或参数草稿。");
  if (kind !== "music") throw new Error("不支持的草稿类型。");
  const body = buildMusicParameters(values, { allowCustom: true });
  const title = body.title || body.prompt || body.sound_prompt || body.lyrics || "未命名纯音乐";
  return { kind, title: Array.from(title).slice(0, 72).join(""), endpoint: "/v1/music/generations", encoding: "application/json", body };
}
