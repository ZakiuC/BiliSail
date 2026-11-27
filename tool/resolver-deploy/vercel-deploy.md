# Vercel 免费部署解析服务器（港澳/台湾）

全程免费，无需信用卡，部署到 Vercel HK 节点（hkg1）。

## 一键部署

1. 打开 https://github.com/JasonZH6600/biliroaming-ts-server-vercel
2. 点 **Fork** 到自己账号
3. 打开 https://vercel.com/new → Import 刚 Fork 的仓库
4. Framework Preset 选 **Next.js**
5. 展开 **Environment Variables**，添加：

| Key | Value | 说明 |
|-----|-------|------|
| `AREA` | `hk` | 代理地区（hk/tw/th/cn） |
| `WEB_ON` | `true` | 允许 Web 端取流（关键！） |
| `LOGIN_ON` | `false` | 不要求登录 |
| `ACCESS_KEY` | （留空） | 不填则匿名 |
| `BLACKLIST_ON` | `false` | 关闭黑名单 |
| `CACHE_ON` | `true` | 开启缓存减少请求 |

6. 展开 **Build & Development Settings**，确认 Region 为 **hkg1 (Hong Kong)**
   （如果看不到地区选项，在 vercel.json 中加 `"regions": ["hkg1"]`）
7. 点 **Deploy**
8. 部署完成后获得 `https://<project>.vercel.app`
9. 在 BiliSail 设置中填入该地址，点「检测」验证

## 多地区

每个 Vercel 项目只代理一个地区。如需港澳+台湾+东南亚：
- Fork 三份，分别设 `AREA=hk`、`AREA=tw`、`AREA=th`
- 部署到 hkg1（港澳）和 sin1（东南亚）
- 在 BiliSail 中分别填入对应地区栏

## 免费额度

- Serverless Function 执行：100 GB-Hrs/月
- 带宽：100 GB/月
- 请求数：无硬性上限（公平使用）
- 个人追番完全够用

## 验证

部署后浏览器打开：
```
https://<project>.vercel.app/pgc/view/web/season?season_id=40664&area=hk
```
应返回 `code: 0` 且 episodes 非空、首集 `rights.area_limit: 0`。

再验证取流：
```
https://<project>.vercel.app/pgc/player/web/playurl?ep_id=458195&qn=80&fnval=4048&area=hk
```
应返回 `code: 0` 且 dash.video/audio 非空。
