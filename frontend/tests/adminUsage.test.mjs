import assert from "node:assert/strict";
import test from "node:test";
import { adminUsageRows, usageState, usageBillingLabel, filterUsageRows } from "../src/lib/adminUsage.js";

test("mixed usage is ordered by time, identified by type and filters without changing actual credits",()=>{
 const image={id:"image",created_at:"2026-10-23T12:00:00Z",generated_count:2,charged_credits:2};
 const music={request_id:"music",created_at:"2026-10-23T13:00:00Z",generated_count:2,charged_credits:2,billing_unit:"request"};
 const rows=adminUsageRows([image],[music]);
 assert.equal(rows[0].kind,"music");assert.equal(rows[0].charged_credits,2);assert.equal(rows[0].generated_count,2);
 assert.equal(adminUsageRows([image],[music],"image").length,1);
 assert.equal(adminUsageRows([image],[music],"music")[0].billing_unit,"request");
 assert.equal(usageState({status:"completed",billing_status:"awaiting_balance"}),"待补足积分");
 assert.equal(usageState({status:"failed",billing_status:"refunded"}),"已退回");
 assert.equal(usageState({status:"submission_unknown"}),"待确认");
});

test('video billing and attention states reflect actual settlement rather than task completion',()=>{
 const rows=adminUsageRows([],[], 'all', [
  {request_id:'balance',model:'seedance-2.5',status:'completed',billing_status:'awaiting_balance',charged_credits:0,reserved_credits:17},
  {request_id:'provider',model:'seedance-2.5',status:'processing',billing_status:'awaiting_provider'},
  {request_id:'mini',model:'seedance-2.0-mini',status:'completed',billing_mode:'platform',billing_status:'settled',charged_credits:2.5},
  {request_id:'failed',status:'failed',billing_status:'refunded',failure_label:'参考素材尺寸',failure_reason:'宽高须为 300–6000 像素'}
 ]);
 assert.equal(filterUsageRows(rows,'attention').length,2);
 assert.equal(filterUsageRows(rows,'success')[0].request_id,'mini');
 assert.equal(filterUsageRows(rows,'failed','素材尺寸')[0].request_id,'failed');
 assert.equal(usageBillingLabel({kind:'video',model:'seedance-2.5',billing_mode:'platform'}),'实际用量结算');
 assert.equal(usageBillingLabel({kind:'video',model:'MiniMax-H3',billing_mode:'platform'}),'实际用量结算');
 assert.equal(usageBillingLabel(rows.find(r=>r.request_id==='mini')),'按秒计费');
 assert.equal(usageBillingLabel({kind:'video',billing_mode:'own_key'}),'不扣网站积分');
});
