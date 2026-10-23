# 模型服务商与积分约定

用户于2026-10-23明确指定：从本次开始，后续新增模型默认使用 [APIMart 中文文档](https://docs.apimart.ai/cn) 对接，除非用户另有说明。

- 已有 `gpt-image-2.5-flare`、`gpt-image-2.5-sunburst`、`gpt-image-2` 暂时保留现有图片服务商、Key、地址、参数协议和1积分单价，不迁移到APIMart。
- 本次新增 Nano Banana 2.1、Nano Banana Pro、grok-imagine-image-2.0、grok-imagine-2.0-ext，统一每成功保存1张图消耗1网站积分；批量按实际张数结算。不能把APIMart账户扣费数值当作网站积分。
- 音乐 Suno / Flow Music 仍是每首2网站积分，保持独立音乐服务配置。
- APIMart 新模型必须先核对对应文档页的实际模型ID、参数和任务协议，不能仅凭界面名称假定兼容OpenAI同步返回。别名映射应写明，未验证能力不可展示为已可用。
- 平台服务端 Key 使用独立变量，不能复用原图片站密钥，不能写入前端包、URL、日志、任务表或历史。自定义Key仍遵循现有会话存储边界。
- 本约定不授权部署、生产迁移或真实付费测试；发布沿用既有项目并遵循 [发布与回滚说明](multimedia-release-and-rollback.md)。

以后新增模型时先读本文件和对应官方文档。用户后续的明确指令优先于本约定。

## 项目与授权（2026-10-23 用户补充）

正式升级沿用已付费的 Supabase **PosterFlow AI**（`ezimtgfppvqkkzpjeojg`），以及现有 Vercel、Resend 和域名。**PosterFlow-AI-2.0**（`eiwwokxkbrowosahfaxv`）是此前的免费本地测试库，不作为本次升级的必需环境；不再要求用户切换或增加其连接器授权，也不新建项目。连接器目前已能访问 PosterFlow AI。

源码继续在 `D:\Projects\Codex工作台\AI全功能生成工作台` 开发，原版源码与恢复点保留在原目录。使用现有项目不等于可以直接向生产库运行测试 fixtures、清库或覆盖用户余额。自动测试仍用隔离数据库、模拟账号与上游；正式迁移按发布说明只补缺失项。本次没有修改真实 `.env` 或云端配置，旧本地 `.env` 中的测试库配置不会随这个约定自动切换，不能将其用于正式构建；正式发布沿用 Vercel 已有生产变量。
