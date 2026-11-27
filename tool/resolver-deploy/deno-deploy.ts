/**
 * BiliSail 番剧地区解锁 — Deno Deploy 免费解析服务器
 *
 * 部署步骤（免费，无需信用卡）：
 * 1. 打开 https://dash.deno.com → 用 GitHub 登录
 * 2. New Project → Deploy from URL → 粘贴本文件 raw URL
 *    或 New Project → Playground → 粘贴本文件内容
 * 3. 部署后获得 https://<project>.deno.dev
 * 4. 在 BiliSail 设置中填入该地址
 *
 * 免费额度：100,000 请求/天，100 GiB 传输/月。
 * Deno Deploy 出口分布在全球多个区域，B 站风控概率低于 CF Workers。
 */

const UPSTREAM_CN = "https://api.bilibili.com";
const UPSTREAM_INTL = "https://api.global.bilibili.com";

const ALLOWED_PATHS = [
  "/pgc/view/v2/app/season",
  "/pgc/view/web/season",
  "/pgc/player/api/playurl",
  "/pgc/player/web/playurl",
  "/intl/gateway/v2/ogv/view/app/season",
  "/intl/gateway/v2/ogv/playurl",
];

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const path = url.pathname;

  if (!ALLOWED_PATHS.some((p) => path.startsWith(p))) {
    return new Response(JSON.stringify({ code: -404, message: "not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const isIntl = path.startsWith("/intl/");
  const upstream = isIntl ? UPSTREAM_INTL : UPSTREAM_CN;
  const targetUrl = upstream + path + url.search;

  const resp = await fetch(targetUrl, {
    headers: {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Referer": "https://www.bilibili.com/",
      "Accept": "application/json",
    },
    redirect: "follow",
  });

  const body = await resp.arrayBuffer();
  return new Response(body, {
    status: resp.status,
    headers: {
      "Content-Type": resp.headers.get("Content-Type") || "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
    },
  });
});
