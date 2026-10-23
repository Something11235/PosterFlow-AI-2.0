# 2026-10-22 本地升级说明

## 2026-10-22 当前状态（优先于下方历史记录）

后续开发工作目录为 `D:\Projects\Codex工作台\AI全功能生成工作台`。原站 `D:\Projects\Codex工作台\AI绘画程序` 已发布自动总账与10.11统计更新，main/origin/main `e8679b65db349fa670046bca6e56b3a959ee1333`，Vercel `GExwsjqo3uPQYSde4CKM4kjE55CG`。Supabase迁移远端版本 `20261022011529` / admin_automatic_ledger 已应用，勿重跑。

已将原站从741d77a之后的12份更新源码同步到本目录并验证SHA256，包含自动总账、6000字符计数、单张16 MB提示和平台错误建议，保留新版App/布局/开发配置。同步前备份位于旧目录 `artifacts/upgrade-sync-20261022/upgrade-before-sync.zip`。本目录仍是独立仓库 `codex/multimedia-studio`，无remote、无生产.env/.vercel绑定，不复制生产凭证。

新版沿用原版深蓝/蓝色风格，入口与模型顺序为图像→音乐→视频。图像7个：GPT Image 2.5 Flare、GPT Image 2.5 Sunburst、GPT Image 2、Nano Banana 2.1、Nano Banana Pro、grok-imagine-image-2.0、grok-imagine-2.0-ext。音乐2个：suno、flowmusic。视频5个：wan3.0-video、seedance-2.5、seedance-2.0、MiniMax-H3、MiniMax-H3-Max。模型文档跳转已移除。视频仅模型预览，暂不编辑参数/保存视频草稿/生成；flowmusic仅预览。Suno保留原有会话草稿和JSON导出，不发真实生成请求。新增候选的本地ID不是已核对的上游API模型标识；以后接入时再核对协议和计费，不得猜参数。

119 Python、46 Node、lint/build、桌面1440/手机375模拟浏览器通过；模型14项、无文档链接、顺序/配色、无溢出、音乐模式切换与草稿、图像提示、无真实请求/扣费验证通过。只读预览4174；开发前端3001/后端5001。本轮只发布了原站；新版没有部署。没有下一次明确部署指令，不得自行发布。详情docs/project-directories.md、docs/studio-refresh-20261022.md、artifacts/studio-refresh-20261022/。


## 本地预览与回滚

运行 `npm run build --prefix frontend` 后执行 `npm run preview:studio --prefix frontend`，访问 http://127.0.0.1:4174 。只读预览不连接真实认证、数据库或生成接口；常规开发环境需另配开发凭证，不能直接复用生产密钥。原图像功能代码保留，现有3个GPT模型之外的4个新图像模型尚待接入。

同步前完整保留升级中修改，备份清单 `artifacts/upgrade-sync-20261022/sync-manifest.json` 位于旧项目。要恢复此前绿色界面，应先保存本轮开发成果，再从备份逐文件恢复，禁止破坏性reset/clean。原站线上回滚到e8679b6的前一版d970c96/8yP5qjcPm1PJRkBj5RkTWKJkiFKi；若恢复手动总账，另建迁移恢复旧get/save函数，不能删除账目。
