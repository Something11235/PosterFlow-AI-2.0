> 2026-10-22 更新：当前界面与模型以 [本轮升级说明](studio-refresh-20261022.md) 为准。入口为图像→音乐→视频；采用原版蓝色风格。视频仅展示5个规划模型，不保留旧参数编辑/视频草稿；flowmusic仅预览。旧调研中的Veo/Wan2.6/Seedance1.5不属于当前选定模型，不可直接作为新接口参数复用。下方为先前调研与历史实现说明。

# PosterFlow AI 多媒体升级方案

记录日期：2026-10-21（北京时间）。依据 APIMart 当前公开中文文档和本仓库稳定基线整理；模型权限、供应商实付价格及真实响应仍需在后续接入阶段确认。

## 1. 本轮范围与回滚点

本轮先完成本地的图像、视频、音乐三类工作台排版和交互预览，范围已按用户最新要求收窄。现有图像继续使用原有图片服务、积分和生成流程，不因界面升级自动切换 APIMart。新增媒体的模型选择、表单、参数和请求预览用于审阅设计，尚未接通真实生成；提交请求预览不代表已提交任务，不模拟排队、成功作品或实际扣费。

用户已明确要求：没有新的明确部署指令，不得自行部署。本轮不推送 GitHub、不创建 Vercel 部署、不修改线上 Supabase、Cron、价格、环境变量或邮件设置，不调用付费生成接口。

| 回滚项目 | 已记录的基线 |
| --- | --- |
| 稳定源代码 | `741d77a412e0565c69e4f0cab239288f2377e774` |
| 本地标签 | `checkpoint/pre-multimedia-20261021` |
| 本地开发分支 | `codex/multimedia-studio` |
| 稳定部署 | Vercel `GnkV5Dw8rTEgki4huh2G5SVK98yn`，当前生产继续运行此版本 |
| 源代码归档 | `artifacts/checkpoints/image-baseline-741d77a.zip`，不含数据库、密钥或用户作品 |
| 详细回滚说明 | `docs/checkpoints/2026-10-21-image-baseline.md` |

回滚前先保存新版开发成果；不要使用 `reset --hard`、`clean` 或覆盖未提交文件。仅回滚网站不会回滚数据库，也不会停用原有图片和提示词清理任务。后续即使暂停多媒体工程，原图像工作台仍应能够独立运行。

## 2. 产品方向与界面结构

升级方向是一个共用账号、积分和创作入口的多媒体工作台。图像、视频、音乐各有自己的输入方式、参数和结果类型，不把所有模型挤进一张万能表单。

- 图像：保留当前文生图、局部重绘、参考图、蒙版、无限画布和画廊；本轮重点改善入口与工作台层级。
- 视频：首轮从文生视频开始；主体、动作、镜头、风格通过提示词表达，模型切换时只提供该模型支持的比例、时长、清晰度和音频开关。
- 音乐：区分灵感模式、自定义歌词和纯音乐；下一阶段再加入延长、改编、分轨，避免首版混入不同来源引用规则。
- 任务中心：真实接入后展示等待、生成、完成或失败及可恢复任务；本轮预览只展示请求草稿，不伪造任务进度。

页面采用固定创作导航、清晰的工作区标题、左侧输入与参数、右侧输出或请求预览。移动端按输入、参数、输出顺序排列；参数区域使用原生可访问控件，切换模型时清理不兼容字段。管理员控制台、账户、购买积分、公告和历史记录继续从共用入口访问。

图像子模式与媒体类别分开维护：`image / video / music` 决定工作区，原来的 `create / iterative / canvas` 仍只表示图像工具。切换媒体时保留原图像状态，避免无限画布卸载丢失编辑现场；从历史填入图像提示词、从画廊进入画布时显式回到图像区。

## 3. 已核实的现有架构

以下是稳定基线中已有的代码和约束，不是新媒体已实现的能力。

| 代码位置 | 当前行为 | 升级影响 |
| --- | --- | --- |
| `backend/server.py` 的 `execute_generation` | 同一次 HTTP 请求内取得非空图片列表，再结算；异常进入图片退款流程 | 不能把 APIMart 的提交成功响应当成图片成功，也不能套到长视频、音乐任务 |
| 同文件 `generate_images`、`resolve_provider_config` | 当前图片提供商适配、参考图处理及平台/自带 Key 边界 | 新增 APIMart 适配器，保留旧图像路径，不直接替换现有服务地址 |
| `backend/supabase_service.py` 的 `account_snapshot`、`recover_stale_generation_jobs` | 账户读取和平台图片生成会触发默认十分钟的过期任务恢复 | 新媒体排队十分钟可能仍正常，不能共用“超时即退款”规则 |
| `supabase/migrations/20261016_011_recover_stale_generation_jobs.sql` | 对达到时限的 running/platform 图片任务退回预扣积分 | 保持旧图片语义；新媒体建立独立对账策略 |
| `supabase/migrations/20260910_001_posterflow_auth_credits.sql` | `generation_jobs` 有图片数量和 `image_keys`；状态限于 reserved/running/succeeded/failed/refunded；流水 `job_id` 外键指向图片任务 | 不直接把音乐首数或视频秒数塞进图片数量 |
| `supabase/migrations/20261019123740_sunburst_one_credit.sql` | 图片结算保留预约时价格，现有三个平台图片模型每张1积分 | 新媒体另建价格版本与计量单位，原图像价格和历史流水不改 |
| `frontend/src/lib/provider.js` | 自带 Key 仅保存在 sessionStorage，经 `X-Provider-*` 请求头交后端；原图像参考图上限8张 | 不落库、不加入请求草稿或历史，不因新目录支持更多参考图就修改旧限制 |
| `vercel.json`、图片超时常量 | 函数 maxDuration 配置300秒，图片上游请求约240至280秒 | 不在单次函数里等待数分钟视频或音乐，也不依赖响应后的普通后台线程 |
| `backend/prompt_history.py`、`SupabaseGateway.prompt_history` | 登录历史只返回 `id,prompt,created_at`，滚动七天，每页50条，认证身份限定本人 | 新媒体提示词若接入历史，继续文字白名单和七天保留；不能附媒体URL或图片 |

当前平台图片频控为8次/60秒的进程内窗口，不能作为跨 Vercel 实例的强一致并发保障。每日图片总限额已经取消，新媒体方案不得借升级重新打开原每日限额。

## 4. APIMart 接口与生命周期

基地址为 `https://api.apimart.ai`，服务端使用 `Authorization: Bearer <Key>`。路径相似不代表响应相同；按媒体和操作选择适配器。

| 操作 | 方法与路径 | 发送方式 | 成功响应与下一步 |
| --- | --- | --- | --- |
| 图像生成 | `POST /v1/images/generations` | JSON，各模型字段不同 | 异步；读取 `data[0].task_id`，再查 `/v1/tasks/{task_id}` |
| 视频生成 | `POST /v1/videos/generations` | JSON，各模型字段不同 | 异步；同上，不是提交后立即拿到视频 |
| 音乐生成 | `POST /v1/music/generations` | JSON；Suno 与 Flow Music 各有模型及参数 | 异步；查询 `GET /v1/music/tasks/{task_id}`，不能统一改成图片任务路径 |
| 参考图上传 | `POST /v1/uploads/images` | multipart，字段 file | 返回顶层公开图片URL等信息，随后再提交生成 |
| 模型目录 | `GET /v1/models?expand=parameters&category=image` 或 video | 服务端鉴权GET | 可提供模型分类、能力和JSON Schema；音乐仍按专用模型文档校验参数 |

图像/视频典型提交响应：

```json
{"code":200,"data":[{"status":"submitted","task_id":"task_example"}]}
```

统一任务查询典型形状：

```json
{
  "code": 200,
  "data": {
    "id": "task_example",
    "status": "completed",
    "progress": 100,
    "result": {"images": [{"url": ["https://example.invalid/result.png"], "expires_at": 0}]}
  }
}
```

示例只说明结构，不表示请求真实执行；`expires_at` 应读取实际Unix时间，结果URL也不能当永久存储。任务文档状态为 pending/processing/completed/failed/cancelled，提交页另有 submitted，解析时需要兼容。结果在 `data.result.images`、`data.result.videos`；音乐专用接口使用 `data.result.music`，按真实返回数量处理。不能因为某个Suno请求常见返回两首，就固定生成两张结果卡。

`language=zh` 可用于统一任务查询的失败消息，改变消息语言，不改变错误码或结算事实。提交HTTP错误、任务终态failed、取媒体文件失败需要分别处理。文档出现cancelled不等于已提供可调用的取消接口；关闭页面或AbortController只停止客户端等待，不代表取消上游任务或已经退款。

依据：[任务状态](https://docs.apimart.ai/cn/api-reference/tasks/status)、[Suno通用约定](https://docs.apimart.ai/cn/api-reference/audios/suno/overview)。

## 5. 最小模型矩阵

模型名称以下游请求值为准，展示名称可使用更易懂的产品名称。以下是接入候选和文档约束，不表示当前账号已开通、当前站点已接通，或价格已经配置。

| 类别 | 精确model / version | 首轮参数与范围 | 接入备注与来源 |
| --- | --- | --- | --- |
| 现有图片 | `gpt-image-2.5-flare` / `gpt-image-2.5-sunburst` / `gpt-image-2` | 保留本站既有生图参数与1积分/张 | 本轮仍调用原图像服务，不因APIMart也有同名模型而切换 |
| APIMart图片候选 | `gpt-image-2.5-flare`、`gpt-image-2.5-sunburst` | n=1–4；size支持auto/比例/像素；resolution小写1k/2k/4k；quality支持low/medium/high/xhigh/max/auto | 最多16个公网参考图URL；与本站现有图片流程不同。[文档](https://docs.apimart.ai/cn/api-reference/images/gpt-image-2.5/generation) |
| APIMart图片候选 | `gemini-3.1-flash-image-preview` | n仅1；resolution大写0.5K/1K/2K/4K；size按模型枚举 | 最多14张URL/Data URI参考图，单张10MB。[文档](https://docs.apimart.ai/cn/api-reference/images/gemini-3.1-flash/generation) |
| 视频 | `seedance-1-5-pro` | duration整数4–12；aspect_ratio=16:9/9:16/1:1/4:3/3:4/21:9；resolution=480p/720p/1080p；audio布尔值，当前正文默认true | 首轮只做文生视频；不传图片或固定镜头等非必要字段。[文档](https://docs.apimart.ai/cn/api-reference/videos/seedance-1-5-pro/generation) |
| 视频 | `veo3.1-fast` | duration固定8；aspect_ratio=16:9/9:16；resolution=720p/1080p/4k | 此页没有Seedance式audio开关，不强行传同名参数。[文档](https://docs.apimart.ai/cn/api-reference/videos/veo3/generation) |
| 视频 | `wan2.6` | duration仅5/10/15；aspect_ratio=16:9/9:16/1:1/4:3/3:4；resolution=720p/1080p；audio可选 | 后续图生模式不可传aspect_ratio；audio_url优先于audio。[文档](https://docs.apimart.ai/cn/api-reference/videos/wan2.6/generation) |
| 音乐 | model=`suno`，version=`v6` | custom=false灵感prompt≤3000字符；custom=true歌词prompt≤5000字符；title≤80、style≤1000仅自定义有效；instrumental控制纯音乐 | 自定义非纯音乐须提供歌词；纯音乐可省略歌词。版本另有v6-wild/v6-mini。[生成文档](https://docs.apimart.ai/cn/api-reference/audios/suno/generation) |
| 音乐 | model=`flowmusic`，可选version=`lyria-3.5` | sound_prompt/lyrics至少一个；length整数1–240秒；bpm为字符串 | 每次一首；clip_id用于后续编辑，不能拿version当model。[Flow](https://docs.apimart.ai/cn/api-reference/audios/flow-music/music)、[Lyria](https://docs.apimart.ai/cn/api-reference/audios/flow-music/music-lyria-3-5) |

三款首轮视频文档都没有明确给出提示词字符上限。本站若为交互体验设置长度限制，应标为本站限制，不把其他视频模型的4000字符规则套过来。切换模型时显式提交受支持的值，避免默认值变化和旧参数残留。

模型目录支持 `GET /v1/models?expand=parameters&category=image|video`；单模型契约为 `/v1/models/{id}/schema`，名称含斜杠时使用 `/v1/model-schema?model=...`。模型范围受Key权限和账号分组影响；Schema存在分钟级缓存且不保证涵盖全部组合约束，服务端仍须校验。[模型元数据文档](https://docs.apimart.ai/cn/api-reference/texts/models/list)

## 6. 长任务、幂等与计费方案（尚未实现）

建议先为新媒体单独建立任务服务，再考虑把APIMart图片迁移进去。保留旧的图片表、RPC和恢复规则，可降低升级与回滚影响。

### 6.1 任务状态与短请求

设计状态可为：draft → submitting → submitted/pending → processing → completed/failed/cancelled；另设 submission_unknown 表示提交结果未知，需要对账。本站状态与上游原始状态分开保存。billing_status独立于任务状态，避免“渲染成功但结算失败”被错误改成生成失败。

提交接口只完成鉴权、参数校验、积分预约、调用上游创建任务与保存上游ID，然后尽快响应。刷新页面通过本站任务ID恢复，不重新生成。前端只在有活动任务、页面可见且当前工作区需要时查询，使用退避、请求去重和断线恢复，后台有独立对账触发机制；具体worker或调度方案在下一阶段选型，不能声称当前已有持久队列。

现有图片十分钟过期退款只适用于旧图片任务，不用于新视频/音乐。新媒体的浏览器超时不能直接退款；应查询真实终态或进入人工对账。上游已完成但本站媒体获取失败，也不应自动重发一次付费生成。

### 6.2 幂等边界

- 客户端为一次用户意图生成稳定request_id；重试同一请求复用该ID，重新创作才创建新ID。
- 数据库为用户与request_id建立唯一约束；服务端保存请求参数指纹，禁止同ID换参数；并发占用与状态迁移使用事务或条件更新。
- 预扣、结算、退款使用各自唯一幂等键；重复、乱序通知不得重复扣费或让终态倒退。
- 上游POST发出后若响应丢失，进入submission_unknown，不自动再次提交；本地数据库幂等并不能消除上游重复扣费。
- APIMart部分模型页面提到Idempotency-Key，但所选三款视频和Suno的统一幂等窗口、参数指纹、查询恢复契约仍需确认。未确认前不承诺端到端exactly-once。
- 不发明取消接口或承诺“停止等待即退款”。若将来支持取消，需要验证上游取消结果与结算行为。

### 6.3 新媒体定价

先确认账号模型权限、实时实付价格、分组倍率、失败退款与预扣规则，再配置本站售价。APIMart的cost/credits_cost不是本站积分，不直接换成现有图片“1积分/张”。

视频可能按秒、分辨率、音轨计费，音乐可能按请求/版本计费；具体单位以所选模型实付契约为准。预约记录保存模型、计量单位、参数、价格版本、兑换率和金额上限，结算不能随管理员后来改价而改变。使用整数最小货币单位或精确数值类型，不用二进制浮点累计财务值。

预览阶段统一使用“计费待配置”等真实状态，不给出未经确认的本站积分价或美元报价。当前三个图片模型的原价格保持。平台积分失败说明继续使用用户指定三条固定文案；上游错误原文单独脱敏展示，不根据关键词擅自确诊审核、余额或高峰。自带Key继续沿用其既有错误说明。

## 7. 数据设计与权限方案（只设计，不建表）

建议新增表和字段如下，最终名称、索引和约束经本地数据库验证后再确定。本轮不创建迁移、不执行SQL、不调整生产数据。

| 拟议对象 | 用途与建议字段 |
| --- | --- |
| `media_jobs` | id、user_id、request_id、media_type、operation、billing_mode、provider/model、provider_task_id、request_fingerprint、参数白名单、上游/本站状态、billing_status、价格快照、预扣/实扣数、时间与脱敏错误 |
| `media_outputs` | 关联media_job、输出序号、类型/MIME、时长、尺寸、临时来源到期时间、转存状态；若启用转存，记录私有storage_key而非永久公开URL |
| 媒体积分流水关联 | 当前credit_transactions.job_id指向generation_jobs，未来通过向后兼容新迁移扩展media_job关联，避免伪造图片任务或破坏旧外键 |
| 媒体提示词保留 | 可以单独保存七天纯文本，或给media_jobs受控文本字段；历史API只返回文字白名单，清理任务覆盖歌词等新增文本范围需明确 |

公开schema中的表启用RLS，按认证身份校验所有权。前端不传可信user_id，不依赖可编辑user_metadata判定管理员。service_role仅存在服务端；任务状态、上游ID、结算字段及输出归属由服务端写入，普通用户不能直接修改。若开放本人读取，策略使用auth.uid()与owner匹配，不只检查authenticated角色；更新策略同时约束现有行与更新后归属。

优先采用invoker和受控服务端调用。确实需要security definer时固定search_path，收紧执行角色并审查内部授权，不能靠该属性绕开访问错误。新增索引至少考虑user_id/created_at、provider/provider_task_id唯一性、活动任务next_check_at；公开目录不得携带平台Key或完整上游配置。

实际开发数据库时先在本地验证迁移、RLS、权限、并发结算与回滚，运行advisors。使用新迁移保留历史表/函数和旧图片接口的兼容，不修改已执行迁移文件。只有之后用户明确授权部署，才考虑执行生产迁移。

权限依据：[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)、[Storage访问控制](https://supabase.com/docs/guides/storage/security/access-control)。

## 8. Key、上传、媒体与文字历史

### 8.1 平台与自带Key

平台Key由服务端环境提供，浏览器只选择服务端允许模型；不能用浏览器请求覆盖平台Key、提供商地址或售价。新APIMart平台配置将来独立设置，不复用旧图片Key并假设同属一家服务商。

自带Key继续只存sessionStorage，不写数据库、localStorage、日志、任务metadata或历史。请求预览只显示非敏感参数，不包括Key、Authorization或用户会话。异步任务恢复时，如果用户已关闭标签页、清空Key或切换身份，不假定服务器持有可长期使用的用户Key；可让用户重新提供同一账户凭证后鉴权查询，或先限定为会话内使用。永久加密托管凭证属于另一个需要明确授权和设计的功能。

### 8.2 上传与媒体

APIMart参考图上传支持JPEG/PNG/WebP/GIF，最大20MB，返回公开URL，72小时有效。具体模型还可能只支持JPEG/PNG或10MB，必须按模型进一步校验；上传成功不等于模型接受。[上传文档](https://docs.apimart.ai/cn/api-reference/uploads/images)

视频与音乐素材上传不能照搬图片Base64请求。本站当前Flask请求体默认24MiB，且部署平台还可能有独立请求体限制；上游允许的文件大小不代表当前本站上传链路已经支持。后续需要选择浏览器直传私有Storage或提供商可用的上传链路，验证MIME/大小/时长、签名有效期、模型公网访问及用户隔离，再显示可用上限。

从公网URL获取资产时限制协议、目标域名/地址、重定向、下载大小和超时，防止SSRF。给上游使用的签名链接有效期须覆盖排队与执行；私有文件不能临时改成永久公开桶。播放和下载优先使用短期签名URL，浏览器直接读取媒体，不通过Vercel反复搬运大文件；外部URL请求不携带本站Authorization。

上游输出链接期限按模型和expires_at处理，不能统一称七天有效。是否转存、存多久、每日媒体存储/流量预算、失败重取与用户主动删除需单独确定；本轮不新增媒体存储。原图片清理Cron与新媒体存储规则分开，不擅自延长原图保存，也不删除用户本机画布作品。

### 8.3 七天纯文本历史

已有七天历史的含义仍是提示词文字，不是图片/视频/音乐作品库。`GET /api/history` 当前只读取generation_jobs中的本人文字；新媒体没有因此自动拥有云端历史。

未来扩展时保持认证本人、滚动7×24小时、稳定游标、private/no-store和文字字段白名单；不把原图、封面、缩略图、媒体URL、上传文件名、Key或请求头混入历史。访客仍只在当前浏览器保存七天文字，不上传或自动合并进账号。

现有 `20261021005342_prompt_text_retention.sql` 仅清空generation_jobs.prompt；不能误以为它也会清理新表、歌词或参数JSON中的副本。新增文本应避免重复持久化，确需保存的文字另设明确保留和清理范围。已有图片Cron与七天文字Cron保持独立。

## 9. Webhook安全与文档疑点

APIMart通用回调约定要求在提交体顶层填写webhook基础地址，服务商自动拼接`/callback`，只推最终completed/failed。示例payload是任务对象本身，没有任务查询响应的code/data外层。约十秒未确认2xx或返回5xx会按约10/30/60秒重试、最多三次；4xx不重试；要求按task_id去重。[Webhook文档](https://docs.apimart.ai/cn/api-reference/tasks/webhook)

文档要求生产验签，但没有公开签名头名、签名算法、时间戳、secret配置或轮换约定。示例也只留TODO。当前不能写出可信验签实现，更不能相信任意POST里写completed就给用户结算。初期优先服务端鉴权轮询；将来回调可仅作为触发可信查询的信号，具体仍要有访问控制、频控和幂等，签名契约确认后再正式启用。

其他尚未解决的公开文档差异：

- 上传页末尾旧示例使用`/v1/images/generations/{id}`和顶层id，与当前统一任务页冲突；按当前模型提交结构和`/v1/tasks/{task_id}`设计。
- 音乐专页使用`/v1/music/tasks/{task_id}`与result.music；通用Webhook页称音频result.audios，音乐是否支持同一回调机制及实际payload需确认，不能提前统一解析。
- 统一任务页包含pending/cancelled，提交页另有submitted；音乐还可能返回unknown，须保留原始状态并防止未知状态被误当成功。
- 旧搜索缓存的doubao-seedance命名与当前索引seedance命名不同，以下游当前目录及账号模型列表为准。
- Seedance2.0正文时长4–15秒与对照表5–15秒不一致；该模型不列入首轮视频最小表单，后续先用保守档位再核实。
- GPT2.5蒙版说明出现50MB与4MB两种大小标准；后续蒙版接入先按严格4MB及Alpha透明通道、原图同尺寸要求校验，仍需实测。
- 上游幂等、取消、结果保留、音乐返回首数、错误退款和模型实际供应状态不能只凭示例保证。

本轮本地无法接收真实公网Webhook；不为了演示而暴露本机端口、配置公网隧道或开通线上回调。

## 10. 分阶段实施与验收

| 阶段 | 交付与边界 | 验收重点 |
| --- | --- | --- |
| A，本轮 | 本地新版导航与图像/视频/音乐三类工作台；原图像继续运行；新媒体非敏感请求草稿、模型参数与说明；源代码回滚基线 | 桌面/移动端布局、键盘访问、切换不丢图像状态、模型参数互斥、没有生成网络调用或伪造结果 |
| B，本地适配 | APIMart服务端适配器、输入校验和模拟响应；先文生视频、基础音乐 | 区分通用任务与音乐专用任务；submitted不算成功；超时、失败、未知状态与错误脱敏；自带Key不扣本站积分 |
| C，本地数据 | 新媒体任务表、RLS、计费预约/结算、可靠恢复、对账与清理设计，准备新迁移 | 跨用户越权、重复/并发/乱序结算、响应丢失、长任务、旧图像十分钟恢复隔离、七天文字保留 |
| D，实际联调 | 在用户明确授权的测试账号和支出范围内，少量真实调用；核对价格、文件可播可下载、退款和权限 | 真实上游参数/音轨/时长/错误、计费差额、退出后恢复、文件过期、浏览器与网络兼容 |
| E，发布候选 | 变更说明、迁移和回滚步骤、媒体预算、生产配置清单及最终验收 | 只有用户明确要求部署才进入线上发布；不把本地测试通过当成发布授权 |

下一步先让用户审阅本地界面和操作路径，再确认首批模型、使用平台积分还是自带Key、是否要保存媒体、保存期限及实际售价。接入前以安全方式核对真实账号的`/v1/models`和实时价格，不在聊天、Git、截图或请求草稿暴露Key。价格和媒体预算未确认前，新媒体保留预览状态。

## 11. 文档来源与已知验证边界

APIMart公开索引：[中文API目录](https://docs.apimart.ai/_llms/zh-hans/api.txt)、[总目录](https://docs.apimart.ai/llms.txt)。本方案阅读并交叉核对了模型页面、任务、上传、音乐和元数据文档；正文已为对应约束提供直接链接。

已排除能力备忘：早期调研还阅读过[语音转写](https://docs.apimart.ai/cn/api-reference/audios/whisper-1)和[文字转语音](https://docs.apimart.ai/cn/api-reference/audios/tts)文档；用户随后明确不要独立音频能力，因此这些内容已从界面、模型矩阵、数据范围及后续路线中移除，不列入本轮或后续计划。视频自身音轨和音乐作品仍属于对应视频/音乐能力。

仓库现状以稳定提交和相关源码/迁移为证据。此次只做源码阅读、公开文档研究和本地文件修改，不查询真实用户数据、不验证真实账号Key、不执行新数据库迁移、不发送媒体生成请求。因此文档中的新媒体表、适配器、持久任务、结算、存储、Webhook和后续阶段均为方案，不是已上线或已完成的后端功能。
