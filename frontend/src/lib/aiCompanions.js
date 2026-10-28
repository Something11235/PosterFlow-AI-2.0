import catalog from './aiCompanionsCatalog.json';

export const AI_COMPANIONS=catalog;
export const AI_COMPANION_IMAGE_COUNT=catalog.reduce((n,g)=>n+g.images.length,0);
const images=new Map(catalog.flatMap(g=>g.images.map(i=>[i.id,i])));

export async function companionFile(id,{signal}={}){
  const image=images.get(id);
  if(!image)throw new Error('请选择专区中的图片。');
  const response=await fetch(image.url,{signal,credentials:'omit',redirect:'error',referrerPolicy:'no-referrer'});
  if(!response.ok)throw new Error('素材暂时读取失败，请稍后重试。');
  const blob=await response.blob();
  if(blob.size!==image.bytes || !blob.type.startsWith('image/'))throw new Error('素材文件不完整，请刷新后重试。');
  return new File([blob],image.id+'.jpg',{type:'image/jpeg',lastModified:0});
}
