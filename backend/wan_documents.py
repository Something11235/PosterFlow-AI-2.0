"""Bounded document validation; no macros, conversion processes or rendering."""
import io
import zipfile
from xml.etree import ElementTree

try:
    from backend.video_provider import VideoError
except ModuleNotFoundError:
    from video_provider import VideoError

MIMES={'pdf':'application/pdf','txt':'text/plain','md':'text/markdown','doc':'application/msword',
       'docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
       'xls':'application/vnd.ms-excel','xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
       'ppt':'application/vnd.ms-powerpoint','pptx':'application/vnd.openxmlformats-officedocument.presentationml.presentation',
       'key':'application/vnd.apple.keynote','pages':'application/vnd.apple.pages','numbers':'application/vnd.apple.numbers'}


def metadata(data,extension):
    pages=None
    if not data or len(data)>100*1024*1024:raise VideoError('VIDEO_REFERENCE_SIZE','参考文档最多 100 MB。')
    try:
        if extension=='pdf':
            from pypdf import PdfReader
            if not data.startswith(b'%PDF-'):raise ValueError()
            reader=PdfReader(io.BytesIO(data),strict=True)
            if reader.is_encrypted:raise ValueError()
            pages=len(reader.pages)
        elif extension in {'txt','md'}:
            text=data.decode('utf-16' if data[:2] in {b'\xff\xfe',b'\xfe\xff'} else 'utf-8-sig')
            if not text.strip() or '\0' in text:raise ValueError()
        elif extension in {'doc','xls','ppt'}:
            if not data.startswith(bytes.fromhex('d0cf11e0a1b11ae1')) or len(data)<512:raise ValueError()
        else:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                entries=archive.infolist();names={i.filename for i in entries}
                if len(entries)>20000 or sum(i.file_size for i in entries)>512*1024*1024 or any(i.flag_bits&1 for i in entries):raise ValueError()
                required={'docx':'word/document.xml','xlsx':'xl/workbook.xml','pptx':'ppt/presentation.xml'}
                if extension in required and required[extension] not in names:raise ValueError()
                if extension in {'key','pages','numbers'} and not any(n.startswith('Index/') and n.endswith('.iwa') for n in names):raise ValueError()
                if extension=='pptx':pages=sum(n.startswith('ppt/slides/slide') and n.endswith('.xml') and '/' not in n[len('ppt/slides/'):] for n in names)
                elif extension=='docx' and 'docProps/app.xml' in names:
                    if archive.getinfo('docProps/app.xml').file_size>1024*1024:raise ValueError()
                    xml=archive.read('docProps/app.xml')
                    if b'<!DOCTYPE' in xml or b'<!ENTITY' in xml:raise ValueError()
                    root=ElementTree.fromstring(xml)
                    page=root.find('{http://schemas.openxmlformats.org/officeDocument/2006/extended-properties}Pages')
                    if page is not None and page.text and page.text.isdigit() and int(page.text)>0:pages=int(page.text)
    except Exception:
        raise VideoError('VIDEO_REFERENCE_FORMAT','文档内容无法识别或已加密，请使用有效、可读取的支持格式。') from None
    if pages is not None and not 1<=pages<=50:raise VideoError('VIDEO_REFERENCE_PAGES','参考文档最多 50 页，请拆分后上传。')
    return {'kind':'document','size':len(data),'content_type':MIMES[extension],**({'pages':pages} if pages is not None else {})}
