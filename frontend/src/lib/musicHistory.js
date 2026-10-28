import { defaultFlow, defaultSuno, FLOW_VERSIONS, SUNO_VERSIONS } from "./music.js";

const fields = new Set(["model", "version", "parameter_format", "custom", "instrumental", "prompt", "sound_prompt", "lyrics", "title", "style", "negative_tags", "operation", "strength"]);
export function cleanMusicHistoryParameters(parameters) {
  if (!parameters || typeof parameters !== "object" || Array.isArray(parameters)) return {};
  return Object.fromEntries(Object.entries(parameters).filter(([key, value]) => fields.has(key) &&
    (typeof value === "boolean" || (typeof value === "string" && Array.from(value).length <= 6000))));
}

export function musicHistorySnapshot(parameters) {
  const clean = cleanMusicHistoryParameters(parameters);
  const labels = [["title", "标题"], ["prompt", "描述或歌词"], ["sound_prompt", "音乐描述"], ["lyrics", "歌词"], ["style", "风格"], ["negative_tags", "排除风格"]];
  const operation = { inspo: "参考音频创作", upload_cover: "音频改编", flow_cover: "Flow 音频改编" }[clean.operation];
  return { kind: "music", parameters: clean, prompt: [operation, ...labels.filter(([key]) => clean[key]).map(([key, label]) => `${label}：${clean[key]}`)].filter(Boolean).join("\n\n") || "纯音乐" };
}

export function restoreMusicHistory(item) {
  const parameters = cleanMusicHistoryParameters(item?.parameters);
  const flow = parameters.model === "flowmusic" || parameters.parameter_format === "flowmusic";
  const base = flow ? defaultFlow() : defaultSuno();
  const versions = flow ? FLOW_VERSIONS.map(v => v.value) : SUNO_VERSIONS;
  // Restore the text and basic form values; provider endpoints and keys never
  // enter history. Custom provider models require the user to select them again.
  return { ...base, ...parameters, model: base.model,
    version: versions.includes(parameters.version) ? parameters.version : base.version };
}
