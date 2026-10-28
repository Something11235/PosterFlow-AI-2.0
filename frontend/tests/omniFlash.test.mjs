import test from 'node:test';
import assert from 'node:assert/strict';
import {OMNI_FLASH,defaultOmniFlash} from '../src/lib/omniFlash.js';
import {buildVideoParameters,videoQuote,videoReferenceInput,restoreVideoHistory,videoFile,validateVideoReferenceDuration} from '../src/lib/video.js';
import {VIDEO_MODELS} from '../src/lib/studioCatalog.js';

test('Omni has its own payload/history whitelist and exact maximum-output estimates',()=>{
 const base=defaultOmniFlash();
 for(const [resolution,estimated,reserved] of [['360p','7','10.5'],['720p','19.5','31.5'],['1080p','29.5','47'],['4k','58.5','93.5']]){
  const value={...base,resolution,prompt:'fixture',duration:15,size:'adaptive',seed:42,nsfw_check:true,web_search:true,generate_audio:false};
  const body=buildVideoParameters(value);assert.deepEqual(Object.keys(body).sort(),['model','prompt','resolution','aspect_ratio','task'].sort());
  assert.equal(videoQuote(value).text,estimated);assert.equal(videoQuote(value).reservedText,reserved);
  assert.equal(restoreVideoHistory({parameters:body}).model,OMNI_FLASH);
 }
 const continued=buildVideoParameters({...base,continue_request_id:'11111111-1111-4111-8111-111111111111',task:'extend'});
 assert.deepEqual(buildVideoParameters(restoreVideoHistory({parameters:continued})),continued);
 assert.equal(VIDEO_MODELS.filter(m=>m.available)[4].id,OMNI_FLASH);
 assert.throws(()=>buildVideoParameters({...base,resolution:'480p'}));
});
test('Omni rejects audio, unsupported approved assets, missing first frame, and long video without dropping materials',()=>{
 const ready=(kind,id,extra={})=>({id,kind,state:'ready',reference:{id,kind,receipt:'proof-'+id,width:128,height:256,duration_ms:3000,...extra}});
 const first={...ready('image','first'),role:'first_frame'},last={...ready('image','last'),role:'last_frame'},ref=ready('image','reference');
 assert.deepEqual(videoReferenceInput([first,ref,last],'unified',OMNI_FLASH),[{receipt:'proof-first',role:'first_frame'},{receipt:'proof-reference'},{receipt:'proof-last',role:'last_frame'}]);
 const invalid=[[last],[ready('audio','a')],[ready('video','v',{duration_ms:10001})],[ready('image','a',{asset_url:'asset://owned'})],Array.from({length:11},(_,i)=>ready('image',String(i)))];
 for(const items of invalid)assert.throws(()=>videoReferenceInput(items,'unified',OMNI_FLASH));
 assert.throws(()=>videoFile({name:'a.mp3',size:10},OMNI_FLASH),/不支持参考音频/);
 validateVideoReferenceDuration(.5,OMNI_FLASH);validateVideoReferenceDuration(10,OMNI_FLASH);assert.throws(()=>validateVideoReferenceDuration(10.001,OMNI_FLASH));
});
