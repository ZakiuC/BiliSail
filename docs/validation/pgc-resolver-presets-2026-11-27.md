# 番剧地区解锁：推荐解析服务器实测与匿名检测

日期：2026-11-27。状态：已加入推荐服务器清单、设置项检测与一键填入，离线测试通过；公共服务器可用性只在实测日期有效。

关联记录：[BBZQ 能力对照与移植](bbzq-integration-2026-11-23.md)、[API 方案](../api-design.md)。

## 背景

「设置 → 播放 → 番剧地区解锁」原先只能手填四个地区的服务器地址，用户必须自己寻找地址；
社区名单里大量域名已失效、被地区网络阻断，或要求账号 `access_key`，手填后无从判断是否真的能播。
本次先在真实网络逐项验证候选服务器，再把「已验证地址」做成推荐项，并提供与播放链路完全一致的匿名检测。

## 探测方法

- 探测主机与用户一致：中国大陆电信网络出口（浙江宁波）。账号、Cookie、`access_key` 一律不发送。
- 每个候选只做两类请求，参数与客户端播放时相同：
  - 详情：`/pgc/view/v2/app/season` → `/pgc/view/web/season`，携带 `season_id` 与 `area`；
  - 取流：`/pgc/player/api/playurl` → `/pgc/player/web/playurl`，
    `qn=80`、`fnval=4048`、`fnver=0`、`fourk=1`、`force_host=2`、`module=bangumi`、`platform=android` 与 `area`。
- 判定标准：
  - **可用**：详情返回 `code=0` 且 `episodes` 非空、首集 `rights.area_limit!=1`；取流返回 `code=0` 且 `dash.video`、`dash.audio` 均非空。
  - **仅详情**：详情通过、取流失败（例如服务器要求 `access_key` 或关闭了取流路径）。本次不纳入推荐。
  - **不可用**：DNS/TLS 失败、HTTP 4xx、非 JSON 或业务码拒绝。

对照剧集：`season_id=40664`（《平凡職業造就世界最強》第二季，标题含「僅限港澳台地區」），
官方从大陆访问时首集 `rights.area_limit=1`，因此该剧集能区分「官方拒绝」与「解析成功」。
`season_id=28049`（第一季）仅第 1 集可取流，其余集数返回 `-10403`，说明授权状态会变化，
检测逻辑因此内置第二个后备样例，样例失效不会被误判为服务器故障。

## 实测结果（2026-11-27）

共探测 **200+** 个候选地址，覆盖以下来源与变体：

- 公开名单与社区文章中的 50 个原始域名；
- 每个域名的 `api.`/`bili.`/`hk.`/`tw.`/`th.`/`cn.` 等子域名变体（60+）；
- Vercel 部署名猜测（`biliroaming`、`biliroaming-ts-server`、`biliroaming-ts-server-vercel` 及地区后缀，80+）；
- Cloudflare Workers / Deno Deploy / Netlify / Railway / Render / Fly.io 部署名（70+）；
- M1saka / hunyl.com 运营者相关域名变体（40+）；
- `lli.cx` 子域名变体（30+）；
- HTTP 回退、非标准端口（443/8443/2053/2083/2087/2096）、`x-from-biliroaming` 请求头变体。

结果分五类：

| 结果 | 数量 | 代表域名 |
| --- | --- | --- |
| **详情与取流均通过（匿名）** | **1** | `bili.lli.cx`（HTTPS 与 HTTP 均可） |
| 仅详情通过、取流要求凭据 | 5 | `atri.ink`（`401 access_key required`）、`hk.biliroaming.bili33.top`（`web_on已关闭`）、`biliroaming.vercel.app`、`biliroaming-ts-server.vercel.app`、`biliroaming-ts-server-vercel-hk.vercel.app`（均要求登录） |
| DNS/TLS 被阻断或证书过期 | 80+ | `api.mahiron.moe`、`bili.nekorua.com`、`api.rnmmihoyo.cc`、`bili.xifeng.cf`、`api.qiu.moe`、`bili.xcnya.cn`、`melusine.moe`（证书已过期）等 |
| 已停放／返回 404、403、500 或 HTML | 60+ | `bili.tuturu.top`、`bstar.kirara-fantasia.moe`、`biliplus.com`、`cc.hmountainln.cn`、Vercel/CF 部署名等 |
| HTTP 503（CDN 防护） | 10+ | `api.mahiron.moe`、`bili.nekorua.com`、`bili.ayo.moe`、`api.rnmmihoyo.cc`、`bili.xifeng.cf`、`api.qiu.moe`、`api.etocs.tk`、`bili.xcnya.cn` |

因此本次内置两条推荐项：

1. `https://bili.lli.cx`（公共志愿者服务器，港澳／台湾）；HTTP 回退同样可用。
2. `https://resolver-vercel-beta.vercel.app`（Vercel hkg1 自建节点，港澳／台湾）。
   使用 [biliroaming-ts-server-vercel](https://github.com/JasonZH6600/biliroaming-ts-server-vercel)
   部署，配置 `need_login=0`、`web_on=1`、`ver_min=0`，匿名 Web 取流可用。
   部署命令与配置见 `tool/resolver-deploy/vercel-deploy.md`。

### 代理验证（192.168.0.35:10808 SOCKS5）

通过局域网 SOCKS5 代理（同时支持 HTTP CONNECT）重新探测全部 SSL 失败域名，
结论：**SSL 失败是服务器自身下线，不是 GFW 阻断**——代理出口同样无法建立 TLS 握手。
`atri.ink`、`hk.biliroaming.bili33.top` 经代理后详情仍通过，但取流依旧要求凭据／登录。
Vercel 部署经代理后同样要求登录或返回 500。代理未揭示任何新的匿名可用服务器。

### 东南亚（th）验证补充

`bili.lli.cx` 对 `area=th` 的港澳剧集请求返回与 `area=hk` 相同的结果（同一上游），
但对东南亚独占内容（如 `season_id=39433` 鬼灭之刃 游郭篇）仍返回 `area_limit=1`、
取流 `-10403`，且 `/intl/gateway/v2/ogv/playurl` 返回 404。
结论：该服务器只反代 `api.bilibili.com`，不代理国际版 `api.global.bilibili.com`，
**不能解锁东南亚独占内容**，因此推荐项不标记 `sea`。

### `bili.lli.cx` 明细

- 详情：`area=hk` 与 `area=tw` 均返回该剧集 15 集，首集 `rights.area_limit=0`；官方大陆请求为 `1`。
- 取流：`ep_id=458195` 起逐集请求，15/15 返回 `code=0`，DASH 视频轨 4–6 条、音频轨 3 条；
  单集耗时 881–2851 ms，中位数 1270 ms；详情单次 876 ms。
- 画质按匿名 Web 身份返回（观测到 360P／480P 档），与「不发送账号凭据」一致。
- 该服务器只代理 `/pgc` 路径；`area=th` 返回与港澳相同的结果，不能证明泰国区解锁，
  因此东南亚与大陆两栏在推荐项中留空，避免用同一个地址造成「全部地区」的错觉。
- 通过客户端自身代码（`BiliApiPgcResolverHealth`）复测港澳两区均判定可用。

## 设置项改动

- 播放分类下新增「推荐解析服务器」条目，对话框列出内置地址、适用地区、实测日期与说明；
  单个条目可「检测」与「填入」，「填入」会一次写入该地址覆盖的地区并同时开启总开关。
- 已配置地区旁提供「检测该地址」按钮，用于自建服务器；未配置的地区不显示该按钮，
  宿主未注入检测实现时（测试或裁剪构建）检测入口整体隐藏。
- 检测使用与播放相同的 `PgcResolver`、路径回退与匿名请求头，12 秒 deadline；
  结果区分为「可用」「仅详情可用」「不可用」并给出原因。
- 推荐清单是编译期常量，不写入设置，`preferences.v1` 快照版本保持 **57**，SQLite schema 保持 **3**；
  应用推荐项仍走 `setPgcResolverServers` 一次保存，缺失地区保留原值。

## 诊断 API

`PgcResolver` 新增只读 `lastFailure`：候选失败按设计被吞掉以保留官方错误，该字段暴露最近一次
`resolveSeason`／`resolvePlayInfo` 结束时的最后失败，供检测解释原因，不参与播放控制流。
同时把业务码 `401` 归入 `authentication`，对应公共服务器「必须提供 access_key」的响应。

## 验证

固定工具链 Flutter **3.50.1** / Dart **3.14.0**，本机 Flutter SDK 修订与该仓库 `.flutter-version` 的差异见下方未验证项。

已执行：

- `flutter analyze --no-pub lib test`：通过。
- `dart analyze`（`packages/bili_api`）：通过。
- 新增与相关定向测试：预设校验与地址匹配、健康检测的可用／仅详情／要求凭据／样例回退／非法地址／网络失败、
  设置项检测与填入、控制器一次写入多地区 → 全部通过。
- `test/features/settings` 与 `test/features/pgc` 共 499 项通过（1 项跳过）。
- 根应用完整 `flutter test --no-pub`：**6073 项通过，7 项跳过**。
- `packages/bili_api` 完整 `dart test`：1131 项通过。
- 线上复测：`PGC_RESOLVER_LIVE=1 flutter test test/features/settings/pgc_resolver_live_check_test.dart` 通过（港澳两区）。
- `dart format` 与 `git diff --check`。

未执行：`tool/check.ps1` 需要 PowerShell，本机为 Linux 环境，相关检查由上面的 Dart／Flutter 命令逐项替代。

未验证：Windows／Android／macOS 实机播放该服务器返回的取流地址；公共服务器在长时间、多用户并发下的稳定性、
限流与下线时间；泰国／东南亚与大陆地区的可用服务器（本次没有通过验证的地址）；
本机 Flutter SDK 为 3.50.1 发行版，与 `.flutter-version` 固定的 main 提交不完全一致，CI 需按仓库流程复核。

## 后续维护

- 服务器失效时先重跑线上复测，再把失效条目从 `PgcResolverPresets.all` 移除；不要凭社区名单直接新增。
- 新增条目必须同时通过详情与取流两类请求，并按其真实覆盖地区填写 `regions`。
- `docs/README.md` 索引与 `CHANGELOG.md` 需同步更新实测日期。