// Iリーグ デジタルプログラム：ネット購入（Stripe）用のサーバー側プログラム（Supabase Edge Function）【版2】
//
// できること
//   action "claim"   … 支払いが終わった人に閲覧コードを渡す（Stripeに「本当に支払い済みか」を問い合わせてから発行）
//   action "recover" … コードを忘れた人に、メールアドレス＋領収書番号が合えば同じコードをもう一度見せる
//
// Supabase の「Edge Functions → Secrets」に入れておく値
//   STRIPE_SECRET_KEY    … Stripeの制限付きキー（rk_…）。権限は「Checkout Sessions：読み取り」「PaymentIntents：読み取り」「Charges：読み取り」だけで十分
//   STRIPE_PAYMENT_LINK  … （任意）販売に使う支払いリンクのID（plink_…）。入れると、そのリンク以外の支払いではコードを出さない
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY は Supabase が自動で用意する。

const STRIPE_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const PAYMENT_LINK = Deno.env.get("STRIPE_PAYMENT_LINK") ?? "";
const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
// サーバー専用の鍵。Supabaseの鍵の形式が新旧どちらでも見つけられるようにしておく。
// どれも無いときは、Secrets に DB_SECRET_KEY（sb_secret_…）を自分で登録すれば使われる。
function serverKey(): string {
  for (const name of ["SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY", "DB_SECRET_KEY"]) {
    const v = Deno.env.get(name);
    if (v) return v;
  }
  const many = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (many) {
    try { const o = JSON.parse(many); return o.default ?? Object.values(o)[0] ?? ""; } catch { return many; }
  }
  return "";
}
const SB_KEY = serverKey();

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

// Stripe に問い合わせる（読み取りだけ）。見つからないときは null
async function stripe(path: string) {
  const res = await fetch("https://api.stripe.com/v1/" + path, { headers: { Authorization: "Bearer " + STRIPE_KEY } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error("stripe " + res.status);
  return await res.json();
}

// データベースの関数を呼ぶ（サーバー専用の鍵で）
async function db(fn: string, body: unknown) {
  const headers: Record<string, string> = { "Content-Type": "application/json", apikey: SB_KEY };
  if (SB_KEY.startsWith("eyJ")) headers.Authorization = "Bearer " + SB_KEY;
  const res = await fetch(SB_URL + "/rest/v1/rpc/" + fn, { method: "POST", headers, body: JSON.stringify(body) });
  if (!res.ok) throw new Error("db " + fn + " " + res.status + " " + (await res.text()));
  return await res.json();
}

const digits = (s: unknown) => String(s ?? "").replace(/[^0-9]/g, "");

async function claim(sessionId: string) {
  if (!/^cs_[A-Za-z0-9_]+$/.test(sessionId)) return reply({ error: "bad_request" }, 400);
  const s = await stripe("checkout/sessions/" + encodeURIComponent(sessionId));
  if (!s) return reply({ error: "bad_request" }, 400);
  if (s.status !== "complete" || s.payment_status !== "paid") return reply({ error: "not_paid" }, 402);
  if (PAYMENT_LINK && s.payment_link !== PAYMENT_LINK) return reply({ error: "other_product" }, 403);
  const r = await db("claim_purchase_code", {
    p_session_id: sessionId,
    p_email: s.customer_details?.email ?? "",
    p_amount: s.amount_total ?? null,
    p_payment_intent: typeof s.payment_intent === "string" ? s.payment_intent : "",
  });
  return reply({ code: r.code, serial: r.serial });
}

async function recover(email: string, receipt: string) {
  email = String(email ?? "").trim().toLowerCase();
  const want = digits(receipt);
  if (!email.includes("@") || want.length < 4) return reply({ error: "bad_request" }, 400);
  const look = await db("recover_lookup", { p_email: email });
  if (look.locked) return reply({ error: "locked" }, 429);
  let hit: number | null = null;
  for (const it of look.items ?? []) {
    const pi = await stripe("payment_intents/" + encodeURIComponent(it.pi) + "?expand[]=latest_charge");
    if (pi && digits(pi.latest_charge?.receipt_number) === want) { hit = it.id; break; }
  }
  const fin = await db("recover_finish", { p_email: email, p_purchase_id: hit });
  if (!fin.ok) return reply({ error: "not_found" }, 404);
  return reply({ code: fin.code });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "method" }, 405);
  try {
    const b = await req.json();
    if (b.action === "claim") return await claim(String(b.session_id ?? ""));
    if (b.action === "recover") return await recover(b.email, b.receipt);
    return reply({ error: "bad_request" }, 400);
  } catch (e) {
    console.error(e);
    return reply({ error: "server" }, 500);
  }
});
