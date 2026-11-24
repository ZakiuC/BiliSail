# 更新日志

应用版本号只维护在根 `pubspec.yaml`（`x.y.z+N`），每个可构建的变更都会递增。
更早版本见 [GitHub Releases](https://github.com/CKopoer/BiliSail/releases)。

## 1.3.1+10

### 修复

- **高画质地址被 CDN 拒绝时不再导致播放失败。** 1.3.1+9 日志显示：手机端身份确实拿到
  `120`（4K）与 `112`（1080P 高码率）条目，但实际请求这些地址返回 **HTTP 403**，
  播放器三次重开全部 `networkOpen` 失败。
- 选流后对高画质地址做一次单字节探测：只有 200／206 才使用该档，被拒绝时自动回落到 1080P，
  保证照常播放；探测无结论时不降档。
- 诊断新增 `probeHttpStatus`，可直接看到高档地址的真实响应码。

### 说明

- 这说明服务端虽然在列表里返回 4K／高码率条目，但并未授权实际取流，CDN 侧直接拒绝。
  该行为在客户端无法绕过；把条目显示出来却播放失败才是本轮真正要修的问题。
- “无限试用会员画质”当前只能影响请求参数与列表展示，不能把未授权的地址变成可播放。
- 若需要确认 BBZQ 的 4K 是否真的能播放（而不只是出现在菜单里），需要以同一账号在官方客户端
  实际起播观察；仅凭清晰度菜单不能判定。

## 1.3.1+9

### 修复

- **高画质第二次定位：PlayView 通了，但服务端按客户端身份限档。**
  1.3.1+8 的诊断显示 `appProtocol=playview`、`outcome=success`、`requestedQuality=127`、
  `trialRequested=true`，但服务端只返回 `80/64/32/16` 四档，说明请求格式已正确，
  限制来自它认定的客户端能力。
- 新增可切换的客户端身份：先用现有 HD（`android_hd`／build 2001100，2.0.1）请求，
  若最高档仍不超过 1080P，再用手机端身份（`android`／build 9000100，9.0.1）重试并合并结果。
  两种身份都只改变公开设备声明，使用同一账号令牌。
- 补齐官方 gRPC 公共元数据头：`x-bili-trace-id`、`x-bili-exps-bin`、
  `x-bili-aurora-zone`、`x-bili-gaia-vtoken`、`bili-http-engine`，User-Agent 与所选身份保持一致。
- 诊断新增 `playview_phone` 来源，便于区分两次尝试各自返回的档位。

### 未验证

- 尚未确认服务端是否因手机端身份放开 4K／杜比／8K；下次日志的 `appPlayInfoResolved`
  会分别记录 `playview` 与 `playview_phone` 的实际档位。

## 1.3.1+8

### 修复

- **高画质取流改用官方 App `PlayViewUnite` 协议。** 此前 Web 与旧 App JSON 端点在这台设备上都只返回
  360P／480P／720P／1080P 四档，4K、杜比视界与 1080P 高码率无法出现在清晰度菜单。
  - 请求携带 `fnval=4048`、`fourk`、`voice_balance` 与 `device`／`metadata`／`network`／
    `locale`／`fawkes` 二进制元数据头，可选 `is_need_trial` 画质试用。
  - 解析普通音频、杜比音频与无损 FLAC；`need_vip` 只作为元数据，不再过滤实际带地址的 DASH 轨道。
  - PlayView 失败时回退旧 JSON 端点，两者都失败仍保留完整 Web 播放；预览片段不会被当成完整视频。
- **修复合并重复轨道。** 同一档位在不同 CDN 地址下会被重复计入并误标为「已合并」，现在按
  `mimeType/id/codecs/bandwidth` 去重，URL 变化不再算新轨道。
- 明确选择 8K 时 Web 首发使用 `qn=127`，不再沿用 HDR 发现档 `129`。

### 新增

- 播放增强设置：解锁最高码率、无限试用会员画质、无限试用界面同步、伪装 Wi-Fi。
  伪装 Wi-Fi 只改变 App 身份声明与新直播间网络默认画质，不修改真实网络与 Web 取流。
- 番剧地区解锁：可配置港澳／台湾／东南亚／大陆自建解析服务器与默认地区，仅在官方详情或取流被
  地区拒绝时回退；默认不发送 Cookie 与访问密钥。
- 避开 HDR／杜比视界；CDN 测速新增「用最快线路」。
- 诊断日志新增 `playInfoResolved` 与 `appPlayInfoResolved`：记录来源、协议、试用是否启用以及
  请求和实际的音视频档位，不含视频 ID、URL、Cookie 或 token。

### 未验证

- 未使用真实账号在线确认服务端是否返回 4K／杜比视界；实际可用档位仍取决于片源与账号权益。
- 未在 Android／iOS／桌面实机验证，本地也没有生成安装包，本轮由 GitHub Actions 构建。
