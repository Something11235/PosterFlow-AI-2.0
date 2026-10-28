import test from 'node:test';
import assert from 'node:assert/strict';
import {videoMentions,remapVideoMentions,videoMentionError,insertVideoMention} from '../src/lib/videoMentions.js';

test('references are numbered independently in the same per-type order as the submitted arrays',()=>{
 const items=[{id:'a',kind:'image'},{id:'v',kind:'video'},{id:'b',kind:'image'},{id:'u'},{id:'m',kind:'audio'}];
 assert.deepEqual(videoMentions(items).map(i=>i.token),['@图片1','@视频1','@图片2','@音频1']);
});
test('removing a reference renumbers exact tokens by identity, never redirects the removed reference to another file',()=>{
 const items=Array.from({length:10},(_,i)=>({id:String(i),kind:'image'}));
 const text='@图片2 模仿 @图片10；@图片1不变，@视频1也不变';
 const changed=remapVideoMentions(text,items,items.filter(i=>i.id!=='1'));
 assert.equal(changed,'【已移除图片2】 模仿 @图片9；@图片1不变，@视频1也不变');
 assert.match(videoMentionError(changed,items),/移除/);
 assert.match(videoMentionError('@音频1',items),/没有对应/);
 assert.equal(videoMentionError('@图片10',items),'');
});
test('an asynchronously identified earlier URL import preserves existing reference bindings',()=>{
 const before=[{id:'pending'},{id:'image',kind:'image'}];
 const after=[{id:'pending',kind:'image'},{id:'image',kind:'image'}];
 assert.equal(remapVideoMentions('@图片1',before,after),'@图片2');
});
test('mention insertion replaces the current query or selection and retains surrounding prompt text',()=>{
 assert.deepEqual(insertVideoMention('镜头 @视 随后推进','@视频1',3,5),{text:'镜头 @视频1 随后推进',cursor:7});
 assert.deepEqual(insertVideoMention('镜头','@图片1',2),{text:'镜头@图片1 ',cursor:7});
});
