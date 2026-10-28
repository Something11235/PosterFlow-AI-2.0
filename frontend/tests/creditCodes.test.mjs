import test from 'node:test';
import assert from 'node:assert/strict';
import {CREDIT_PACKAGES,creditCodeApi,normalizeCreditCode,creditCodeFilename} from '../src/lib/creditCodes.js';

test('credit packages match the five actual Taobao SKUs and normalize a single code',()=>{
 assert.deepEqual(CREDIT_PACKAGES.map(p=>[p.price,p.credits]),[[10,20],[30,70],[50,120],[80,200],[100,260]]);
 const code='PF'+'A'.repeat(26);assert.equal(normalizeCreditCode(' '+code.toLowerCase().slice(0,8)+'-\n'+code.slice(8)+' '),code);
 for(const invalid of ['PF'+'0'.repeat(26),'PF'+ 'A'.repeat(25),'taobao-voucher',''])assert.throws(()=>normalizeCreditCode(invalid));
 assert.equal(creditCodeFilename({package_id:'pf20',note:'1'},100),'10元20积分-100-1.txt');
 assert.equal(creditCodeFilename({package_id:'pf20',note:'第１批'},93),'10元20积分-93-1.txt');
 assert.equal(creditCodeFilename({package_id:'pf260',note:'',id:'test-batch'},100),'100元260积分-100-test-batch.txt');
 assert.equal(creditCodeFilename({package_id:'pf70',note:'../../1:批?. '},5),'30元70积分-5-....1批.txt');
});
test('redeem requests contain codes only in POST bodies, never URL/storage; failures are not success',async()=>{
 const original=globalThis.fetch,calls=[];globalThis.fetch=async(url,options)=>{calls.push({url,options});return {ok:true,json:async()=>({success:true,credits:20})};};
 try{const code='PF'+'A'.repeat(26);await creditCodeApi('/redeem',{authHeaders:{Authorization:'Bearer fixture'},body:{code}});assert.equal(calls[0].url,'/api/credit-codes/redeem');assert.equal(calls[0].options.method,'POST');assert.equal(calls[0].options.cache,'no-store');assert.equal(calls[0].options.credentials,'include');assert.equal(JSON.parse(calls[0].options.body).code,code);
 globalThis.fetch=async()=>({ok:false,json:async()=>({error:'兑换码无效或暂不可用'})});await assert.rejects(creditCodeApi('/redeem',{body:{code}}),/无效/);
 }finally{globalThis.fetch=original;}
});
