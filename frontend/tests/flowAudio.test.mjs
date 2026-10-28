import assert from "node:assert/strict";
import test from "node:test";
import { buildAudioOperationParameters, musicOperations } from "../src/lib/musicReferences.js";
import { defaultFlow } from "../src/lib/music.js";
import { buildStudioDraft } from "../src/lib/studioCatalog.js";
import { musicHistorySnapshot, restoreMusicHistory } from "../src/lib/musicHistory.js";

test("Flow cover excludes unrelated text-generation fields and preserves zero strength", () => {
  const values={...defaultFlow(),operation:"flow_cover",prompt:" jazz ",strength:"0",lyrics:"must not leak",sound_prompt:"other mode",audio_url:"secret"};
  assert.deepEqual(buildAudioOperationParameters(values,"flow_cover"),{model:"flowmusic",version:"lyria-3-pro",prompt:"jazz",strength:0});
  for(const strength of ["-1","1.5","bad",Infinity]) assert.throws(()=>buildAudioOperationParameters({...values,strength},"flow_cover"));
  assert.throws(()=>buildAudioOperationParameters({...values,prompt:""},"flow_cover"));
});
test("Flow exposes only documented single-audio cover and text creation", () => {
  assert.deepEqual(musicOperations("flowmusic"),["generate","flow_cover"]);
  assert.deepEqual(musicOperations("suno"),["generate","inspo","upload_cover"]);
  assert.deepEqual(musicOperations("custom"),["generate"]);
});
test("Flow cover drafts and history restore the operation without source audio or credentials", () => {
  const values={...defaultFlow(),operation:"flow_cover",prompt:"jazz",strength:"0.75",version:"lyria-3.5",api_key:"secret",references:["secret"]};
  const draft=buildStudioDraft("music",values);
  assert.equal(draft.endpoint,"/api/music/operations/flow_cover");assert.equal(draft.body.strength,.75);assert.match(draft.note,/重新添加/);
  assert.equal(JSON.stringify(draft).includes("secret"),false);
  const restored=restoreMusicHistory(musicHistorySnapshot(values));
  assert.equal(restored.model,"flowmusic");assert.equal(restored.operation,"flow_cover");assert.equal(restored.prompt,"jazz");assert.equal(restored.strength,"0.75");
  assert.equal(JSON.stringify(restored).includes("secret"),false);
});
