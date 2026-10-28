# Suno 音频与音色功能接入评估

2026-10-25 更新：用户截图指定的前三项已完成本地实现和隔离验证，未部署、新操作迁移未应用正式库。普通参考创作与音频改编采用每次 2 网站积分，其他工具不沿用此价格。具体状态、限制及本地预览见 [音频创作说明](suno-audio-creation.md)。下文保留原调研时点的结论。

核对日期：2026-10-24（北京时间）。本次只阅读公开文档、对照现有代码，没有调用收费接口，也没有把下列功能接通或发布。当前正式网站已上线基础音乐生成，本文件是后续功能评估。

## 最值得先做的功能

| 功能 | 文档依据与入口 | 网站可以提供的操作 | 状态与边界 |
| --- | --- | --- | --- |
| 本地音频导入 | [上传音频](https://docs.apimart.ai/cn/api-reference/audios/suno/upload) `/uploadTask` | 在描述上方增加“添加音频”，试听后作为后续操作的素材 | 接口只接JSON公网直链，不能直接传本地文件/Blob；需先建立网站音频上传与临时读取通道。图片上传的16MB限制不能直接当音频规格 |
| 参考音频创作 | [灵感生成](https://docs.apimart.ai/cn/api-reference/audios/suno/inspo) `/inspo` | 选择1–4段音频作为参考，再填写风格和歌词生成新歌 | 可接；音频用URL，不先导入任务。不是保证逐音符复现的工具，不能承诺精确复制 |
| 上传后翻唱/改风格 | [上传并翻唱](https://docs.apimart.ai/cn/api-reference/audios/suno/upload-cover) `/uploadCover` | 上传旋律，生成另一风格版本 | 可接；直接收音频URL，无需额外先调用uploadTask；文档建议原音频不超过8分钟，该建议不等于硬性大小上限 |
| 音频续写 | [上传并延伸](https://docs.apimart.ai/cn/api-reference/audios/suno/upload-extend) `/uploadExtend`、[已有歌曲延长](https://docs.apimart.ai/cn/api-reference/audios/suno/extend) `/extend` | 选择续写起点，继续唱或继续生成伴奏 | 可接；上传延伸起点至少1秒且小于源长度，用户已生成歌曲用源任务+原始音轨序号 |
| 保存歌手Persona | [Persona](https://docs.apimart.ai/cn/api-reference/audios/suno/persona)、[歌曲生成](https://docs.apimart.ai/cn/api-reference/audios/suno/generation) | 在成品上点“保存为歌手”，给它命名，下次创作选择 | 文档有完整链路：源任务+audio_index → result.persona_id → custom=true生成参数persona_id。可选择源片段；不能承诺与真人音色完全一致，或素材无限期保留 |
| 自动写歌词 | [生成歌词](https://docs.apimart.ai/cn/api-reference/audios/suno/lyrics) `/lyrics` | 输入主题→生成歌词→填回自定义歌词编辑器 | 可接；返回文本，不能按music[]歌曲结果解析 |

## “声音”入口需区分的两种能力

- **Persona**有明确可供再次生成使用的ID，适合先落地“我的歌手/音色”选择器。主生成仅在自定义歌词模式下使用persona_id；不能与custom_model_id混用。它复用歌手特征/风格，不保证真人声纹的精确克隆。
- **createVoice**的[创建语音接口](https://docs.apimart.ai/cn/api-reference/audios/suno/create-voice)可从公开MP3/WAV音轨提取音色，但文档明确目前没有固定result.voice_id约定，结果不能直接当persona_id传入。应先做一笔有明确费用上限的真实联调，确认返回和后续复用方式，再提供“上传自己的声音→直接用于新歌”的完整功能，不能仅据接口名称就声称闭环可用。
- [Vox](https://docs.apimart.ai/cn/api-reference/audios/suno/vox)是历史/片段用途，新Persona流程不要求先建Vox，避免用户无意义多跑一次任务。

## 后续可以扩展

| 功能 | 来源 | 注意 |
| --- | --- | --- |
| 给伴奏加人声、给清唱加伴奏 | [add-vocals](https://docs.apimart.ai/cn/api-reference/audios/suno/add-vocals)、[add-instrumental](https://docs.apimart.ai/cn/api-reference/audios/suno/add-instrumental) | 源任务必须来自uploadTask，不能直接拿普通生歌任务当源 |
| 指定段落重做 | [replace-music](https://docs.apimart.ai/cn/api-reference/audios/suno/replace-music) | 需时间选段UI，保留未替换部分；具体输入/输出按实际结果验证 |
| 分离人声/乐器 | [stems](https://docs.apimart.ai/cn/api-reference/audios/suno/stems) | 可按文档列举的stem_type提取轨道，不能把它理解成所有乐器一次全返回 |
| 同步滚动歌词 | [aligned-lyrics](https://docs.apimart.ai/cn/api-reference/audios/suno/aligned-lyrics) | 从时间轴结果驱动播放器，不用客户端猜时间 |
| 服务端格式转换/下载 | [download](https://docs.apimart.ai/cn/api-reference/audios/suno/wav) | 新路径为/generations/download，可选MP3/M4A/WAV；这是收费转换任务。与现在直接下载已返回音频URL的免费读取按钮分开，多次提交会多次计费 |
| 专属模型 | [create-model](https://docs.apimart.ai/cn/api-reference/audios/suno/create-model) | 6–24条参考音频，独立训练任务，完成后model_id用于custom_model_id；不是自定义歌词，计费档位不同，建议后做 |

公开目录还列有音效、风格标签增强、剪裁、删除片段、淡入淡出、变速、拼接、两首混音、采样成歌、MIDI、BPM和MP4等操作。本次主要细读19页，未对这些目录中的全部工具逐一进行真实联调，不能声称所有能力已经可用。Flow Music也有独立上传、延长、替换、Cover和分轨页面，可另行按其clip_id协议实现，不能直接复用Suno任务引用。

## 接入顺序建议

先做“添加音频、自动歌词、翻唱/续写、参考音频生成”，再做“保存与选择Persona”。第二阶段做分轨、加人声/伴奏和局部重做。createVoice及自定义模型等先验证真实返回与费用，再决定是否开放。

现有基础生歌保持每次2网站积分，不因这次调研改变。新工具各自是独立调用，可能有额外费用；Max模式文档为普通售价2倍，训练模型另有档位，不能把所有新操作自动套为2积分。应先明确每类工具的实际成本、失败退款、重复调用及组合操作的计费单位。

## 对当前代码的具体影响

当前music_provider.py只接受基础生成字段，music_jobs主要记录歌曲数量和结算，MusicWorkspace只有基础表单。后续需增加operation、源任务归属验证、原始audio_index、结果类型（音乐/文本/Persona/文件）和操作计费快照，不能把Persona/歌词成功判成“没有返回音频”。上传需音频专用校验/试听/临时存储，不将Key或用户素材地址放进提示词历史。音色库记录账号归属与名称/ID，Key仍只在服务端或自带Key会话中；保留期限先核对服务方，不承诺永久。

文档overview仍写音乐专用查询，但本站此前实测该路由403、通用/v1/tasks/{id}正常。新增任务应保留已有通用查询修复，不能照抄文档把已修复路径改回；不同结果类型需按操作解析。没有做数据库迁移、上线音频/音色按钮或真实收费测试。
