export const SEEDANCE20='seedance-2.0';
export const SEEDANCE20_FAST='seedance-2.0-fast';
export const isSeedance20=model=>[SEEDANCE20,SEEDANCE20_FAST].includes(model);
export const defaultSeedance20=(model=SEEDANCE20)=>({model,prompt:'',resolution:'720p',duration:5,size:'16:9',seed:'',generate_audio:true,return_last_frame:false,web_search:false,nsfw_check:false});

export function buildSeedance20(values){
  const {prompt='',resolution='720p',duration=5,size='16:9',seed=''}=values;
  const model=values.model || SEEDANCE20,fast=model===SEEDANCE20_FAST;
  if(!isSeedance20(model))throw new Error('请选择 Seedance 2.0 或 Fast。');
  const text=String(prompt).trim(),seconds=Number(duration);
  if(Array.from(text).length>4000)throw new Error('Seedance 2.0 提示词最多 4000 个字符。');
  if(!(fast?['480p','720p']:['480p','720p','1080p','4k']).includes(resolution)||!Number.isInteger(seconds)||seconds<4||seconds>15||!['16:9','9:16','1:1','4:3','3:4','21:9','adaptive'].includes(size))throw new Error(fast?'Fast 仅支持 480P / 720P、4–15 秒和有效画幅。':'请选择 Seedance 2.0 支持的清晰度、4–15 秒和有效画幅。');
  const body={model,prompt:text,resolution,duration:seconds,size,generate_audio:Boolean(values.generate_audio),return_last_frame:Boolean(values.return_last_frame),nsfw_check:Boolean(values.nsfw_check)};
  if(seed!==''&&seed!=null){const n=Number(seed);if(!/^-?\d+$/.test(String(seed))||!Number.isInteger(n)||n< -1||n>2147483647)throw new Error('请输入有效随机种子。');body.seed=n;}
  if(values.web_search)body.tools=[{type:'web_search'}];
  return body;
}

export function seedance20Quote(values,references=[]){
  const body=buildSeedance20(values),refMs=references.filter(r=>r.kind==='video').reduce((n,r)=>n+(r.duration_ms || 0),0);
  const rates=body.model===SEEDANCE20_FAST?{'480p':[39840,23680],'720p':[85600,51280]}:{'480p':[66000,40000],'720p':[142000,85840],'1080p':[354400,215680],'4k':[722000,444320]};
  const rate=rates[body.resolution][refMs?1:0];
  if(!Number.isInteger(refMs)||refMs<0)throw new Error('参考视频时长尚未校验。');
  const nanoUsd=(body.duration*1000+refMs)*rate;
  const halves=Math.ceil(nanoUsd*1680/(38*1e9)),reserved=Math.ceil(nanoUsd*1680*16/(38*1e9*10));
  return {units:halves*5000,text:String(halves/2),reservedUnits:reserved*5000,reservedText:String(reserved/2),referenceSeconds:refMs/1000,generatedSeconds:body.duration};
}
