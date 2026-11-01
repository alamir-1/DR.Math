/* Cloudflare Worker (مجاني، من غير كارت) — بيبعت Push للموبايل والتطبيق مقفول.
   الصفحة بتنده عليه بعد ما تكتب الإشعار في Firebase: { recipient, id }.
   الـ Worker بيقرا الإشعار من Firebase بنفسه (فمحدش يقدر يزوّر نص الإشعار)،
   ويبعته مرة واحدة بس (بيعلّم عليه pushed:true).
   المتغير السري المطلوب: SERVICE_ACCOUNT = محتوى ملف الـ service account JSON كله. */

const DB = "https://soon-8c1e6-default-rtdb.firebaseio.com";
const PROJECT = "soon-8c1e6";
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type" };
const SAFE = /^[A-Za-z0-9_\-]{1,200}$/;

let cached = { token: null, exp: 0 };

const b64url = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlStr = (s) => b64url(new TextEncoder().encode(s));

async function accessToken(env) {
  if (cached.token && Date.now() < cached.exp) return cached.token;
  const sa = JSON.parse(env.SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);
  const head = b64urlStr(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64urlStr(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/userinfo.email",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(head + "." + claim));
  const jwt = head + "." + claim + "." + b64url(sig);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=" + jwt,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("oauth failed: " + JSON.stringify(j));
  cached = { token: j.access_token, exp: Date.now() + 50 * 60 * 1000 };
  return cached.token;
}

const reply = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });

export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
    if (req.method === "GET") return reply({ ok: true, service: "edu-push" });
    if (req.method !== "POST") return reply({ error: "method" }, 405);
    try {
      const { recipient, id } = JSON.parse(await req.text());
      if (!SAFE.test(recipient || "") || !SAFE.test(id || "")) return reply({ error: "bad input" }, 400);
      const at = await accessToken(env);
      const q = "?access_token=" + at;

      const nRes = await fetch(`${DB}/notifications/${recipient}/${id}.json${q}`);
      const n = await nRes.json();
      if (!n) return reply({ skipped: "no such notification" });
      if (n.pushed || n.read) return reply({ skipped: "already pushed/read" });
      if (Date.now() - (n.at || 0) > 10 * 60 * 1000) return reply({ skipped: "too old" });
      await fetch(`${DB}/notifications/${recipient}/${id}.json${q}`, { method: "PATCH", body: JSON.stringify({ pushed: true }) });

      const tRes = await fetch(`${DB}/fcmTokens/${recipient}.json${q}&shallow=true`);
      const tokens = Object.keys((await tRes.json()) || {});
      if (!tokens.length) return reply({ sent: 0, note: "no tokens for recipient" });

      let sent = 0, failed = 0;
      await Promise.all(tokens.map(async (token) => {
        const r = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`, {
          method: "POST",
          headers: { Authorization: "Bearer " + at, "Content-Type": "application/json" },
          body: JSON.stringify({ message: {
            token,
            notification: { title: String(n.title || "إشعار جديد"), body: String(n.body || "") },
            data: { category: String(n.category || "") },
            android: { priority: "HIGH", ttl: "86400s", notification: {
              channel_id: "edu_high", icon: "ic_stat_notify", color: "#3FA535",
              default_sound: true, default_vibrate_timings: true,
              notification_priority: "PRIORITY_HIGH", visibility: "PUBLIC" } },
          } }),
        });
        if (r.ok) { sent++; return; }
        failed++;
        const t = await r.text();
        if (r.status === 404 || /UNREGISTERED/.test(t)) {
          await fetch(`${DB}/fcmTokens/${recipient}/${encodeURIComponent(token)}.json${q}`, { method: "DELETE" });
        }
      }));
      return reply({ sent, failed });
    } catch (e) {
      return reply({ error: String(e && e.message || e) }, 500);
    }
  },
};
