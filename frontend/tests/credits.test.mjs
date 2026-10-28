import assert from "node:assert/strict";
import test from "node:test";
import { creditText, creditUnits } from "../src/lib/credits.js";

test("fractional website credits use exact integer units",()=>{
  assert.equal(creditUnits('0.1')+creditUnits('0.2'),creditUnits('0.3'));
  assert.equal(creditText('7.5000'),'7.5');assert.equal(creditText('-0.0001'),'-0.0001');assert.equal(creditText('10.0000'),'10');
  for(const value of [true,null,NaN,Infinity,'0.00001','1e4','',{},'0.30000000000000004'])assert.throws(()=>creditUnits(value));
});
