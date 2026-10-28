import assert from "node:assert/strict";
import test from "node:test";
import { musicJobCost } from "../src/lib/music.js";
import { musicHistorySnapshot, restoreMusicHistory } from "../src/lib/musicHistory.js";
import { cleanPromptHistory, HISTORY_WINDOW_MS } from "../src/lib/promptHistory.js";

test("request pricing is two credits regardless of track count; historical charges remain visible", () => {
  for (const generated_count of [1,2,3,64]) assert.equal(musicJobCost({ billing_mode:"platform",billing_unit:"request",credits_per_request:2,generated_count }),2);
  assert.equal(musicJobCost({billing_mode:"own_key",billing_unit:"request",credits_per_request:2,generated_count:2}),0);
  assert.equal(musicJobCost({billing_mode:"platform",billing_unit:"song",charged_credits:4,generated_count:2}),4);
});

test("music history retains both Flow text inputs but excludes service and media credentials", () => {
  const item=musicHistorySnapshot({model:"flowmusic",version:"lyria-3.5",sound_prompt:"爵士",lyrics:"歌词",api_key:"private-secret",endpoint:"https://private.invalid",audio_url:"https://private.invalid/a"});
  assert.match(item.prompt,/爵士/);assert.match(item.prompt,/歌词/);
  assert.equal(JSON.stringify(item).includes("private"),false);
  const restored=restoreMusicHistory(item);
  assert.equal(restored.model,"flowmusic");assert.equal(restored.lyrics,"歌词");assert.equal(restored.sound_prompt,"爵士");assert.equal(restored.version,"lyria-3.5");
});

test("long music text respects seven-day expiry and preserves Unicode with safe parameter fields", () => {
  const now=Date.now();
  const item={id:"music",created_at:new Date(now).toISOString(),...musicHistorySnapshot({model:"flowmusic",sound_prompt:"🎵".repeat(6000),lyrics:"字".repeat(6000)})};
  assert.equal(cleanPromptHistory([item],now).length,1);
  assert.equal(cleanPromptHistory([item],now+HISTORY_WINDOW_MS).length,0);
  const copy=cleanPromptHistory([{...item,parameters:{...item.parameters,key:"private"}}],now)[0];
  assert.equal(copy.parameters.key,undefined);
});

test("Suno custom lyrics restore correctly; custom providers restore into their matching text form", () => {
  const restored=restoreMusicHistory(musicHistorySnapshot({model:"suno",version:"v6-mini",custom:true,instrumental:false,prompt:"[Verse]\n歌词"}));
  assert.equal(restored.custom,true);assert.equal(restored.instrumental,false);assert.equal(restored.prompt,"[Verse]\n歌词");
  const custom=restoreMusicHistory(musicHistorySnapshot({model:"private-model",parameter_format:"flowmusic",lyrics:"歌词",version:"provider-v9"}));
  assert.equal(custom.model,"flowmusic");assert.equal(custom.version,"lyria-3-pro");assert.equal(custom.lyrics,"歌词");
});
