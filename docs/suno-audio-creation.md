# Suno 音频创作

2026-10-25 已获授权并正式上线；生产迁移 20261024172815/suno_audio_operations 已应用。详见 [文档核对与发布记录](music-support-audit-20261025.md)。以下保留实现过程与上线前约束，当前状态以本更新为准。

2026-10-25。用户指定优先完成本地导入、1–4 段参考创作、上传后改编风格。本轮不创建 Vercel 部署，也不应用下面的新迁移到正式库。正式库只执行了另行授权的音乐历史表合并。

## 用户操作

音乐工作区的 Suno 增加“文字创作 / 参考音频创作 / 音频改编”。基础文字创作与 Flow Music 保持原逻辑。参考创作可以选择 1–4 段音频；改编只接受一段。切换后若已有素材超出上限，明确提示移除多余音频，不静默丢弃文件。

添加音频后可用本地播放器试听，每次只播放一段。本站支持 MP3、PCM WAV，每段大于零且不超过 20 MiB、时长 1 秒至 8 分钟；这是网站限制，不冒充服务商硬性上限。服务端根据实际文件字节解析格式与时长，不能只改扩展名绕过。音频素材需要登录、邮箱已验证、账户状态正常；自带 Key 的基础文字创作仍兼容访客。

上传及试听不扣网站积分。两个新生成操作使用普通模式，每次成功共 2 积分，返回两首仍合计 2 积分；自带 Key 不扣网站积分。未启用独立加价的 Max 模式（与 variety 风格变化的 max 值不同）。

## API 和协议

- `POST /api/music/references/uploads`：只收文件名、声明大小、MIME，返回单对象签名上传 URL 和上传票据。浏览器直接 PUT 到私有 Storage，绕过 Vercel Function 请求体限制，不附带网站 Authorization、Cookie 或音乐 Key。
- `POST /api/music/references/complete`：根据所有者票据读取限定对象，核验实际大小、格式、时长与内容 SHA256，返回 HMAC 校验凭证。
- `POST /api/music/operations/inspo`：1–4 份凭证，由服务器换取短期可读 URL，向固定 `/v1/music/generations/inspo` 提交 `audio_urls`。映射 tags、weirdness 等字段，不传 custom/instrumental/gpt_description/目标时长。依据[灵感生成文档](https://docs.apimart.ai/cn/api-reference/audios/suno/inspo)。
- `POST /api/music/operations/upload_cover`：单个凭证，固定 `/v1/music/generations/uploadCover`，使用 `audio_url`。描述模式传 gpt_description；自定义歌词模式传 prompt/tags，可选 duration_s。依据[上传并翻唱文档](https://docs.apimart.ai/cn/api-reference/audios/suno/upload-cover)。
- 两个操作直接接收 URL，不额外调用收费的 uploadTask；本地导入是准备素材，未声称创建上游导入任务。
- 查询沿用已实测修复的统一 `/v1/tasks/{task_id}?language=zh`，不改回先前返回 403 的音乐专用路径。音乐结果继续按 `result.music[]` 展示全部有效音轨和真实进度。

只允许平台预置服务或与之完全一致的标准自带 Key 端点使用音频工具；不假设任意兼容基础音乐的自定义服务商都兼容这些附加路径。

## 素材边界与留存

复用现有私有 `posterflow-images` bucket，路径为 `posterflow/music-<owner SHA256>/audio-references/<server epoch>-<server UUID>.mp3|wav`，不把 bucket 改公开。实际 Storage 签名地址必须与配置项目完全同源，禁止带凭据、fragment 或重定向。新功能无需新增公开环境变量；服务端沿用现有 Storage 凭证，独立音乐 Key 保持服务端配置。

上传票据绑定账户及当前服务作用域，核验后凭证还绑定文件内容。只允许服务端签发的素材，不接收任意用户音频 URL。换账号或服务配置、卸载页面时中止在途上传并释放本地 Object URL；刷新后需重新添加素材。

素材凭证从签发起 12 小时过期；临近过期 15 分钟停止新提交，为异步读取预留时间。真正给生成服务的读取签名至多 1 小时。新 Cron 每小时第 37 分钟通过 Storage API 删除满 12 小时的匹配音频对象，实际物理清理可能晚一小时；不会命中图片、参考图、其他 bucket、任意自定义文件名。失败上传暂留的对象也按此清理。现有图片和文本清理不变。

音乐成品仍由生成服务临时提供，页面已有 72 小时下载提示；这里的 12 小时专指上传的参考素材。历史与草稿只保留操作类型和白名单文本，不保存素材文件、URL、票据、校验凭证或 Key。

## 任务与数据

本地待应用 `20261024162034_suno_audio_operations.sql`：给已合并的 music_jobs 添加 operation/reference_count，新增仅 service_role 可调用的 begin_music_audio_job，补充管理员用量记录中的操作类型，并创建私有素材清理函数/Cron。不再新建音乐历史表。

沿用原预约/结算函数：先完成素材校验和签名，再原子预约 2 积分并保存文字；原请求 UUID + 稳定参数/素材指纹保证一次收费 POST。签名 URL 不进入指纹。重复已存在任务可使用已过期的原凭证识别，但不会再签名或提交。明确拒绝或失败退款一次，提交超时或受理后保存异常保留原意图与预留，不自动重发或猜测退款。管理员依实际 charged_credits 显示，DAU 定义不变。

## 验证与本地预览

已完成 222 Python、104 Node 测试，lint/build；隔离 PGlite 验证历史合并后的新操作、原图片计费、基本音乐计费、退款与权限。Storage 清理只在模拟 HTTP 上验证，没有真实删除素材。Chrome 1440/375 验证添加、真实本地 MP3 试听、后端凭证、进度、两首展示、退款、无效 WAV 拦截；另验证四段上限、历史文本及退出账号素材隔离。证据在 artifacts/suno-tools-20261024。

本地功能预览：`http://127.0.0.1:4176/`，音乐工作区。使用真正的本地构建、Flask 路由和隔离内存 SQL；生成服务、Storage、账户均为明确标示的测试替身。试听结果为两秒合成音，不能据此评价真实生成质量。没有真实付费请求、正式积分或素材写入。

重启预览（在项目根目录运行两个独立进程）：

```powershell
node artifacts/suno-tools-20261024/preview-database.cjs
.\.venv\Scripts\python.exe artifacts/suno-tools-20261024/preview-server.py
```

预览服务只监听 loopback，数据只在内存中，关闭后丢失。不读取 .env、不代理云服务。不得把预览脚本、浏览器会话注入或测试构建作为正式发布配置。

## 后续上线

必须先等用户明确说“可以部署了”。届时先复核正式环境/当前迁移，应用上述新迁移、核对私有 bucket 与既有 Vault 清理配置，再发布正常业务构建。先核对素材上传/读取与新 RPC，再用明确成本的一次真实生成验证账号实际权限和响应。当前没有进行该真实收费联调。回滚只切代码，保留用户/账目/兼容迁移；历史合并应急反向脚本不能在新增操作迁移之后不经检查直接运行。
