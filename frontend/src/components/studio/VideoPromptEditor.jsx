import React,{useId,useLayoutEffect,useRef,useState} from 'react';
import {AtSign,FileText,Film,Image,Music2} from 'lucide-react';
import {insertVideoMention,videoMentions} from '../../lib/videoMentions';

export default function VideoPromptEditor({value,onChange,items,mentionsEnabled,maximum=32000}){
  const editor=useRef(null),selection=useRef({start:value.length,end:value.length}),composing=useRef(false),pendingCursor=useRef(null);
  const [menu,setMenu]=useState(null),[highlight,setHighlight]=useState(0),listId=useId();
  const options=videoMentions(items).filter(i=>i.state==='ready' && (!menu?.query || i.token.includes(menu.query) || i.name.includes(menu.query)));
  useLayoutEffect(()=>{const pending=pendingCursor.current;if(!pending)return;pendingCursor.current=null;if(pending.text===value){editor.current?.focus();editor.current?.setSelectionRange(pending.cursor,pending.cursor);}},[value]);
  function detect(target){
    const {selectionStart:start,selectionEnd:end}=target;selection.current={start,end};
    const match=value.slice(0,start).match(/@([^\s@]*)$/u);
    setMenu(mentionsEnabled && start===end && match?{start:start-match[0].length,end,query:match[1]}:null);setHighlight(0);
  }
  function choose(item){
    const range=menu || selection.current,result=insertVideoMention(value,item.token,range.start,range.end);
    pendingCursor.current=result;onChange(result.text);setMenu(null);selection.current={start:result.cursor,end:result.cursor};
  }
  return <div className="video-prompt-editor video-composer-card">
    <div className="video-prompt-heading"><label htmlFor={listId+'-prompt'}><FileText size={18} aria-hidden="true" />视频提示词</label><small id={listId+'-count'}>{Array.from(value).length} / {maximum}</small></div>
    <p className="video-section-hint" id={listId+'-hint'}>在下方输入你想生成的画面、镜头运动与声音。</p>
    <textarea ref={editor} id={listId+'-prompt'} aria-describedby={listId+'-hint '+listId+'-count'} rows={6} maxLength={maximum} value={value}
      placeholder={mentionsEnabled?'在这里写视频提示词，例如：镜头缓缓推进，人物转身望向窗外。也可用 @ 引用下方素材。':'在这里写视频提示词，例如：傍晚的海边，镜头缓缓推进，海浪拍打礁石，配上轻柔的环境音。'}
      aria-autocomplete={mentionsEnabled?'list':undefined} aria-controls={menu?listId:undefined} aria-expanded={mentionsEnabled?Boolean(menu):undefined}
      aria-activedescendant={menu && options[highlight]?listId+'-'+highlight:undefined}
      onChange={e=>{onChange(e.target.value);const t=e.target,start=t.selectionStart,end=t.selectionEnd;selection.current={start,end};const match=t.value.slice(0,start).match(/@([^\s@]*)$/u);setMenu(!composing.current && mentionsEnabled && match?{start:start-match[0].length,end,query:match[1]}:null);setHighlight(0);}}
      onSelect={e=>{if(!composing.current)detect(e.currentTarget);}}
      onCompositionStart={()=>{composing.current=true;}} onCompositionEnd={e=>{composing.current=false;detect(e.currentTarget);}}
      onKeyDown={e=>{if(!menu || e.nativeEvent.isComposing)return;if(e.key==='Escape'){setMenu(null);e.preventDefault();}else if(options.length && ['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();setHighlight(n=>(n+(e.key==='ArrowDown'?1:-1)+options.length)%options.length);}else if(options.length && e.key==='Enter'){e.preventDefault();choose(options[highlight] || options[0]);}}} />
    <div className="video-prompt-actions">{mentionsEnabled && <button type="button" className="video-tool-button" aria-expanded={Boolean(menu)} aria-controls={listId} onClick={()=>{const range=editor.current?{start:editor.current.selectionStart,end:editor.current.selectionEnd}:selection.current;setMenu(menu?null:{...range,query:''});setHighlight(0);}}><AtSign size={16} />引用素材</button>}<small>所有已添加素材都会发送；{mentionsEnabled?'@ 用于指定各素材如何参与创作。':'无需切换图片用途。'}</small></div>
    {menu && <div className="video-mention-panel"><div className="video-mention-title">选择参考素材<button type="button" aria-label="关闭素材引用" onClick={()=>setMenu(null)}>关闭</button></div><div id={listId} role="listbox" aria-label="可引用素材">{options.length?options.map((item,index)=>{const Icon={image:Image,video:Film,audio:Music2}[item.kind];return <button type="button" role="option" id={listId+'-'+index} aria-selected={index===highlight} key={item.id} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(item)}><Icon size={17} /><strong>{item.token}</strong><span>{item.name}</span></button>;}):<p>请先添加并校验图片、视频或音频；仅列出匹配的可用素材。</p>}</div></div>}
  </div>;
}
