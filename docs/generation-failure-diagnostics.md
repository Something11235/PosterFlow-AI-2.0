# 生成失败分类与素材预检查（2026-10-25，已正式发布）

本轮已正式部署 dpl_2ydEbgx6581VfCJy5p2G7XRcy9P8，管理员只读统计迁移20261025123511已应用；原账户、积分和任务保留，未调用收费生成。

- 音乐 `MUSIC_AUDIO_MATCH`：服务明确返回“This audio matches an existing recording in our catalog.”时，显示参考音频与曲库已有录音匹配、未通过查重；不将其误报为歌词版权问题。建议使用有使用权且符合服务要求的原创录音。嵌套 error、编码 JSON 中的原因同样能识别；已知版权、艺人名称等类别继续分别处理。未知音乐失败保留用户此前要求的兜底提示，不以它推断已知原因。
- 图片 `IMAGE_PROVIDER_TIMEOUT`：HTTP 504/524 或明确 gateway timeout 显示中文服务超时及至少等待两分钟的建议，不使用修改提示词/审核拒绝文案。原 GPT 同步服务和新增异步图片模型均覆盖。异步提交不确定时预留保留、不重发 POST；查询 HTTP 超时不结算、不退款；只有查询返回明确 failed/cancelled 后才通过原幂等 RPC 退回。前端保留错误码和说明，待确认任务可查询原任务，并隐藏不确定提交的“重新生成”。
- 视频 `VIDEO_REFERENCE_RESOLUTION` / `VIDEO_REFERENCE_DURATION`：翻译尺寸和时长限制，任务列表刷新后仍可根据已存分类显示中文。以前未记录具体分类的失败任务无法凭空恢复真实原因。

视频图片前端解码校验、服务端实际文件校验，以及旧收据提交时再次校验：宽高均300–6000px，宽高比0.4–2.5。Mini每段音频/视频2–15秒；2.5每段2–30秒。浏览器使用本地 Blob 读取媒体元数据并释放对象URL，校验失败不申请上传、不提交生成；服务端以实际内容及签名元数据为准，生成预留发生在校验之后。链接导入走服务端同样规则；已审核素材沿用审核结果。不会自动放大或裁切用户原素材。

规则依据：[Seedance 2.5 素材要求及素材同步校验](https://docs.apimart.ai/cn/api-reference/videos/seedance-2-5/generation)、[Seedance 2.0 生成](https://docs.apimart.ai/cn/api-reference/videos/seedance-2-0/generation)。素材文档列明2.0家族按2–15秒，2.5按2–30秒；日志中的1.8/30.2是服务边界提示，本站采用文档的2/30秒规格。Mini保留原参考视频总时长大于1.8、小于15.2秒的合计规则、音频合计15秒、原定价及输出时长4–15秒。

诊断只输出固定中文及内部类别，不透传上游原始日志、链接、签名参数、密钥、曲目输入或 Cloudflare 追踪字段。原始错误仅作为有深度和长度限制的分类输入，不写入公共返回值。

验证证据：artifacts/admin-errors-20261025。真实构建在1440/375宽度用合成账户/API验证管理员状态筛选、失败原因与小数积分；真实1像素PNG和1秒PCM WAV在浏览器上传前被拦截，合法图片能进入模拟上传流程。Python测试覆盖真实文件、旧收据、网关超时不重发/查询不终结任务；隔离PGlite验证新管理员RPC的统计和权限。没有真实付费服务调用。


## 2026-10-28 Flow 参数类型与改编通用失败（本地待发布）

截图核对：两笔Lyria 3.5 generate任务返回Request parameter type mismatch，另一笔标准版cover仅返回Job failed,Please try again later.；本站三笔均refunded、charged_credits=0。前者明确归类MUSIC_PARAMETER_TYPE_MISMATCH，中文说明未指明具体字段、需保留任务号核查；后者归类MUSIC_PROVIDER_JOB_FAILED，明确服务未提供具体失败原因。两者都不再归入未知错误的版权兜底。此前用户指定的真正未知失败兜底原文保持。

normalize_task仅从error/message/error_message/failure_reason及result.error读取错误；不把歌曲title、lyrics、prompt当成原因或将原始URL/Key输出给前端。管理员类型标签同步。已退款旧任务刷新时可显示新查询到的原因，不重发POST或改写历史账目；没有人工修改正式错误码/余额。

当前不能声称已修复生成失败：官方Flow两版本均规定bpm/seed为字符串、length为1–240整数，标准版省略version而3.5明确version=lyria-3.5；现有构造及序列化类型符合。历史只保留提示词类字段，没记录bpm/length/seed，不能因历史缺项推断没有填写。失败两笔文本字段重算指纹不匹配原提交指纹；只读常见可选值核对未锁定原始请求。仍需原值/上游请求参数，不能盲目把BPM改成数字或补默认时长、不能自动重新收费生成。

321 Python/145 Node及差异检查通过，新增两版本出站JSON类型、截图错误多种容器、安全中文、旧退款任务GET刷新无POST等回归。无新数据库迁移、生产写入、付费生成、部署或Git操作。证据artifacts/flow-type-diagnostics-20261028/verification.json；现网仍dpl_4WRjv5zLG8tMuYBSsPsvTpNNsz2N。
