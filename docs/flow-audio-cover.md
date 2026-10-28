# Flow Music 单音频改编

2026-10-25，用户明确授权后已正式上线：dpl_BvDAMbJtdQj2tEqRGs5pP6ukSBJa，www/root 同步，主脚本 index-BxBueQMg.js。正式迁移 20261025041114/flow_audio_cover，43 条原音乐任务及所有原计费函数完整保留，积分仍是整数；发布证据见 artifacts/flow-release-20261025。以下实现、限制和本地验证说明保留。

## 已核实的支持范围

| 网站操作 | 明确支持的接口 | 边界 |
| --- | --- | --- |
| MP3 / PCM WAV 添加与试听 | 本站原有私有素材上传、字节/时长校验与本地播放器 | 本站限制为 20 MiB、1 秒至 8 分钟，12 小时清理，非供应商规格 |
| 将本地音频导入 Flow | `POST /v1/music/generations/uploadAudioFlowMusic`，model=flowmusic、audio_url | 异步返回 task_id，完成后取 result.music[].clip_id；不能把本地路径或 blob 地址交给服务 |
| 标准版音频改编 | `POST /v1/music/generations/coverFlowMusic`，model、clip_id、instruction、strength，可选 title | 标准版不发送 version；strength 0–1，保留 0 |
| Lyria 3.5 音频改编 | 同上，加 version=lyria-3.5 | model 仍为 flowmusic |

依据：[导入音频](https://docs.apimart.ai/cn/api-reference/audios/flow-music/upload-audio)、[标准改编](https://docs.apimart.ai/cn/api-reference/audios/flow-music/cover)、[Lyria 3.5 改编](https://docs.apimart.ai/cn/api-reference/audios/flow-music/cover-lyria-3-5)。文档原文快照见 artifacts/flow-audio-20261025/docs。

没有发现与 Suno /inspo 相同的 1–4 段参考音频创作接口，因此 Flow 仅显示“文字创作 / 音频改编”。本次不开放续写、片段替换、生成歌词、分轨和音乐视频。改编不传 Suno 的歌词、纯音乐开关、variety、目标时长等字段，也没有承诺声音克隆或精确旋律保留。

## 同一意图的两阶段处理

前端只提交一次 `/api/music/operations/flow_cover`。素材校验、服务配置和所有者凭证确认后，用 `begin_flow_cover_job` 原子记录一个音乐任务、原提示词历史及一次两积分预留，再发一次 uploadAudioFlowMusic。添加与试听不提交供应商导入任务。

查询导入任务完成、取得合法 clip_id 后，`advance_flow_cover_job` 通过行锁及原 task_id 对照，只有一次请求能领取改编提交权；事务提交后再 POST coverFlowMusic，避免锁跨越网络请求。阶段为 importing → cover_submitting → generating；保存最终 task_id 后使用既有查询和结算逻辑。导入音频不会作为最终作品展示或提前结算；导入和改编合计成功一次收 2 网站积分，自带 Key 为 0。

重复的请求号、并发查询、旧导入状态响应均不重发收费请求或退回正在改编任务的积分。明确导入/改编失败沿用原结算 RPC 退回一次；提交超时、领取提交权后进程中断、已受理但保存失败均保留待核对状态，不自动重试或退款。未知提交不能靠刷新补发，需人工核对任务编号；没有后台新增自动重试器。

新兼容迁移 `20261025033604_flow_audio_cover.sql` 已在本次发布应用：增加 Flow 阶段和原导入任务 ID，两组 private definer/public invoker RPC 固定空 search_path、仅 service_role 执行，保留 RLS、旧预约/结算/管理员函数及旧账目。改编说明与强度只使用现有七天历史字段，不另存素材 URL、文件、凭证、Key 或重复文本；若导入拖到历史过期，则在提交改编前终止并退回预留。代码回滚只切网站版本，不恢复旧用户或账目数据库。

## 音乐界面补充

“司凤版音乐”使用用户提供的完整英文提示词，加入 Suno 文字描述、自定义风格、参考创作风格、两种改编模式对应的描述/风格，以及 Flow 文字描述和改编描述共七处；点击替换当前对应字段，保留歌词、原 Lo-fi 入口和音频素材。所有按钮均为 type=button，不隐式提交生成。

Suno 两种音频创作下补上用途说明：参考创作用 1–4 段音频启发新歌，改编以单段音频为对象做翻唱/换风格；参数相似不代表调用同一个功能。variety 文档只有 off/normal/high/extra/max 档位，没有量化算法，自动为省略参数；variety=max 不等于未开放的加价 max_mode。

## 验证

231 Python、107 Node 测试、lint/build 通过。隔离 PGlite 跑原图片/音乐/历史/管理员回归、新阶段状态、防重复领取、一次计费、导入不结算、明确失败退款、未知保留、过期历史、自带 Key、归属和实际 anon/authenticated/service_role 权限；所有原函数与原任务内容不变。

真实 Chrome 1440/375 使用实际构建、Flask 和内存 SQL，模拟生成与 Storage：七处灵感填入及歌词保留、点击素材区域添加 MP3、零强度、两版本、草稿、导入进度、自动改编和一首结果两积分均通过，无 JS 异常或横向溢出。额外四个并发查询核对只产生一次导入与一次改编，最终仅结算两积分。未调用正式数据库、未发真实收费生成；不能据此声称已实测供应商账号权限和生成音质。

本地预览 http://127.0.0.1:4178/（音乐创作），数据库桥 4179，均仅 loopback。预览明确标注模拟、不读取 .env、不连接云端；本地 dist 含开发配置，不能直接上传为生产构建。证据见 artifacts/flow-audio-20261025。
