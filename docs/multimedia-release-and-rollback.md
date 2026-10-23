# 全功能工作台发布与回滚说明

准备日期：2026-10-23（北京时间）。本文记录部署准备，不表示新版已上线。继续使用原有 Vercel、生产 Supabase、Resend；本轮没有创建项目、修改云端配置或执行生产迁移。

## 固定恢复点

| 项目 | 值 |
| --- | --- |
| 用户识别名称 | 2026-10-23 全功能升级前稳定版 2416911 |
| 正式网址 | https://www.posterflow-ai.xyz/ |
| 稳定代码提交 | `2416911f90a0ee2dd5c2886d3ab3344d45244ffd` |
| Vercel 恢复目标 | `dpl_fDjCMNzLTqruZUuuA7i2FtbY1cV5` |
| Vercel 项目 | `posterflow-ai` / `prj_eyJWm3sya1TjEjaUsvM3g3XK7PLU` |
| Vercel 团队 | `team_TOWSZDwF64wxXycLZ3oNxGBc` |
| 原站生产 Supabase | `ezimtgfppvqkkzpjeojg` |
| 历史测试 Supabase | `eiwwokxkbrowosahfaxv`，用户确认是免费测试库，本次升级不依赖其授权，不能带入正式构建 |
| 原站本地 Git 标签 | `stable/before-multimedia-20261023`，当前仅本地保存 |
| 独立备份目录 | `D:\Projects\Codex工作台\发布备份\20261023-before-multimedia-2416911` |

备份含稳定版源码 ZIP、可独立恢复 Git 历史的 bundle、新版合并前工作区源码 ZIP，以及 SHA-256 清单。已校验 ZIP CRC、bundle 完整性和稳定版来源。源码备份不包含 `.env`、密钥、数据库业务记录、Storage 图片或 SMTP 设置；不能把它当作整站数据备份。完整历史优先以 bundle 为准，源码 ZIP 的换行符可能遵循 Windows Git 配置。

用户最新确认：后续沿用已付费的原 PosterFlow AI 项目，不再要求为旧 2.0 测试库切换授权。本地源码目录和新版 GitHub 仓库名字中的 2.0 不代表必须连接该测试库。连接器已只读验证原项目为 ACTIVE_HEALTHY，尚无 music_jobs、apimart_image_jobs 或 credit_transactions.music_job_id，远端迁移最新为 20261022011529；本轮未改生产结构或数据。本地旧 `.env` 的测试库配置尚未切换，不能据此启动生产数据联调或上传该配置。

用户以后可以说：

> 把正式网站回滚到「2026-10-23 全功能升级前稳定版 2416911」，保留最新的用户、积分、充值和账目数据。

## 这次准备已做什么

- 保护新版原有未提交的音乐连接修复、错误提示和界面修改，先快照后合并。
- 将原站提交 2416911 的五文件补丁合入新版：独立备用下载、画布失败项保留及单独重试、并发与身份隔离、对应测试和文档。保留新版 Studio；原站应用源码未改。
- 新版充值说明已经包含用户原文，并有自己的滚动布局，不用旧组件覆盖。
- 生产库只读核对：尚无 music_jobs 和 credit_transactions.music_job_id；已有迁移记录与本地历史版本号不同，不允许直接 db push 重放。
- 在隔离 PGlite/PostgreSQL 中载入生产库 9 个实际 RPC 定义并逐个核对哈希，然后应用音乐和权限迁移；验证旧版 RPC、注册、积分、退款、总账、跨版本处理中任务，以及音乐幂等和权限。
- 显式排除 frontend/.env 和 frontend/.env.* 上传，避免 CLI 部署带入本地开发库配置。

本地隔离数据库不模拟 Supabase Auth 网络、Storage/Vault/http/cron 服务及真实 APIMart；云端读写与真实付费模型联调仍需正式发布阶段验证。测试结果在 `artifacts/release-prep-20261023/`，其中原图浏览器验证只用合成图片、模拟端点，不实际扣积分。

## 正式发布顺序

1. 重新确认当前正式域名及部署，记录期间发生的配置变更；保留上述固定恢复点，另记最新部署。不要删除旧部署；检查 Vercel 部署保留设置，源码 bundle 作为独立后备。
2. 核对生产数据库可用备份的时间与恢复方式。需要精确发布前数据点时另外执行受保护的数据备份，确认内容和可恢复性；Storage 对象另行备份。此项当前没有执行，不可假报已完成。
3. 提交经审查的新版本候选代码，记录实际 SHA。本地有原开发者未提交修改，不能 reset/clean；提交范围必须包含这些修复及本轮合并。新版 GitHub 仓库是 PosterFlow-AI-2.0，原 Vercel 项目仍关联旧仓库，推新版仓库本身不会自动更新原网站。
4. 选择把新版本地目录链接到**已有** Vercel 项目，以候选生产部署暂不分配正式域名的方式构建；不创建项目、不提前重绑 GitHub 来源。提交前检查 CLI 实际上传文件，排除本地 .env、artifacts、临时媒体和依赖缓存。本次验证 dist 使用合成 publishable key，不能作为正式预构建产物上传；由 Vercel 用其生产环境变量重新构建。
5. 原有生产 SUPABASE_URL、浏览器配置、图片服务 Key/地址/价格、Resend SMTP 与域名保持既有设置；新功能只增加必要变量。平台音乐需要 `APIMART_MUSIC_API_KEY`，新增图像模型需要 `APIMART_IMAGE_API_KEY`；受保护的后台对账分别需要 `MUSIC_RECONCILE_SECRET` 和 `APIMART_IMAGE_RECONCILE_SECRET`。未配置的平台能力必须如实显示不可用，不能宣称已接通。不得上传开发库的 .env 或将服务端 Key 写入 VITE_ 变量。
6. 在原生产库只补下面三份经审查的迁移，逐份核对来源哈希与远端迁移记录，事务执行、失败立即停；其余既有迁移不重放：
   - `supabase/migrations/20261022164535_music_generation.sql`：增加独立音乐任务、可空 music_job_id、音乐 RPC。
   - `supabase/migrations/20261023081514_restrict_internal_auth_access.sql`：收紧注册去重表和触发器函数权限，保持触发器创建资料/积分账户。
   - `supabase/migrations/20261023115033_apimart_image_jobs.sql`：新增四个APIMart图像模型的任务跟踪、每张1积分白名单和防止异步任务被旧超时回收退款的保护。原三个模型分支的价格不变。
7. 候选部署先验证注册/登录/邮箱、原图像模型和价格、参考图、原图/画布、总账，再验证音乐真实返回与按首结算。连接生产库的候选部署也会改真实数据和耗费额度：只用指定测试账号，不批量运行开发 SQL fixtures。付费验证须在明确支出范围内进行。
8. 检查音乐和新增异步图像回滚时的任务接管方式：保留受 Vercel 访问保护的新版候选地址，验证站主可以在正式域名切回旧版后继续通过此地址查询/对账；平台入口分别需要 MUSIC_RECONCILE_SECRET、APIMART_IMAGE_RECONCILE_SECRET。当前尚未配置线上调度和此接管流程，不能宣称已具备无人值守对账。自定义 Key 不托管，需要用户保留本次会话或到上游核对。
9. 验证通过后才将正式域名指向候选生产部署。记录新部署 ID、SHA、迁移来源、配置变更清单和原恢复目标。随后检查首页、health、静态资源哈希与关键流程。最后再决定是否把原 Vercel 项目的 Git 来源切换到新版仓库；这与首发解耦，并记录如何改回。

## 回滚操作

1. 记录故障和当前新版部署地址；保存必要的任务状态。不要先删任务或把“未知”状态当失败退款。若已进入生产音乐调用，需要在本次回滚同时安排受保护新版部署继续处理已受理任务。
2. 在现有 Vercel 项目的 Deployments/Instant Rollback 选择固定目标 `dpl_fDjCMNzLTqruZUuuA7i2FtbY1cV5`，核对 www 和根域名后执行。也可由执行代理按当前 CLI 文档和团队范围执行同一目标；不要含糊回滚到“上一个”（可能已不是此稳定版）。
3. 保留 Supabase 现有用户、余额、充值、每日记录、流水、音乐任务与新增字段。兼容验证表明旧 RPC 可使用扩展后的结构；正常代码回滚不需要回滚数据库。新音乐表即使旧 UI 不显示也保留。
4. 旧程序不包含音乐及APIMart异步图像 API：不能指望正式域名切回后仍会自动结算这些任务。通过保留的受保护新版部署核对已知任务，明确失败按幂等规则退款，完成按实际首数或成功保存的图片张数结算；submission_unknown 无上游编号时先核对上游，不重新发起收费 POST、不自动退款。自定义 Key 的任务由用户会话/上游辅助核对。持续处理音乐 awaiting_balance，以及图像 saving/processing 状态，不能只检查 reserved。
5. 检查正式首页与 health、原图/下载/画布、登录、管理员总账和余额。确认切回的是稳定版构建，不是只有前端静态页面。
6. Vercel 的回滚会停止生产域名自动分配；未来重新发布需明确重新 Promote。Git 来源、项目环境设置、Supabase/Resend/上游配置不会随代码自动完整恢复，需按变更清单逐项检查，不能盲目覆盖为旧值。

如果旧 Vercel 部署已不可用，从 bundle 在**新目录**恢复稳定代码，再链接同一 Vercel 项目、沿用正确生产配置重新构建发布。恢复示例：

```powershell
git clone "D:\Projects\Codex工作台\发布备份\20261023-before-multimedia-2416911\stable-history.bundle" "D:\Projects\Codex工作台\AI绘画程序_稳定版恢复"
git -C "D:\Projects\Codex工作台\AI绘画程序_稳定版恢复" switch --detach "stable/before-multimedia-20261023"
```

目标目录须不存在，禁止对现有开发目录执行 reset、clean 或覆盖恢复；bundle 不含环境密钥，不能仅解压源码就当作完成生产恢复。

整库恢复只用于确认的数据损坏等特殊事故，必须先保留事故后的合法用户和交易数据、评估合并方式，再单独执行；它不是普通网站回滚步骤。

## 官方参考

- [Vercel Instant Rollback](https://vercel.com/docs/instant-rollback)
- [Vercel 候选部署与 Promote](https://vercel.com/docs/deployments/promoting-a-deployment)
- [Supabase 数据库备份边界：不包含 Storage 对象](https://supabase.com/docs/guides/platform/backups)
