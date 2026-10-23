# APIMart 新增图像模型

本次只在 `AI全功能生成工作台` 接入。原图像接口、原三个模型及其平台Key/单价保持原样。服务商长期约定见 [模型服务商约定](model-provider-policy.md)。

## 模型与支持范围

| 显示名称 | APIMart 请求 model | 本站单次出图 | 本站参考图 | 清晰度 |
| --- | --- | --- | --- | --- |
| Nano Banana 2.1 | `gemini-nano-banana-2.1` | 1–4 | 0–8 | 1K / 2K / 4K |
| Nano Banana Pro | `nano-banana-pro`，官方版别名，对应 `gemini-3-pro-image-preview-official` | 1 | 0–8 | 1K / 2K / 4K |
| grok-imagine-image-2.0 | 同显示名称 | 1–4 | 0–3 | 1K / 2K |
| grok-imagine-2.0-ext | 同显示名称 | 1–4 | 不支持，文生图专用 | quality（质量模式，不是像素档） |

所有新增模型均为每张1网站积分，包括可选的清晰度档位。本站批量上限和参考图上限可以比上游低；不绕开Pro单张限制拆出多次收费调用。提示词继续使用6000字符、参考图继续单张16MiB早检及既有上传压缩。参数不支持时在积分预留前拒绝，不静默删除参考图或忽略蒙版。当前未接入新模型的蒙版/分层编辑协议；局部精确蒙版继续使用原有支持该功能的模型。

尺寸转成上游的比例，而不是把原有像素尺寸字符串直接发过去。Grok官方用 `aspect_ratio`，其余用 `size`；自定义宽高只在能精确对应受支持比例时接受，实际输出像素以上游为准。Grok Ext省略尺寸时采用1:1，且不传公开 `quality` 字段。Grok官方的 @图1–3 转换成文档中的 `<IMAGE_0>`–`<IMAGE_2>`，保持参考图顺序。

## 异步任务与保存

浏览器对原三个模型继续调用原 `/api/generate`、`/api/modify`。新增模型通过 `imageGenerationFetch` 只提交一次 `POST /api/apimart-images/generations`，然后GET本站任务接口。画布和迭代请求使用相同适配；前端等待有期限，超时后不会自动再发收费POST。

服务端提交到固定 `https://api.apimart.ai/v1/images/generations`，查询固定 `/v1/tasks/{task_id}`，兼容文档中的数组 `data[0].task_id` 和新版对象 `data.id`。固定响应版本2026-07-27并传稳定幂等Key；连接错误、409、5xx或不明确响应均不重发POST。

参考图先通过已有鉴权上传通道读取，再上传到APIMart `/v1/uploads/images`，将返回的URL按顺序传入。这避免Grok官方不接受Data URI，也避免本地参考图清理后异步服务找不到图片。参考图上传失败发生在生图提交前，可安全退回预留积分。

新 `apimart_image_jobs` 保存任务ID、所属身份、模型、参数哈希、出图数量、处理状态、原站generation_job_id和保存租约。任务表不存Key、参考图、图片字节、服务商媒体URL、提示词或歌词；登录用户提示词仍进入既有generation_jobs并遵循7天文字清理，图片沿用私有Storage和已有保留策略。

平台任务先在同一事务调用既有reserve RPC预留 `张数×1`，然后创建跟踪行。完成后读取并验证图片、保存原图和缩略图，才按实际数量调用原settle RPC，未生成的差额退回。自定义Key不扣平台积分，登录用户仍记录图像任务；游客按浏览器身份与Key摘要隔离。平台模式拒绝浏览器覆盖Key或地址，自定义模式新增模型只接受APIMart完整地址及Bearer。

保存采用数据库租约和确定性文件名；并发查询不会让两个worker同时结算，下载/存储失败后保留原任务重试，不重新生成。媒体读取固定经验证的公网IP、验证原TLS主机名、不发送任何平台/自定义Key、不跟随重定向，并限制字节与像素大小。只从可信服务端查询结果决定成功数量，不信任浏览器提交的收费参数。

明确的上游终态失败可幂等退款。提交结果不确定、缺少上游任务编号、查询暂时失败或原图保存失败都不能据此判断生成失败；保留预留积分，用户通过图片任务窗口继续查询。无上游编号时需站主核对服务商记录，不能自动退款或自动重新付费提交。

旧超时回收RPC增加对已有关联APIMart跟踪行的排除条件。这样既有三个模型的超时退款继续工作，异步新任务不会在上游仍生成时被提前退款。原生图后端函数体保持，新增blueprint独立注册；SQL只扩展reserve的4个白名单分支，不改变旧3个分支价格或已有任务捕获的单价。

## 配置与迁移

- 服务端 `APIMART_IMAGE_API_KEY`：新增图像模型的平台Key，不使用原 `PLATFORM_IMAGE_*` Key，也不自动借用音乐Key。
- 可选 `APIMART_IMAGE_RECONCILE_SECRET`：保护 `POST /api/apimart-images/reconcile`，每次最多处理4个已知上游编号的平台任务。没有自动创建Cron；未配置的入口拒绝访问。
- 新本地迁移 `supabase/migrations/20261023115033_apimart_image_jobs.sql`：跟踪表、server-only权限、原子begin/apply RPC、白名单和超时回收保护；尚未应用生产库或已有开发库。
- 用户已指定沿用现有付费 Supabase PosterFlow AI（`ezimtgfppvqkkzpjeojg`）；旧 2.0 免费库只保留为历史测试环境，不需要重新授权它才能继续。本地隔离验证不写生产数据，正式迁移和 Vercel 切换按发布步骤进行。
- 自定义Key仍只保存在原图片服务的sessionStorage；后台不托管其Key，关闭会话后需要用户重新配置才能查询对应身份下的任务。

任务恢复通过 `GET /api/apimart-images/tasks` 和 `/tasks/{本站request_id}`，只查看本人。保存完成后可重新加载结果，不发起新生图；原图预览/备用下载/画布/ZIP继续走现有私有图片链路。

发布前必须用正确生产变量构建、核对现有迁移并只补缺失项，不能重跑整套开发库初始化。原稳定版恢复点2416911不变。回滚旧UI时保留新增任务和流水，并通过受保护的新版本部署继续处理未结算任务；旧代码不含这些新API，不能声称回滚后它会自动完成对账。

## 验证边界

单测使用模拟服务商和存储；SQL在隔离PGlite/PostgreSQL中载入原生产RPC定义后实际执行，覆盖新四模型1积分单价、重复/冲突请求、部分结果、租约与错误worker、退款幂等、权限、旧模型回归及异步任务不被旧超时回收。浏览器使用真实构建、合成账号与模拟API，不代表真实上游账户余额、权限或付费出图已验收。当前没有读取真实Key、调用真实付费生成或改云端数据。

## 核对的官方页面（2026-10-23）

- [Nano Banana 2.1](https://docs.apimart.ai/cn/api-reference/images/gemini-nano-banana-2.1/generation)
- [Nano Banana Pro及官方版别名](https://docs.apimart.ai/cn/api-reference/images/gemini-3-pro/generation)
- [Grok Imagine Image 2.0官方版](https://docs.apimart.ai/cn/api-reference/images/grok-imagine-2.0-ext/official)
- [Grok Imagine 2.0 Ext](https://docs.apimart.ai/cn/api-reference/images/grok-imagine-2.0-ext/generation)
- [任务查询](https://docs.apimart.ai/cn/api-reference/tasks/status)
- [参考图上传](https://docs.apimart.ai/cn/api-reference/uploads/images)
