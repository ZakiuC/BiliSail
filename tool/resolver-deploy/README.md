# 免费自建解析服务器

没有海外 VPS 也能拥有自己的解析服务器。以下三种方案全程免费、无需信用卡：

| 方案 | 免费额度 | 出口地区 | 部署难度 | 风控风险 |
|------|----------|----------|----------|----------|
| **Vercel** | 100 GB-Hrs/月 | HK (hkg1) / Singapore (sin1) | ★☆☆ 一键 Fork | 低 |
| **Deno Deploy** | 10 万请求/天 | 全球多区域 | ★☆☆ Playground | 低 |
| **Cloudflare Workers** | 10 万请求/天 | 全球边缘 | ★☆☆ 粘贴代码 | 中（部分 IP 被 B 站封） |

## 推荐顺序

1. **Vercel**（最稳）：Fork [biliroaming-ts-server-vercel](https://github.com/JasonZH6600/biliroaming-ts-server-vercel)，
   设 `WEB_ON=true` + `LOGIN_ON=false`，部署到 hkg1。详见 [vercel-deploy.md](vercel-deploy.md)。
2. **Deno Deploy**（最简单）：打开 [dash.deno.com](https://dash.deno.com)，Playground 粘贴
   [deno-deploy.ts](deno-deploy.ts)，Deploy。
3. **Cloudflare Workers**（备选）：[dash.cloudflare.com](https://dash.cloudflare.com) → Workers →
   Create → 粘贴 [cloudflare-worker.js](cloudflare-worker.js) → Deploy。

## 部署后验证

在 BiliSail「设置 → 播放 → 番剧地区解锁」中：
- 把部署得到的地址填入对应地区栏
- 点旁边的「检测」按钮
- 显示「可用」即成功

或浏览器直接访问：
```
https://<你的地址>/pgc/view/web/season?season_id=40664&area=hk
```
返回 `code: 0`、episodes 非空、首集 `area_limit: 0` 即为成功。

## 多地区

- Vercel：每个项目一个地区，Fork 多份分别设 AREA=hk/tw/th
- Deno/CF：单实例同时支持所有地区（自动按路径选上游）

## 注意

- 这些平台出口 IP 是共享的，高并发时可能触发 B 站风控（-412）
- 个人追番（每天几十次请求）完全不会触发
- 如果某个平台被风控，换另一个即可
- 不要公开分享你的部署地址，避免被滥用导致封禁
