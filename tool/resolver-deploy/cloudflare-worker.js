/**
 * BiliSail 番剧地区解锁 — Cloudflare Workers 免费解析服务器
 *
 * 部署步骤（全程免费，无需信用卡）：
 * 1. 注册 https://dash.cloudflare.com （免费计划即可）
 * 2. 左侧 Workers & Pages → Create → Create Worker
 * 3. 把本文件内容粘贴到编辑器，替换默认代码
 * 4. 点 Deploy，获得 https://<name>.<subdomain>.workers.dev
 * 5. 在 BiliSail 设置 → 播放 → 番剧地区解锁 → 推荐解析服务器 → 检测
 *    或手动填入该地址到港澳/台湾栏
 *
 * 免费额度：100,000 请求/天，足够个人使用。
 * 注意：CF Workers 出口 IP 可能被 B 站风控，如遇 -412 可换 Vercel 方案。
 */

const UPSTREAM_CN = "https://api.bilibili.com";
const UPSTREAM_INTL = "https://api.global.bilibili.com";

// 允许的路径前缀
const ALLOWED_PATHS = [
  "/pgc/view/v2/app/season",
  "/pgc/view/web/season",
  "/pgc/player/api/playurl",
  "/pgc/player/web/playurl",
  "/intl/gateway/v2/ogv/view/app/season",
  "/intl/gateway/v2/ogv/playurl",
];

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // 只允许 PGC 相关路径
    if (!ALLOWED_PATHS.some((p) => path.startsWith(p))) {
      return new Response(JSON.stringify({ code: -404, message: "not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 根据路径选择上游
    const isIntl = path.startsWith("/intl/");
    const upstream = isIntl ? UPSTREAM_INTL : UPSTREAM_CN;

    // 转发请求，保留 query 参数
    const targetUrl = upstream + path + url.search;
    const resp = await fetch(targetUrl, {
      method: "GET",
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        Referer: "https://www.bilibili.com/",
        Accept: "application/json",
      },
      redirect: "follow",
    });

    // 透传响应
    const body = await resp.arrayBuffer();
    return new Response(body, {
      status: resp.status,
      headers: {
        "Content-Type": resp.headers.get("Content-Type") || "application/json",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-store",
      },
    });
  },
};
