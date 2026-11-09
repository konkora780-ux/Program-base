// Supabase の接続先（Supabase の Project Settings → API に表示される値を貼り付けます）
// anon key は「公開してよい鍵」です。データの保護は データベース側の関数とRLS で行っています。
// ※ service_role key（秘密の鍵）は絶対にここへ書かないでください。
window.ILEAGUE_CONFIG = {
  SUPABASE_URL: "https://wvxzzyzbcdlsqwrbbwht.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_-yhkCh3AFrV6b9pKa26Rjw_MEkZlp0n",
  // Stripe の支払いリンク（https://buy.stripe.com/…）。空のあいだは「購入する」ボタンを出さない。
  BUY_URL: "https://buy.stripe.com/test_28E6oIgmabyN3tU2uqaMU00",
  // Supabase の Edge Function の名前（コード支払い確認用）
  PURCHASE_FN: "swift-api",
};
