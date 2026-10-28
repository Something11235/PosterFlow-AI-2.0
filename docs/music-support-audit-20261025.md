# 音乐功能文档核对与上线记录

2026-10-25，北京时间。用户授权“确认官方文档明确支持后部署”。已逐项核对最新官方文档及实际发送的请求，完成迁移和正式发布。

| 网站功能 | 明确支持的接口与参数 | 官方依据 |
| --- | --- | --- |
| Suno 文字创作、自定义歌词、纯音乐 | generations；custom/instrumental/prompt，公共版本 v6、v6-wild、v6-mini | [生成音乐](https://docs.apimart.ai/cn/api-reference/audios/suno/generation) |
| 1–4 段参考音频创作 | generations/inspo；audio_urls，tags、weirdness 等参数；不传 custom/instrumental/目标时长 | [参考创作](https://docs.apimart.ai/cn/api-reference/audios/suno/inspo) |
| 单段音频改编、翻唱、换风格 | generations/uploadCover；audio_url；描述模式 gpt_description，自定义模式 prompt/tags，目标时长 duration_s | [上传并翻唱](https://docs.apimart.ai/cn/api-reference/audios/suno/upload-cover) |
| Flow Music 标准版 | generations；model=flowmusic，不发送版本；sound_prompt/lyrics 至少一项，BPM、时长、种子 | [标准生成](https://docs.apimart.ai/cn/api-reference/audios/flow-music/music) |
| Flow Music Lyria 3.5 | generations；model=flowmusic、version=lyria-3.5，其余字段与标准版一致 | [Lyria 3.5](https://docs.apimart.ai/cn/api-reference/audios/flow-music/music-lyria-3-5) |
| 任务进度、音轨播放与下载 | 官方通用 tasks/{id}?language=zh；按返回 progress/status/result.music 处理。下载已有文件不额外提交收费转换任务 | [任务查询](https://docs.apimart.ai/cn/api-reference/tasks/status) |

本地导入/试听是网站自身的素材准备能力：使用私有 Storage 签名上传、字节校验，再向明确接受公网 URL 的两个接口提交短期可读地址。不把本地路径或 blob 地址交给生成服务，也不额外调用收费 uploadTask。

七组规范化请求已程序化核对，只使用文档明确列出的字段。基础生成使用 style/weirdness_constraint/duration，参考和改编分别映射为 tags/weirdness/duration_s，未混用字段。0 权重保留。未启用 Max 加价模式、Persona、自定义训练模型或未接入的工具。

本次补齐了 uploadCover 的明确条件：custom=true 且 instrumental=false 时，前后端均要求歌词，空输入在预留积分/调用上游前拦截。Flow 标准文档没有明确写成“Lyria 3 Pro”，因此展示名改为“标准版”；内部旧标识保留用于任务/历史兼容，不冒充发送给上游的版本。

20 MiB、1 秒至 8 分钟、素材 12 小时和每次 2 网站积分均为网站策略；返回两首仍合计 2 积分，上传和试听不收费。成品首数依真实结果展示，不承诺可指定单首。自带 Key 的任意自定义接口/模型属于兼容接入，其服务商支持范围不应宣称由这些文档保证。上游已识别错误分类成中文；未知失败仍保留用户此前指定的兜底文案，不将其当作已证实的具体拒绝原因。

正式发布 dpl_HVLHoB7nczkKZgwnYamsUGg6TatN，www 与根域名已核对，主脚本 index-DkUR-bMt.js。生产迁移 20261024172815/suno_audio_operations；原音乐任务、原计费函数和旧账目流水前缀完整保留，正常用户注册引起的余额/流水新增没有被覆盖。没有测试扣款或真实收费生成。

验证包括 222 Python、104 Node、lint/build、隔离 SQL、七种请求字段核对、正式环境真实签名上传/私有读取/无登录签名读取/定点删除，以及候选和正式资源的 1440/375 浏览器操作。浏览器生成与账户使用隔离替身，不能称为已实测真实生成音质或新操作的实际账号权限。记录、快照与截图见 artifacts/suno-audit-release-20261025。前正式 dpl_8fjuVRJzTkVUVBj1t7Ud9RQjBviG 保留；回滚只切代码，不恢复旧用户/余额/流水数据库。
