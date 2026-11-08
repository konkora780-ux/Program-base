// Supabase の接続先（Supabase の Project Settings → API に表示される値を貼り付けます）
// anon key は「公開してよい鍵」です。データの保護は データベース側の関数とRLS で行っています。
// ※ service_role key（秘密の鍵）は絶対にここへ書かないでください。
window.ILEAGUE_CONFIG = {
  SUPABASE_URL: "https://xxxxxxxx.supabase.co",
  SUPABASE_ANON_KEY: "ここに anon key を貼り付け",
};
