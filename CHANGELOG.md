# 更新日志

应用版本号只维护在根 `pubspec.yaml`（`x.y.z+N`），每个可构建的变更都会递增。
更早版本见 [GitHub Releases](https://github.com/CKopoer/BiliSail/releases)。

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
