const names={image:'图片',video:'视频',audio:'音频'};
const tokenPattern=/@(图片|视频|音频)([1-9]\d*)(?!\d)/gu;

// Match the order of each media array in the provider request, including pending
// known types so a completed upload never silently steals an existing number.
export function videoMentions(items){
  const counts={image:0,video:0,audio:0};
  return items.flatMap(item=>names[item.kind]?[{...item,token:`@${names[item.kind]}${++counts[item.kind]}`}]:[]);
}

export function remapVideoMentions(text,before,after){
  const old=new Map(videoMentions(before).map(i=>[i.token,i]));
  const next=new Map(videoMentions(after).map(i=>[i.id,i.token]));
  return text.replace(tokenPattern,(token)=>old.has(token)?next.get(old.get(token).id) || `【已移除${token.slice(1)}】`:token);
}

export function videoMentionError(text,items){
  if(/【已移除(?:图片|视频|音频)\d+】/u.test(text))return '提示词引用的素材已移除，请修改标记或重新选择素材。';
  const available=new Set(videoMentions(items).map(i=>i.token));
  const missing=[...text.matchAll(tokenPattern)].map(m=>m[0]).find(token=>!available.has(token));
  return missing?`${missing} 没有对应素材，请添加素材或修改提示词。`:'';
}

export function insertVideoMention(text,token,start,end=start){
  const tail=text.slice(end),space=!tail || /^\S/u.test(tail)?' ':'';
  return {text:text.slice(0,start)+token+space+tail,cursor:start+token.length+space.length};
}
