import test from 'node:test';
import assert from 'node:assert/strict';
import {appendVideoReference,setVideoFrameRole,buildVideoParameters,defaultVideo,videoQuote,videoReferenceInput,restoreVideoHistory,videoApi,validateVideoImageDimensions,validateVideoReferenceDuration,uploadVideoReference} from '../src/lib/video.js';
import {buildStudioDraft} from '../src/lib/studioCatalog.js';
import {cleanPromptHistory} from '../src/lib/promptHistory.js';

const ready=(kind,id,extra={})=>({id,state:'ready',reference:{id,kind,...kind==='image'?{width:512,height:512}:{},receipt:'owner-proof-'+id,...extra}});
test('video quote counts only video milliseconds with exact half-credit pricing',()=>{
  const values={...defaultVideo(),duration:10};
  const refs=[{kind:'video',duration_ms:5000},{kind:'audio',duration_ms:3000},{kind:'image'}];
  assert.equal(videoQuote(values,refs).text,'7.5');assert.equal(videoQuote({...values,resolution:'720p'},refs).text,'15');
  refs[0].duration_ms=5123;assert.equal(videoQuote(values,refs).text,'7.5615');
  assert.equal(videoQuote(defaultVideo()).text,'2.5');
});
test('all Mini controls and seed zero survive; drafts and restored history contain no references or credentials',()=>{
  const values={...defaultVideo(),seed:'0',prompt:'cinematic',generate_audio:false,return_last_frame:true,web_search:true,nsfw_check:true,api_key:'secret',references:['secret'],image_urls:['secret']};
  const body=buildVideoParameters(values);
  assert.equal(body.seed,0);assert.deepEqual(body.tools,[{type:'web_search'}]);assert.equal(body.generate_audio,false);
  const draft=buildStudioDraft('video',values);assert.equal(draft.body.model,'seedance-2.0-mini');assert.ok(!JSON.stringify(draft).includes('secret'));
  const entry={id:'video-history',prompt:'cinematic',kind:'video',created_at:new Date().toISOString(),parameters:values,preview_count:1,preview_expires_at:new Date(Date.now()+3600000).toISOString()};
  const clean=cleanPromptHistory([entry])[0];assert.equal(clean.kind,'video');assert.equal(clean.preview_count,undefined);assert.ok(!JSON.stringify(clean).includes('secret'));
  assert.equal(restoreVideoHistory(clean).seed,0);
  assert.throws(()=>buildVideoParameters({...values,model:'minimax-h3'}),/暂未开放/);
});
test('reference rules block incompatible modes without dropping any selected item',()=>{
  const mixed=[ready('image','i'),ready('video','v',{duration_ms:5000}),ready('audio','a',{duration_ms:3000})];
  assert.equal(videoReferenceInput(mixed,'reference').length,3);
  assert.throws(()=>videoReferenceInput(mixed,'frames'),/首尾帧/);assert.equal(mixed.length,3);
  assert.throws(()=>videoReferenceInput([ready('audio','a',{duration_ms:3000})],'reference'),/搭配/);
  assert.throws(()=>videoReferenceInput([ready('image','i')],'portrait'),/审核/);
  const approved=[ready('image','i',{asset_url:'asset://owner_asset_001'})];
  assert.deepEqual(videoReferenceInput(approved,'portrait'),[{asset_url:'asset://owner_asset_001',role:'reference_image'}]);
  assert.throws(()=>videoReferenceInput([...mixed,{state:'uploading'}],'reference'),/校验/);
});

test('video image and audio bounds block malformed references before issuing any upload or paid request',async()=>{
 for(const size of [[299,600],[600,299],[6001,600],[300,751]])assert.throws(()=>validateVideoImageDimensions(...size),/参考图片/);
 for(const size of [[300,300],[300,750],[750,300],[6000,2400]])assert.doesNotThrow(()=>validateVideoImageDimensions(...size));
 for(const duration of [1,1.799,1.999,15.001,NaN,Infinity])assert.throws(()=>validateVideoReferenceDuration(duration),/每段须为/);
 for(const duration of [2,15])assert.doesNotThrow(()=>validateVideoReferenceDuration(duration));
 assert.doesNotThrow(()=>validateVideoReferenceDuration(30,'seedance-2.5'));
 assert.throws(()=>validateVideoReferenceDuration(30.001,'seedance-2.5'),/2–30/);
 const originalFetch=globalThis.fetch, originalBitmap=globalThis.createImageBitmap;let calls=0,closed=false;
 globalThis.fetch=async()=>{calls++;throw new Error('must not call');};
 globalThis.createImageBitmap=async()=>({width:200,height:400,close(){closed=true;}});
 try{await assert.rejects(uploadVideoReference({name:'too-small.png',size:100},{model:'seedance-2.0-mini'}),/200 × 400/);assert.equal(calls,0);assert.equal(closed,true);}
 finally{globalThis.fetch=originalFetch;globalThis.createImageBitmap=originalBitmap;}
});
test('a rejected or uncertain video API request never submits again automatically',async()=>{
  const original=globalThis.fetch;const calls=[];
  globalThis.fetch=async(...args)=>{calls.push(args);return new Response(JSON.stringify({code:'VIDEO_QUERY_UNAVAILABLE',error:'查询暂不可用'}),{status:502});};
  try{await assert.rejects(videoApi('/tasks/fixture',{mode:'own_key',key:'fixture-key',authHeaders:{Authorization:'Bearer account'}}),/查询暂不可用/);assert.equal(calls.length,1);assert.equal(calls[0][1].method,'GET');}
  finally{globalThis.fetch=original;}
});

test('frame uploads receive distinct roles before completion and manual changes swap the pair without changing file order',()=>{
  let items=appendVideoReference([], {...ready('image','a'),kind:'image'});
  items=appendVideoReference(items,{...ready('image','b'),kind:'image'});
  assert.deepEqual(items.map(i=>i.role),['first_frame','last_frame']);
  const swapped=setVideoFrameRole(items,'a','last_frame');
  assert.deepEqual(swapped.map(i=>i.id),['a','b']);
  assert.deepEqual(swapped.map(i=>i.role),['last_frame','first_frame']);
  assert.deepEqual(items.map(i=>i.role),['first_frame','last_frame']);
  assert.deepEqual(videoReferenceInput(swapped,'frames'),[{receipt:'owner-proof-a',role:'last_frame'},{receipt:'owner-proof-b',role:'first_frame'}]);
  const replacement=appendVideoReference(swapped.filter(i=>i.id!=='b'),{...ready('image','c'),kind:'image'});
  assert.deepEqual(replacement.map(i=>i.role),['last_frame','first_frame']);
});
