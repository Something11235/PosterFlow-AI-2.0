export const CREDIT_PACKAGES=[
  {id:'pf20',credits:20,price:10,name:'10元20积分'},
  {id:'pf70',credits:70,price:30,name:'30元70积分'},
  {id:'pf120',credits:120,price:50,name:'50元120积分'},
  {id:'pf200',credits:200,price:80,name:'80元200积分'},
  {id:'pf260',credits:260,price:100,name:'100元260积分'},
];
export function normalizeCreditCode(value){
  const code=String(value || '').replace(/[\s-]/g,'').toUpperCase();
  if(!/^PF[A-Z2-7]{26}$/.test(code))throw new Error('请粘贴完整的 PosterFlow 积分兑换码。');
  return code;
}
export async function creditCodeApi(path,{authHeaders={},body,signal}={}){
  const response=await fetch('/api/credit-codes'+path,{method:body!==undefined?'POST':'GET',headers:{...authHeaders,...body!==undefined?{'Content-Type':'application/json'}:{}},credentials:'include',cache:'no-store',signal,...body!==undefined?{body:JSON.stringify(body)}:{}});
  let data;try{data=await response.json();}catch{throw new Error('暂未确认结果，请刷新记录后再核对本次操作。');}
  if(!response.ok || !data.success)throw new Error(data.error || data.detail || '兑换码服务暂不可用。');
  return data;
}
export function creditCodeFilename(batch,count){
  const pack=CREDIT_PACKAGES.find(p=>p.id===batch?.package_id);
  if(!pack || !Number.isSafeInteger(count) || count<1)throw new Error('导出套餐信息不完整，请刷新批次后重试。');
  const safe=value=>Array.from(String(value||'').normalize('NFKC').replace(/[<>:"/\\|?*\x00-\x1f\x7f]/g,'').trim().replace(/[. ]+$/g,'')).slice(0,48).join('');
  const label=safe(batch.note).replace(/^(?:第\s*)?(\d+)\s*批?$/,'$1') || safe(batch.id) || '未命名批次';
  return `${pack.name}-${count}-${label}.txt`;
}
export function downloadCreditCodes(data,batch){
  if(!data.count || !data.text)throw new Error('此批次没有可导出的未使用兑换码。');
  const codes=data.text.split('\n');
  if(codes.length!==data.count || codes.some(c=>normalizeCreditCode(c)!==c))throw new Error('导出内容不完整，请刷新批次后重试。');
  const filename=creditCodeFilename(batch,data.count);
  const url=URL.createObjectURL(new Blob([data.text+'\n'],{type:'text/plain;charset=utf-8'}));
  const link=document.createElement('a');link.href=url;link.download=filename;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
