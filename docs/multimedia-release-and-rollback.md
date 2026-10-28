# 全功能工作台发布与回滚说明

## 2026-10-27：当前正式上游优先读取与侧栏更新

已推广dpl_7hwNTrVhRrZUk6svk6etCiK3toEP，主脚本index-Y4HkiKWD.js，https://www.posterflow-ai.xyz/；186文件完整源码与SHA256在artifacts/upstream-delivery-20261026。回退目标dpl_5aBgyA3TXnMb2McQJCPAGA6LbHNR保留此前淘宝购买、历史原图及重复下载。此次无数据库迁移，也未改任务保存/积分结算/清理期限，回退只恢复原来优先读本站原图。

保留本站原图备份，平台APIMart的已完成本人任务尽量复用明确有效的上游原图；只读索引与GET任务查询，不取任意用户历史或保存用户Key。浏览器失败/跨域/过期/403/404/超时/格式不符自动走独立备份签名，备用下载固定绕过上游；自带Key任务及其它通道维持备份读取。客户端编号不能冒用账户user-命名空间，源选择只信实际登录用户。前后端原图缓存仍账户隔离、内存存储，列表只加载缩略图。

同时替换淘宝蓝色方码及指定文案，左侧新增QQ交流群二维码弹窗，管理员兑换码放到最底部；桌面侧栏可折叠为图标栏并记住UI偏好，提示词和生成任务不因折叠丢失。308 Python、139 Node、lint/build、真实UI/API/隔离SQL/模拟媒体全流程和线上桌面手机检查通过。未新建真实充值码、下单或发起收费生成；现有控制字符过滤lint提示已记录。下方正式版本描述为前序记录。

## 2026-10-26：当前正式淘宝购买与历史原图

已推广dpl_5aBgyA3TXnMb2McQJCPAGA6LbHNR，https://www.posterflow-ai.xyz/，主脚本index-Bjj4kvl_.js。184文件当前源码及验证在artifacts/history-originals-20261026；回退目标dpl_8KqrhBLPjKLiappecAwE1rfBSVvb仍保留本次已开放的淘宝选购、店铺/交流群二维码、中文卡密文件名。此前dpl_1iT887wJLF4QF5G88a1yLGwcHWPK是筹备版支付，用户后续已要求移除；不要误回退到人工支付默认页。

兑换码和Omni正式迁移20261026131307/20261026131305已应用，不再是待发布；本轮后续UI与历史原图无需新迁移。当前只改变历史预览返回安全文件名及前端按需读取原图，原图存储、所有扣费与原图保留逻辑不改。列表不签原图，点击预览/下载才读原图，重复下载用内存复用；12小时入口限制保持。关于APIMart原图URL可复用但有expires_at，保存方式已问用户、尚未选择，不删除旧Supabase文件。

298 Python、136 Node、lint退出0/build通过；真实页面→Flask→PGlite配合合成Storage在电脑/手机验证惰性加载、原图逐字节下载、重复下载、跨用户拒绝、Escape及无溢出。卡密文件名清理控制字符的正则有一条预期lint提示，未放宽过滤。生产未造测试码或收费生成。较早发布记录保留供回查，状态以本节和HANDOFF最新节为准。

## 2026-10-26：卡库制码与网站兑换待发布

新增管理员批量制码、未用码 TXT 下载、单码/整批作废与近期记录；用户在购买积分窗口输入兑换码自动记 purchase 流水，每码只到账一次。五档 ¥10/20、¥30/70、¥50/120、¥80/200、¥100/260，制码不算收入、不改余额，订单实收不按套餐面值猜测。网站本地已实现，不再是“CDK尚无实现”；下文同日早期记录保留为历史。

尚未部署/写生产，未开通淘宝或阿奇索授权、核销、退款回调、自动补货，未走真实收费订单；不宣称全自动支付闭环完成。新迁移20261026120723_credit_code_redemption.sql独立于待发布Omni，逐项确认旧函数/ACL/余额/流水未变，四款模型正式基线与含Omni基线均通过。正式部署需单独应用真正未执行迁移，禁止db push重放历史合并版本。

298 Python、136 Node、lint/build、SQL及1440/375真实页面→Flask→隔离数据库通过。完整证据、运行时源码归档及哈希见artifacts/credit-codes-20261026；操作/安全/密钥轮换/退款限制见docs/credit-code-redemption.md。当前正式部署与回滚目标保持不变；当前本地测试码不可导入正式卡库售卖。回退时保留所有已发码和到账数据，不删表或充值流水，必要时先暂停销售。

## 2026-10-26：Gemini Omni 1.1 Flash 已本地接入，等待部署指令

用户要求按顺序继续下一款、定价实际 USD×7÷0.38×1.2向上取整0.5。本轮新增gemini-omni-1.1-flash，未部署、未写正式数据库、未调用真实收费生成。当前正式仍dpl_DMkAxod4RuNagdpszr2LmC4pXqs9/index-CDM_372b.js；默认2.5保持，下拉已接四款的顺序保持，本地Omni为第五项；Mini固定价、其他旧价及历史快照保持。下一未接MiniMax H3，不提前开放。

Omni独立参数/上传校验/历史/管理员/计费RPC：360/720/1080/4K、16:9/9:16、模型自动约3–10秒有声，不能传duration；10图1视频（视频≤10秒），无参考音频/Seedance审核asset/种子/联网/样片/@菜单。统一素材可指定首尾帧，尾帧须配首帧；普通图仍传image_urls，首尾走独立字段防止覆盖。视频编辑和本人已完成已结算同型号任务续写，本站UUID由后端核对owner_scope再换成上游任务ID，不能混传参考视频。图片16MB/3200万像素、视频50MB是本站限制；不误套Seedance300–6000、2秒下限或720P参考视频上限。

按官网黄金档最多10秒输出预估360P7分/预留10.5，720P19.5/31.5，1080P29.5/47，4K58.5/93.5。预估不含精确输入token费用；最终只认可信data.cost，与credits_cost同时存在须一致，套1.2公式；费用缺失等待、差额不足保存账单待补足、明确失败幂等退回、未知不重发POST、自带Key零网站扣分。新任务保存价格快照。

新增待发布迁移supabase/migrations/20261026102159_omni_flash_actual_cost.sql；只新增OmniRPC、必要约束/历史白名单和管理员只读actual_cost分类。隔离SQL逐项确认旧任务/余额/函数定义和ACL保持。不能直接db push重放之前生产已合并版本的旧本地迁移；发布时仅本次新迁移，并保留新型号后端结算兼容回退。

289 Python、134 Node、lint/build、隔离SQL通过；真实页面→Flask→PGlite→模拟上游/Storage在1440/375验证音频拦截、缺首帧拦截、首尾+普通图、延迟cost不交付、31.5预留/12分模拟实结、单次POST、视频编辑、本人任务续写、失败退回、默认2.5及无溢出。最后文案更新已额外浏览器复核，未重复收费测试。证据artifacts/omni-flash-20261026，功能说明docs/video-omni-flash.md。完整本地入口http://127.0.0.1:4202/（Flask会话76424），内存DB4203（89754），合成账户/模拟服务/不读.env；4200仍是旧静态服务，不代表本次完整功能。

同时用户淘宝新截图已显示店铺开通并进入发布页，能看到AI软件及应用及在线卡密/API聚合平台/无品牌无注册商标/服务订阅与充值选项。仅提供按实际业务填写建议，不代表资质批准或已发布；型号建议PosterFlow AI积分兑换码。CDK功能仍未实现，支付未启用、未上架或操作淘宝账号。


## 2026-10-26：视频默认2.5、隐藏待接入下拉项、去掉测试标记（已部署）

用户明确改完直接部署。正式已推广dpl_DMkAxod4RuNagdpszr2LmC4pXqs9至https://www.posterflow-ai.xyz/，主脚本index-CDM_372b.js，www/根域名均200。仅改4个前端文件：StudioNavigation去掉“测试中”；VideoWorkspace下拉仅保留已接入的2.5/2.0/Fast/Mini且顺序不变；StudioWorkspace首次状态及从新灵感开始的视频默认defaultSeedance25；studioCatalog概览默认文案同步2.5。内部待接入路标、Mini构造器、历史恢复、手动切换编辑状态及所有计费协议保持，未重写已有任务。

132项前端测试、lint/build、差异与源码扫描通过；1440/375本地与真实生产资源+隔离合成API浏览器验证默认2.5、仅4项、无测试标记、灵感开始2.5、保留Mini草稿、原Mini/Fast报价、管理员统计与失败分类、上传下限均通过。正式home/health/video config200、匿名admin401；Mini价格和标准/Fast的1.2配置未变。176份准确源码ZIP/清单hash、4份上传、截图/结果见artifacts/video-default25-release-20261026/release.json。无后端、数据库、密钥、支付配置变更，无真实收费调用或生产测试账户写入。没有提交推送Git，仍手动推广。

当前回滚目标dpl_ERBptfL1SiaAQKEyKAKEnd6MDcRp，直接切代码即可；本次前后后端和计费完全相同，保留全部数据/账户/积分/兼容迁移。上一阶段的Mini默认描述属于历史，当前正式默认Seedance2.5。支付问题目前按淘宝个人店路线调研，用户最新截图仅为开店资料审核中，未实现CDK/启用收款/上架商品，不要把文档草案误当上线功能。

## 2026-10-25：Seedance 2.0 / Fast 与视频编辑器正式发布

用户明确“部署”后，已发布dpl_ERBptfL1SiaAQKEyKAKEnd6MDcRp至https://www.posterflow-ai.xyz/（www与根域名均200），主脚本index-Bnz3E4Eg.js。包含标准版、Fast、视频要求复查与独立卡片/醒目视频提示词输入区；默认Mini和下拉顺序不变。标准版/Fast/现有2.5均按实际USD×7÷0.38×1.2向上取整0.5积分，Mini固定价不变，历史价格快照不改。176份准确源码、15份更新与SHA256/页面截图见artifacts/seedance20-release-20261025/release.json，未提交推送Git、未改密钥，仍保持手动推广。

正式迁移20261025143519_seedance20_standard_fast_actual_cost已应用，对应本地20261025130000与20261025140000两份，不能重复db push。连接器提交后曾传输断开，已通过迁移列表、新RPC和read-only价格/权限查询确认成功，没有重发DDL。单事务守卫验证旧视频行、原计费函数hash/权限、表授权与RLS保持；仅private管理员只读汇总改变，public包装仍247fac7741686fba7203ee3c498cde27，private新hash6858d49068897d863cf97b61d037fe28。正式价格7.5/4.5/9.5及旧2.5的11、service_role only均复核，安全告警与之前完全相同。

283后端/132前端、本地两型号完整链路和8组界面检查、guarded SQL、lint/build已通过；正式1440/375真实线上资源+隔离合成API验证图像管理员统计/音乐视频切换/待处理/失败分类/上传下限及4模型/分辨率/提示词/默认Mini/4.5报价均通过。真实正式home/health/三种媒体config=200，匿名admin/video tasks/空生成请求=401；未调用真实收费生成，未写生产测试账户或任务。不能把模拟上游验证声称为真实收费视频已生成。

回退保留全部现有数据库和账目。尚无新型号任务时可切回前版dpl_83iBL1sncNRiHWqUF48qJNkAWmW2；一旦标准/Fast有任务，使用artifacts/seedance20-release-20261025/rollback-compatible-runtime-source.zip发布回退（同一计费后端，仅回退到已验证的旧视频UI），避免旧后端不识别新模型而把预留当最终收费。回退包176文件、只有4个UI文件差异，精确SHA256已保存；不逆向迁移或恢复旧数据库。稳定2416911仅作更早历史点。下方本地待发布内容属于此前阶段。

## 2026-10-25：管理员生图统计归入图像页（已正式部署）

用户要求生图统计并入原音乐/视频运营区，去掉平均耗时、发放积分和退回积分，平台生图任务排在自定义Key前。仅改AdminMetricsPanel.jsx/AdminMusicOverview.jsx：顶部白名单固定为新增用户/已验证邮箱/今日活跃/本月活跃，创作运营概览增加默认图像tab，依次为生成图片/生图消耗积分/生图成功率/平台任务/自定义任务；沿用原数值和口径，不改查询或账目。音乐视频原功能保留。

已部署dpl_83iBL1sncNRiHWqUF48qJNkAWmW2，https://www.posterflow-ai.xyz/，主脚本index-CtBO3y96.js；174份精确ZIP/SHA256、记录artifacts/admin-image-tab-release-20261025。电脑1440/手机375真实线上资源+隔离合成API验证指标位置/数值/顺序/移除项/音乐视频切换通过，lint/build通过。无生产迁移、密钥变化或收费调用，未提交推送Git，保持手动推广；回滚仅切代码到dpl_2ydEbgx6581VfCJy5p2G7XRcy9P8。

后续当前任务：用户要求部署此UI之后继续列表下一个视频模型Seedance 2.0；新款实际USD×7÷0.38×1.05向上取整0.5积分（区别于现有2.5的1.2和Mini固定价，旧价保持）。还须全面复查Mini/2.5素材与任务限制，不能漏掉导致付费失败的边界。Seedance 2.0官方支持4–15秒、480/720/1080/4k、4000字符、9图3视频3音频，首尾帧不能混视频音频，音频须搭配图或视频，审核asset可跨2.0/2.5使用。价格页apimart.ai/model/doubao-seedance-2-0提供Gold无视频/有视频USD每秒：480p0.066/0.04、720p0.142/0.08584、1080p0.3544/0.21568、4k0.722/0.44432，只作预估，终态真实cost结算。新模型尚未改代码/迁移/发布。已查官方 generation 和 private-avatar、2.5 generation；须保存能力矩阵和测试后再交付，不做真实收费试生成。

## 2026-10-25：管理员与生成失败修正已正式发布（最新）

用户明确“改完直接部署”后，正式推广 dpl_2ydEbgx6581VfCJy5p2G7XRcy9P8 至 https://www.posterflow-ai.xyz/。主脚本 index-BHSXZI7A.js，工作区 StudioWorkspace-B3LGcqNu.js，174份运行文件精确ZIP和SHA256在 artifacts/admin-errors-release-20261025/release.json。20份新增/更改源码上传；前次一次性Storage构建探针移出，保持原构建命令；未改变价格、模型协议或任何密钥。保留手动推广，未提交/推送Git。

生产迁移20261025123511/admin_multimedia_operations已成功应用，对应本地20261025102000文件，不得重复重放。仅更新private只读统计函数；原public包装hash 247fac7741686fba7203ee3c498cde27、service_role权限保持，前置函数版本守卫及新overview_version=2断言通过。没有对账户、积分、流水、任务做数据更新；安全告警与之前完全相同。音乐/视频运营与分类失败分布、待确认和待结算筛选正式上线。

Suno曲库音频匹配单独提示查重；图片504显示服务超时及等待两分钟、查询原任务，不再误导为审核拒绝。视频Mini图片宽高300–6000/比例0.4–2.5、音视频每段2–15秒，2.5每段2–30秒；前端上传前与后端实际内容/旧收据在预留前校验。任务失败中文原因刷新后可按已存分类显示，旧未知原因不会凭空补全。

272 Python、126 Node、lint/build/diff、凭据字面量扫描、含生产函数守卫的隔离SQL通过；正式线上真实资源在1440/375浏览器通过（合成API隔离、无生产写测试用户/生成任务），真实小尺寸PNG/1秒音频被上传前拦住，合法图进入模拟上传。候选home/config/匿名401通过。免费验证未调用收费生成。立即代码回滚点 dpl_7Xhy4C1B9aJEJjdHLgCohvDcFCeE；仅切代码，保留当前DB/用户/积分/所有兼容迁移。下方“本地待发布”是历史实施阶段。

## 2026-10-25：视频与创作素材已正式上线（最新发布状态）

用户批准并补齐视频 Production 密钥后，正式推广 dpl_7Xhy4C1B9aJEJjdHLgCohvDcFCeE，https://www.posterflow-ai.xyz/；index-CD9w7I7W.js / StudioWorkspace-BEyvf9Uu.js。173份运行文件的精确源码ZIP、SHA256、发布检查在 artifacts/video-materials-release-20261025/release.json。视频 Mini 默认和原价、2.5按实际美元×7÷0.38×1.2向上取整0.5积分、个人素材与分类/删除/预设保留、资料与工具面包屑均已发布。

生产 Supabase ezim 的兼容合并迁移 20261025091626/video_fractional_seedance25_markup20 已成功应用，包含四份本地视频/小数积分/2.5迁移；禁止再次重跑这四份。事务内旧表逐行JSONB和函数权限守卫通过；数字列现支持四位小数，旧用户、积分、流水和任务保留。新视频RPC仅服务端可执行，video_jobs开启RLS，原Cron保留。不能用跨时间的账户总数或积分总和作不变断言，因为线上用户仍在活动。

262 Python、123 Node、lint/build/diff通过；正式网页真实静态资源在1440/375宽度测试通过（合成API隔离，不写生产），public health/config/匿名401、首尾静态图哈希通过。构建期间在原私有bucket完成一个小型合成视频的签名上传、鉴权及签名读取、字节核对，并删除该对象；未做真实收费生成。首个候选因构建探针导入失败未推广，修正后本候选通过。保留手动推广，自动域名分配关闭。

立即代码回滚点 dpl_BvDAMbJtdQj2tEqRGs5pP6ukSBJa；仅切代码，绝不能恢复旧数据库、覆盖新用户/积分或把 numeric 改回 integer。原2416911固定恢复点仍保留。新一轮管理员多媒体完善、错误分类和视频参考图尺寸修正尚属本地工作，不包含在本次发布。下方“仅本地/未迁移/待部署”说明是历史阶段记录。

当前正式版（2026-10-25 最新）：dpl_BvDAMbJtdQj2tEqRGs5pP6ukSBJa，index-BxBueQMg.js；Flow 单音频导入后改编及七处司凤灵感上线。89份源码清单12bc1f303dabd9bd4c376a2a7f87f3fe11b634a981833117f5d60e1925a0f4fa，精确ZIP/记录artifacts/flow-release-20261025；迁移20261025041114/flow_audio_cover，43条原音乐任务、17个原计费与管理员函数完整保留。前正式dpl_HVLHoB7nczkKZgwnYamsUGg6TatN及原2416911固定点保留。只切代码回滚，保留最新用户、积分、流水、充值、任务和所有兼容迁移；整数积分不变。用户后续要求研究Seedance Mini，不代表视频已上线。以下为历史版本记录。

当前正式版（2026-10-25）：dpl_HVLHoB7nczkKZgwnYamsUGg6TatN，index-DkUR-bMt.js。Suno 本地音频素材、参考创作、上传改编正式上线，官方请求字段核对与必要校验修正完成。迁移 20261024172815/suno_audio_operations，原任务与计费函数保留。发布记录/精确 ZIP 见 artifacts/suno-audit-release-20261025，支持矩阵见 music-support-audit-20261025.md。前正式 dpl_8fjuVRJzTkVUVBj1t7Ud9RQjBviG 与原2416911恢复点保留，回滚只切代码，不恢复旧用户/账目/数据库。后续改动仍需用户批准部署。以下为历史记录。

当前正式版（2026-10-24）：dpl_8fjuVRJzTkVUVBj1t7Ud9RQjBviG，index-Bhov4N70.js。Nano 1K/2K每张1积分，4K每张2积分（参考同价），图像失败建议两处同步用户最终文字。79份清单78e5bb7a916adfeebfc23e7a28147c85081575c664cb1960b033c59070b529d0，记录/源码ZIP见artifacts/nano-4k-pricing-20261024。生产新增兼容迁移20261024092842/nano_4k_pricing，原函数和历史账目不变。前版dpl_rY8cHkNrenHNe9WZyLEuRZzabmN6及原2416911恢复点保留；只切代码，保留最新数据/迁移，已提交任务按快照结算；旧代码新任务遵循旧价格。以下为历史发布。

当前正式版（2026-10-24）：dpl_rY8cHkNrenHNe9WZyLEuRZzabmN6，index-Ca8DutGO.js，音乐未知失败显示用户指定版权审核提示，已识别原因及退款说明保留。79份源码清单56db9d3bb5b74b4df693c0a81590fbb312b69768c5288126df7735ca7e2f1916，记录/ZIP见artifacts/music-failure-copy-20261024。前版dpl_4Seqop9N4mT1cHP63vGs5F1Vkxc5及原2416911固定点保留；无数据库/环境变化。以下为历史发布。

当前正式版（2026-10-24）：dpl_4Seqop9N4mT1cHP63vGs5F1Vkxc5，index-K00x1Pgj.js，创作灵感新增二次元风格提示词参考链接。相对前版只改两份前端文件；79份源码清单7612d9d16cb92ac0cd255ecd096300a07412c9b27417fa5cd4443877dd9d1db0，记录/源码ZIP见artifacts/anime-inspiration-20261024。前版dpl_4zQ3VCy6UBQhmpyaLTvb1jwAm4Tu和原2416911固定恢复点保留；无数据库/环境变更。以下为历史发布。

当前正式版（2026-10-24）：dpl_4zQ3VCy6UBQhmpyaLTvb1jwAm4Tu，index-BKvSyhSs.js，www/root均已推广。账号历史按需显示现有512px缩略图，预览12小时、提示词7天；两个Grok模型清晰度自动；预览顶部和侧栏同时保留备用下载，每张画廊卡有网络/下载失败提示。79份源码清单f3b7ad607b946d33a2e909acd53c037f99b7de5d4d64acde0d4bb7db8b614dbc，发布记录/源码ZIP见artifacts/history-previews-20261024。无数据库迁移或环境修改，原12h清理继续。前版dpl_4nuV1xk47qwuKRZjAoGSz8f4x5tA保留，原2416911固定恢复点不变；恢复只切代码，保留用户、积分、充值、账目和任务。下面均为历史发布记录。

最新正式版（2026-10-24）：dpl_4nuV1xk47qwuKRZjAoGSz8f4x5tA，index-DehaKKta.js，www/root均已推广。修复参考图上传成功但getapib.org域名被误拒绝，以及批量下载失败隐藏画廊的问题；78份源码清单08eef820493994702c77a88d10a41e017454f764518092813e307409de8cc1af，发布记录及ZIP见artifacts/reference-upload-20261024。前版dpl_46ALxguacP8u2gppaGfo9NyPLeQK和原2416911恢复点均保留。本轮无数据库/环境变量变化；恢复只切代码别名，保留已有账目、用户和兼容迁移。

最新正式版（2026-10-24）：dpl_46ALxguacP8u2gppaGfo9NyPLeQK，index-9jzaSFsm.js，www/root已推广。包含设置模型完整小写ID及括号价格、工作区易读名称、模型卡定价，以及常驻画廊/预览顶部的备用下载和网络提示。78份运行源码清单bfb3989f94a5a9cd8e8416e6fab19dc36746ec11788b86e3a22ac3ba90c3825a，发布记录及源码ZIP见artifacts/visible-backup-20261024。前版dpl_5Y9FQEjcwWeiTCQwm4ShEpG58Ajz保留，原2416911固定恢复目标不变；本轮无后端/数据库/环境变动，恢复只切代码别名，保留现有数据与计费迁移。

当前正式版本更新（2026-10-24）：dpl_J7FmBuW62EsuZNt2kKGJ7Fc9v3WP，主脚本index-CTbeB0OV.js，www/root均已推广；图片模型快捷切换、Grok恢复（文生图1/参考编辑2积分每张、最多3张参考）、统一模型文案与音乐中文失败原因已上线。迁移20261024024433/grok_reference_pricing已应用，原四图像RPC hash保持不变，不需重跑。77份源码清单与ZIP见artifacts/grok-reference-20261024/release.json。最近前版dpl_4phGS2D8aXwN84ebG1ZMsyFVzvYa和原2416911稳定版均保留；回滚只切代码，不恢复旧数据库、不删除任务或逆向修改现行计费。当前仍手动推广，未改Git来源，未新建Vercel/Supabase/Resend。Suno音频扩展和上游临时图片历史仅调研，未上线。

当前状态（2026-10-23T23:59:12+08:00）：用户验收后已推广 dpl_wBFvP7ooVQKm6XgsTU64yRN1mGi5，www/根域名正式运行新版。保持原Supabase/Resend/Vercel；旧版固定恢复目标2416911不变。音乐现按次2积分，返回两首仍共2，新增历史/管理员迁移已应用，不重跑。此次推广未改Git来源，自动域名分配关闭，后续需手动Promote。精确发布记录 artifacts/production-launch-20261023/release.json，下面的准备状态及“按首”描述属于历史。

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


## 2026-10-28 MiniMax H3 本地接入，尚未部署

已按路线加入第六款 `MiniMax-H3`，默认 Seedance 2.5 和前五款顺序不变；H3 Max 暂未开放。支持 768P/2K、4–15 秒、7000 字符、明确首尾帧或多模态参考，独立解析与校验尺寸/编码/FPS/大小/时长，HEIC/HEIF 新增固定 pillow-heif 依赖。首尾帧与参考模式互斥，音频不可单独使用，不传旧型号无关参数。原生有声及水印/内容预检查，任务、历史、管理员实际用量标签同步。

最终实际 USD×7÷0.38×1.2，上取整 0.5；预估含参考视频秒数与超过5张图片的费用。5秒无参考768P预计6.5预留10.5，2K预计10.5预留16.5。新迁移20261028033511_minimax_h3_actual_cost.sql仅隔离本地验证，生产不写。私有Storage桶只读确认 public=false、MIME/单文件上限null。正式仍 dpl_4WRjv5zLG8tMuYBSsPsvTpNNsz2N / index-xQUUnbJ1.js。未提交推送部署、未发起真实收费生成。

本地验收 http://localhost:4212/ ，真实React/Flask/PGlite，生成与Storage模拟；端口4213是隔离DB桥接。桌面1440/手机375验证6模型顺序、保留草稿、低帧率拒绝、首尾帧互斥、最终费用等待/结算、9图加视频计费、失败退款、BYOK零扣分，无JS错误/横向溢出。详细文档docs/video-minimax-h3.md，检查和源码快照artifacts/minimax-h3-20261028。新模型真实权限和真实出片未联调。另保留之前Flow类型错误/泛化失败的中文诊断本地修复，未声称原生成功率已修好。


## 2026-10-28 MiniMax H3 Max 本地接入（未部署）

新增第七款 MiniMax-H3-Max（在H3之后），默认Seedance2.5、此前顺序保持，下一未接Wan3.0。官方max文档确认5–15秒/480P768P1080P、7000字符，1080P必须完全不传watermark即使false也禁止；无文档化nsfw_check，不能照搬H3预检查；无2K/4秒/中间帧/重生成。相同素材约束复用H3，经真实字节验证尺寸/FPS/编码/时长/大小，首尾帧与普通参考互斥，音频不可单独使用。工作区1080P隐藏水印，其他档可选，服务端及SQL独立拒绝不合规请求。

计价仍实际USD×7÷0.38×1.2上取整0.5。Max前2图免费，额外图USD0.05712/张；生成秒价480P .03768/768P .05712/1080P .128，参考视频独立秒价 .04232/.11088/.11936；参考音频免费。5秒无参考预计4.5/6.5/14.5，预留7/10.5/23；768P5秒+3秒视频+3图预估15预留24。最终按真实cost结算，多退少补；无cost等待，不把估算当实际；失败退款、BYOK零扣分、未知提交不重发、按原任务幂等查询都保留。

新增本地迁移20261028041350_minimax_h3_max_actual_cost.sql依赖上一轮未部署H3迁移20261028033511；仅在隔离PGlite应用。旧H3/此前函数和ACL逐项保持、原任务/账户不变，管理员实际用量分类同步。未写生产/修改真实.env/付费生成/提交推送部署，正式仍dpl_4WRjv5zLG8tMuYBSsPsvTpNNsz2N。

本地验收http://localhost:4214/，DB桥4215，真实React/Flask/SQL，生成和Storage模拟，不扣真实积分。桌面1440/手机375已验证七型号、默认2.5、5秒下限、三档清晰度、水印在1080P完全不传而768P保留、低FPS拦截、首尾帧排他、3图+视频+音频独立计价、费用等待/失败退款/BYOK零扣分，无JS错误或溢出。333Python/150Node/SQL旧模型回归/lint/build通过，详docs/video-minimax-h3-max.md及artifacts/minimax-h3-max-20261028。保留原H3预览4212和所有此前本地Flow诊断修复。真实上游权限和出片仍未联调。


## 2026-10-28 Wan 3.0 本地接入，未部署

新增第八款wan3.0-video，默认2.5与既有顺序保持，未开放Prime/FLUX。独立参数：2–30秒或自动-1，480/720/1080P默认1080P5秒，自适应+五画幅无21:9；20000字符、原生audio开关/0..2^31-1种子/水印/可选预检查。首帧必须，尾帧可选，不能混用普通参考图/音视频/文档/网页；普通图片显式reference_image防接口猜首尾。10图5视频5音频1文档；图片240–8000/20MiB无透明PNG，视频240–4096/100MiB每段1–15秒，音频15MiB每段1–15秒且可单独空提示词。音视频各合计15秒，视频加生成≤30秒。实际字节校验，复用其他模型旧收据会重新读取并校验SHA256与Wan约束，旧透明PNG不漏检。

支持上传及URL导入doc/docx/xls/xlsx/ppt/pptx/pdf/txt/md/key/pages/numbers，100MiB50页；新增pypdf==6.21.3。PDF/PPTX校验真实页数，DOCX元数据可用时校验，其余复杂格式页数由服务最终解析，UI明确，不伪称全格式本地精确分页。不执行宏/外部转换。网页填公开HTTPS，不能与文档或首尾帧混用，链接不入提示词历史；@素材菜单发送转换图N/视频N/音频N，顺序按类型稳定。

仍实际USD×7÷0.38×1.2上取整0.5；仅参考视频+生成时长计费，图片/参考音频/文档/网页不加时长，关闭声音不降价。Gold预估USD秒价 .03288/.06575/.1315，5秒预计4/7.5/15积分、预留6/12/23.5；自动按总30秒上限估算。最终cost待确认不假结算，补差/退款/幂等/BYOK零扣分保持，管理员及历史同步。

待发布新迁移20261028055103_wan30_actual_cost.sql依赖H3 20261028033511与Max 20261028041350，三份均仅本地隔离应用。原模型函数/ACL/账户/任务逐项不变，禁止db push重放旧正式合并迁移。没有写生产/修改真实.env/实际付费生成/推送部署，正式仍dpl_4WRjv5zLG8tMuYBSsPsvTpNNsz2N。

本地验收http://localhost:4216/，DB桥4217，真实React/Flask/PGlite，服务与Storage模拟。桌面1440/手机375验证八模型默认顺序、透明PNG、首帧必选/混用拒绝、@编号转换、音频单独生成、自动/30秒总预算、文档/网页、URL不入历史、费用确认、退款及BYOK零扣分，无JS错误或横向溢出。BYOK另只查询原任务核实completed/0扣分/0新增POST。详docs/video-wan30.md和artifacts/wan30-20261028。真实出片/权限、生产100MB全局Storage配置未联调，不能据模拟结果宣称真实上游成功。下一未接FLUX3。


## 2026-10-28 FLUX 3 Video 接入与四模型发布准备

新增第九款 flux-3-video，默认2.5、既有顺序与Mini固定定价不变。5–20秒、HD/FHD、八个含自动画幅选项、1–10张有序关键帧（允许重复、可前后移动）、一段MP4续写、HD草稿与独立全价正式片、声音/审核容忍度/预检查。正式片只发model/resolution/draft_from_task_id，双重核验本人同Key作用域已完成并结算草稿，继承原续写费率，不能篡改提示词/时长/素材。实际USD×7÷0.38×1.2上取整0.5；续写按独立秒价只计输出秒数，草稿费不抵扣。历史与管理员实际用量同步。

356 Python、156 Node、独立PGlite迁移/全旧模型回归、lint/build通过；1440/375真实UI→Flask→PGlite验收有序图片、草稿/续写草稿转正式片、待确认费用、重复查询无新POST、退款/BYOK零扣分，无JS错误或溢出。生成与Storage模拟，未用真实Key或收费联调。验收http://localhost:4218/，DB4219。197运行文件源码清单/ZIP与密钥特征扫描存artifacts/flux3-20261028；详docs/video-flux3.md。

用户随后明确授权“做完可以直接推送并部署”：目标GitHub Something11235/PosterFlow-AI-2.0 main、Vercel现有posterflow-ai、生产库ezimtgfppvqkkzpjeojg。发布候选将包含H3/Max/Wan/FLUX四份独立新迁移；不得重放已合并的历史迁移，不改真实.env。发布前正式回滚点dpl_4WRjv5zLG8tMuYBSsPsvTpNNsz2N。最终线上ID/SHA/迁移版本和限制见本轮release.json；在该记录完成前不能声称已上线。
