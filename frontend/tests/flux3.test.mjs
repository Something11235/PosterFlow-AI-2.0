import test from 'node:test';
import assert from 'node:assert/strict';
import {FLUX3,defaultFlux3,FLUX_RATIOS,moveFluxFrame} from '../src/lib/flux3.js';
import {buildVideoParameters,videoQuote,videoReferenceInput,videoFile,restoreVideoHistory,validateVideoReferenceDuration} from '../src/lib/video.js';
import {VIDEO_MODELS} from '../src/lib/studioCatalog.js';
const base=()=>({...defaultFlux3(),prompt:'镜头推进'}),image=(id='a.png')=>({id,kind:'image',width:128,height:128,size:1024,receipt:'proof-'+id});
const vid={id:'a.mp4',kind:'video',size:1024,width:854,height:480,duration_ms:3000,receipt:'proof-v'};
test('FLUX six rate estimates and supported parameters',()=>{
 for(const [workflow,resolution,refs,estimate,reserve] of [['draft','hd',[],'5.5','8.5'],['draft','hd',[vid],'11','17'],['generate','hd',[],'15.5','24.5'],['generate','fhd',[],'26','41.5'],['generate','hd',[vid],'36.5','58.5'],['generate','fhd',[vid],'47','75']]){const values={...base(),workflow,resolution};assert.equal(videoQuote(values,refs).text,estimate);assert.equal(videoQuote(values,refs).reservedText,reserve);assert.deepEqual(buildVideoParameters(restoreVideoHistory({parameters:buildVideoParameters(values)})),buildVideoParameters(values));}
 for(const aspect_ratio of FLUX_RATIOS)assert.equal(buildVideoParameters({...base(),aspect_ratio}).aspect_ratio,aspect_ratio);
 for(const patch of [{duration:4},{duration:21},{duration:'auto'},{duration:5.5},{safety_tolerance:5},{aspect_ratio:'adaptive'},{workflow:'draft',resolution:'fhd'}])assert.throws(()=>buildVideoParameters({...base(),...patch}));
 assert.equal(VIDEO_MODELS.filter(m=>m.available).at(-1).id,FLUX3);
});
test('ordered and repeated keyframes stay intact; incompatible media rejected',()=>{
 const refs=[image('z.png'),image('a.png'),image('z.png')],items=refs.map((r,i)=>({id:String(i),reference:r,kind:r.kind,state:'ready'}));
 assert.deepEqual(videoReferenceInput(items,'unified',FLUX3,base()),refs.map(r=>({receipt:r.receipt})));
 assert.deepEqual(moveFluxFrame(items,'1',-1).map(i=>i.id),['1','0','2']);assert.deepEqual(moveFluxFrame(items,'0',-1),items);
 assert.throws(()=>videoReferenceInput([...items,{id:'v',state:'ready',reference:vid}],'unified',FLUX3,base()));assert.throws(()=>videoReferenceInput(items.map(i=>({...i,role:'first_frame'})),'unified',FLUX3,base()));
 for(const name of ['sound.wav','video.mov','document.pdf'])assert.throws(()=>videoFile({name,size:1024},FLUX3));
 assert.equal(videoFile({name:'clip.mp4',size:1024},FLUX3),'video');validateVideoReferenceDuration(30,FLUX3);assert.throws(()=>validateVideoReferenceDuration(30.001,FLUX3));
});
test('draft finalization strips editable fields and prices the original mode',()=>{
 const source={model:FLUX3,is_draft:true,status:'completed',billing_status:'settled',requested_duration:5,pricing_profile:{continuation:true}};
 const values={...base(),workflow:'final',resolution:'fhd',draft_request_id:'11111111-1111-4111-8111-111111111111'};
 assert.deepEqual(Object.keys(buildVideoParameters(values)).sort(),['draft_request_id','model','resolution']);assert.equal(videoQuote(values,[],source).text,'47');assert.throws(()=>videoQuote(values,[],{...source,model:'seedance-2.5'}));
 assert.deepEqual(buildVideoParameters(restoreVideoHistory({parameters:buildVideoParameters(values)})),buildVideoParameters(values));
});
