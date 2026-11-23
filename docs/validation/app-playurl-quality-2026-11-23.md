# App 高画质与完整音视频流补充

日期：2026-11-23。基线：`2fe2419` 之后的用户日志与双源修复工作区。

## 问题证据

用户将视频默认清晰度设为 8K，普通视频菜单仍只有 360P、480P、720P、1080P；同一视频在 BBZQ 中可见杜比视界、4K 和 1080P 高码率。导出的三次播放均实际解码为 1920×1080 H.264/AAC。

旧日志只有请求成功/失败和原生解码状态，没有请求 qn 或响应 DASH 档位，因此不能仅凭旧包断定高档是在服务端缺失还是本地过滤。历史 Web 在线记录也证明：`accept_quality` 中广告的高档不等于账号实际得到对应轨道。

另确认一个本地请求缺口：只选择默认 8K、未开启最高码率增强时，UGC 首发使用 `qn=129`，既不等于明确的 127，也不会补取 127。

## 修复

### 定向请求与 App 补充

- 明确选择 8K 时，Web 首发改为 `qn=127`；其他默认清晰度保留原有 129 发现与缺档补取。
- 当选择高于 1080P、开启最高码率或开启画质试用时，普通视频会通过 `AppPlaybackClient` 读取
  `https://api.bilibili.com/x/player/playurl`。
- Web 成功时合并 App 实际返回的新轨道；Web 权限拒绝或不可用时，App 完整响应可作为主源。
- 普通 1080P 及以下且未开增强时不增加 App 请求。App 可选补充失败时保留完整 Web 播放。
- App 请求使用现有 HD AppProfile 签名、按需 App token/buvid 和设备快照，不携带 Web Cookie；签名 query 不进入播放器 headers 或日志。

### 完整音视频合并

`mergeApiPlayInfo` 同时合并：

- 4K、8K、HDR、杜比视界及同档不同码率视频；
- AAC 64K／132K／192K、FLAC/Hi-Res、杜比音频；
- `accept_quality`、响度和既有语音元数据。

精确重复轨道不会重复加入；同档同编码但不同码率的真实表示会保留供现有选流器比较。
预览片、时长相差超过 2 秒、不同语音/制作类型的响应不得混入主源。完整播放仍拒绝 `is_preview`，明确无音轨视频沿用原静音契约。

### 身份与请求隔离

App 身份来自现有安全身份存储的 `requestIdentity()`，播放模块只接收三个回调，不读取 CredentialStore，也不依赖 feed data。
返回后同时核对 App identity revision、调用取消状态和账号 session epoch。只有当前身份的明确认证失败才触发失效清理；网络、超时、权限或协议错误不会误删登录状态。

## 脱敏诊断

新增核心事件 `playInfoResolved`，可包含：

- `playSource`：web、app 或 merged；
- `requestedQuality` 与 `selectedQuality`；
- 实际返回的 `videoQualities` 和 `audioQualities`。

列表最多 32 个正整数；来源只接受固定枚举。视频 ID、URL、Cookie、token、buvid 和响应正文仍不写入日志。
复测同一视频后，可直接用该事件区分 Web 四档、App 补出高档、或 App 作为主源。

## 离线验证

- App 客户端：签名身份、无 Web Cookie、qn/fnval/fourk/trial、DASH 全音视频、预览保护、超时/取消/epoch。
- 双源仓储：8K 定向请求、App 合并与主回退、普通 1080P 无额外请求、App 失败保留 Web、预览拒绝。
- 合并器：高画质视频、AAC/FLAC/Dolby、同档码率、重复/时长/语音/预览隔离。
- 身份源：认证失效、网络失败不误清理、在途 revision 变化取消。
- 核心日志：字段输出、来源白名单、敏感字符串与数组边界、旧事件兼容。

最终全量结果：根应用 **6018 项通过、6 项跳过**；`bili_api` **1107 项通过**。 `flutter analyze --no-pub` 无问题；1127 个相关 Dart 文件格式无待变更，`git diff --check` 通过。

## 未验证边界

没有使用用户真实账号或原始视频发在线请求，也没有把测试桩中的 4K/杜比轨道当作线上解锁证据。
实际可用档位仍由片源、账号权益与服务端策略决定；设备能否解码 8K/杜比是另一项实机验收。
本次不改变下载器只选择 AAC 进行封装的既有约束，也未给 PGC/直播强行套用 UGC App 端点。
