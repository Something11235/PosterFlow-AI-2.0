import assert from "node:assert/strict";
import test from "node:test";
import { buildMusicParameters, defaultFlow, defaultSuno, downloadMusic, FLOW_VERSIONS, musicApi, musicShouldPoll, readMusicSession, saveMusicSession, SUNO_VERSIONS } from "../src/lib/music.js";

test("all five selected versions build the intended model and version", () => {
  for (const version of SUNO_VERSIONS) assert.equal(buildMusicParameters({ ...defaultSuno(), version, prompt: "钢琴" }).version, version);
  for (const { value: version } of FLOW_VERSIONS) assert.equal(buildMusicParameters({ ...defaultFlow(), version, lyrics: "歌词" }).version, version);
});
test("automatic duration is omitted for both models while explicit values are validated", () => {
  const suno = { ...defaultSuno(), custom: true, instrumental: true };
  const flow = { ...defaultFlow(), sound_prompt: "钢琴" };
  assert.equal(Object.hasOwn(buildMusicParameters(suno), "duration"), false);
  assert.equal(Object.hasOwn(buildMusicParameters(flow), "length"), false);
  assert.equal(buildMusicParameters({ ...suno, duration: "360" }).duration, 360);
  assert.equal(buildMusicParameters({ ...flow, length: "240" }).length, 240);
  assert.throws(() => buildMusicParameters({ ...suno, duration: "9" }));
  assert.throws(() => buildMusicParameters({ ...flow, length: "1.5" }));
});
test("custom models require custom mode and omit a blank optional version", () => {
  const values = { ...defaultSuno(), model: "custom", custom_model: "provider/music-v9", parameter_format: "suno", prompt: "钢琴" };
  assert.throws(() => buildMusicParameters(values));
  const body = buildMusicParameters(values, { allowCustom: true });
  assert.equal(body.model, "provider/music-v9");
  assert.equal(body.parameter_format, "suno");
  assert.equal(Object.hasOwn(body, "version"), false);
  assert.equal(buildMusicParameters({ ...values, custom_version: "v9" }, { allowCustom: true }).version, "v9");
});
test("switching custom parameter families excludes fields from the other protocol", () => {
  const body = buildMusicParameters({ ...defaultSuno(), ...defaultFlow(), model: "custom", custom_model: "model-v3", parameter_format: "flowmusic", sound_prompt: "爵士", prompt: "private lyrics", style: "private style" }, { allowCustom: true });
  assert.equal(body.sound_prompt, "爵士");
  assert.equal(Object.hasOwn(body, "prompt"), false);
  assert.equal(Object.hasOwn(body, "style"), false);
});
test("generation bodies never contain credentials, endpoints or unrecognized options", () => {
  const body = buildMusicParameters({ ...defaultSuno(), prompt: "钢琴", apiKey: "SECRET", endpoint: "https://secret.invalid", authHeaders: { Authorization: "SECRET" }, max_mode: true });
  assert.equal(JSON.stringify(body).includes("SECRET"), false);
  assert.equal(Object.hasOwn(body, "max_mode"), false);
});
test("inspiration mode excludes retained custom-only fields", () => {
  const body = buildMusicParameters({ ...defaultSuno(), prompt: "钢琴", title: "标题", style: "jazz", duration: "200", negative_tags: "metal", auto_lyrics: true });
  for (const key of ["title", "style", "duration", "negative_tags", "auto_lyrics"]) assert.equal(Object.hasOwn(body, key), false);
});
test("zero weights and Unicode limits retain their actual meaning", () => {
  assert.equal(buildMusicParameters({ ...defaultSuno(), prompt: "🎵".repeat(3000), weirdness_constraint: 0 }).weirdness_constraint, 0);
  assert.throws(() => buildMusicParameters({ ...defaultSuno(), prompt: "🎵".repeat(3001) }));
  assert.throws(() => buildMusicParameters({ ...defaultSuno(), prompt: "钢琴", audio_weight: 2 }));
});
test("Flow requires description or lyrics and retains BPM as a string", () => {
  assert.throws(() => buildMusicParameters(defaultFlow()));
  const body = buildMusicParameters({ ...defaultFlow(), lyrics: "歌词", bpm: "120" });
  assert.equal(body.bpm, "120");
  assert.equal(Object.hasOwn(body, "prompt"), false);
});
test("only known active provider tasks are polled", () => {
  for (const status of ["submitted", "pending", "processing"]) assert.equal(musicShouldPoll({ status, provider_task_id: "task_1" }), true);
  for (const status of ["completed", "failed", "unknown", "submission_unknown"]) assert.equal(musicShouldPoll({ status, provider_task_id: "task_1" }), false);
  assert.equal(musicShouldPoll({ status: "submitting" }), false);
});
test("music credentials are session-only and namespaced by identity", () => {
  const data = new Map();
  globalThis.sessionStorage = { getItem: key => data.get(key), setItem: (key, value) => data.set(key, value), removeItem: key => data.delete(key) };
  assert.equal(saveMusicSession("user-a", "key", "secret"), true);
  assert.equal(readMusicSession("user-a", "key"), "secret");
  assert.equal(readMusicSession("user-b", "key"), "");
  saveMusicSession("user-a", "key", "");
  assert.equal(readMusicSession("user-a", "key"), "");
  delete globalThis.sessionStorage;
});
test("blocked storage degrades safely", () => {
  globalThis.sessionStorage = { getItem() { throw new Error("blocked"); }, setItem() { throw new Error("blocked"); } };
  assert.equal(readMusicSession("guest", "key"), "");
  assert.equal(saveMusicSession("guest", "key", "secret"), false);
  delete globalThis.sessionStorage;
});
test("platform requests ignore custom endpoint and key settings", async () => {
  const original = globalThis.fetch;
  let received;
  globalThis.fetch = async (url, options) => { received = { url, options }; return { ok: true, json: async () => ({ success: true }) }; };
  try {
    await musicApi("/generations", { mode: "platform", key: "own-secret", endpoint: "https://custom.invalid", body: { request_id: "id", parameters: { prompt: "钢琴" } } });
    assert.equal(received.url, "/api/music/generations");
    assert.equal(received.options.headers["X-Music-Api-Key"], undefined);
    assert.equal(received.options.headers["X-Music-Endpoint"], undefined);
  } finally { globalThis.fetch = original; }
});
test("custom requests transmit provider credentials only to the local backend", async () => {
  const original = globalThis.fetch;
  let received;
  globalThis.fetch = async (url, options) => { received = { url, options }; return { ok: true, json: async () => ({ success: true }) }; };
  try {
    await musicApi("/tasks", { mode: "own_key", key: "own-secret", endpoint: "https://custom.invalid/generate", queryTemplate: "https://custom.invalid/tasks/{task_id}", authType: "x-api-key" });
    assert.equal(received.url, "/api/music/tasks");
    assert.equal(received.options.headers["X-Music-Api-Key"], "own-secret");
    assert.equal(received.options.headers["X-Music-Auth-Type"], "x-api-key");
    assert.equal(received.options.credentials, "include");
  } finally { globalThis.fetch = original; }
});
test("API transport does not automatically retry a paid submission", async () => {
  const original = globalThis.fetch;
  let count = 0;
  globalThis.fetch = async () => { count += 1; throw new TypeError("offline"); };
  try { await assert.rejects(musicApi("/generations", { body: {} })); assert.equal(count, 1); }
  finally { globalThis.fetch = original; }
});
test("media downloads never transmit credentials and reject HTML instead of saving it", async () => {
  const original = globalThis.fetch;
  let options;
  globalThis.fetch = async (_url, opts) => { options = opts; return { ok: true, body: {}, headers: new Headers({ "content-type": "text/html" }) }; };
  try {
    await assert.rejects(downloadMusic("https://cdn.invalid/audio", "test"), /没有返回音频/);
    assert.equal(options.credentials, "omit");
    assert.equal(options.referrerPolicy, "no-referrer");
    assert.equal(options.headers, undefined);
  } finally { globalThis.fetch = original; }
});
