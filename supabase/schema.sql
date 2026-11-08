-- =====================================================================
-- Iリーグ デジタルプログラム データベース定義
-- Supabase の「SQL Editor」に全文を貼り付けて1回実行してください。
--
-- 考え方
--  * どの表も RLS（行レベルセキュリティ）を有効にし、閲覧者（anon）は
--    表を直接読めない状態にします。
--  * 閲覧者は「コードを渡すと中身を返す関数」だけを呼べます。
--    関数の中でコードを照合し、正しいときだけデータを返します。
--  * 管理者は Supabase Auth でログインし、admins 表に登録された人だけが
--    書き込めます。
--  * 掲載不同意（×）の選手も運営用に保存するが、購入者向けの関数は
--    同意済み（consent = true）の選手だけを返す。
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 表
-- ---------------------------------------------------------------------

-- 管理者（Supabase Auth のユーザーIDを登録）
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

-- 年度（シーズン）。コードは年度ごとに有効
create table if not exists public.seasons (
  id          serial primary key,
  year        int  not null unique,              -- 例: 2027
  title       text not null,                     -- 例: 2027 Iリーグ岩手 公式プログラム
  greeting    text not null default '',          -- 挨拶文
  regulation  text not null default '',          -- レギュレーション
  valid_from  date not null,                     -- コード有効開始日
  valid_to    date not null,                     -- コード有効終了日
  is_current  boolean not null default false,    -- 現在販売中の年度
  updated_at  timestamptz not null default now(),
  check (valid_from <= valid_to)
);
create unique index if not exists seasons_one_current on public.seasons(is_current) where is_current;

-- リーグ（ディビジョン）。年度ごとに管理画面で追加・名前変更・並べ替え・削除できる
create table if not exists public.divisions (
  id          serial primary key,
  season_id   int  not null references public.seasons(id) on delete cascade,
  name        text not null,               -- 例: DIVISION Ⅰ
  sort_order  int  not null default 0,
  unique (season_id, name)
);

-- チーム
create table if not exists public.teams (
  id                    serial primary key,
  season_id             int  not null references public.seasons(id) on delete cascade,
  name                  text not null,
  sort_order            int  not null default 0,
  manager               text not null default '',
  coaches               text[] not null default '{}',
  -- ユニフォーム: {"field_main":{"top":"","bottom":"","socks":""}, "field_sub":{...}, "gk_main":{...}, "gk_sub":{...}}
  uniform               jsonb not null default '{}'::jsonb,
  intro                 text not null default '',   -- チーム紹介文（ユニフォーム表の左に載る）
  photo_ok              boolean not null default true,   -- 写真を掲載するか（登録すれば掲載。管理画面で個別に非表示にできる）
  updated_at            timestamptz not null default now(),
  unique (season_id, name)
);

-- 以前の版で作った表に「チーム紹介」列を足し、古いリーグ欄を消す（新規なら何もしない）
-- チームの「主な所属リーグ」は廃止。どのリーグに載るかは選手ごとの所属リーグだけで決める
alter table public.teams drop column if exists division_id;
alter table public.teams drop column if exists league;
-- 監督コメントは載せないことになったため、以前の版の列があれば消す
alter table public.teams drop column if exists manager_comment;
alter table public.teams drop column if exists show_manager_comment;
alter table public.teams add column if not exists intro text not null default '';
-- 写真は「登録すれば掲載」に変更（未同意の選手が写っていても掲載してよい：2026-11-08決定）
alter table public.teams alter column photo_ok set default true;

-- チーム写真（ブラウザで縮小したJPEGを文字列で保存。取り出しは関数経由のみ）
create table if not exists public.team_photos (
  team_id    int primary key references public.teams(id) on delete cascade,
  data_url   text not null,            -- data:image/jpeg;base64,...
  updated_at timestamptz not null default now(),
  check (data_url like 'data:image/%' and length(data_url) < 3000000)
);

-- 選手
create table if not exists public.players (
  id           serial primary key,
  team_id      int  not null references public.teams(id) on delete cascade,
  sort_order   int  not null default 0,
  consent      boolean not null default true,   -- false = 掲載不同意（×）。管理画面では見えるが、購入者には一切出さない
  number       text,     -- 背番号
  position     text,     -- ポジション
  grade        text,     -- 学年
  name         text,     -- 名前
  name_kana    text,     -- ふりがな
  club_u12     text,     -- U12 所属クラブ
  club_u15     text,     -- U15 所属クラブ
  height       text,     -- 身長
  division_id  int references public.divisions(id) on delete set null  -- 選手ごとの所属リーグ（空欄＝どのリーグにも所属しない。学校紹介ページにだけ載る）
);
alter table public.players add column if not exists division_id int references public.divisions(id) on delete set null;
-- 出身中学校は掲載しないことになったため、以前の版の列があれば消す
alter table public.players drop column if exists junior_high;
-- 以前の版で作った「未同意は名前を保存できない」制約があれば外す
alter table public.players drop constraint if exists players_consent_minimum;
create index if not exists players_team on public.players(team_id, sort_order);

-- 日程（対戦表もここから作ります）
create table if not exists public.matches (
  id            serial primary key,
  season_id     int  not null references public.seasons(id) on delete cascade,
  league        text not null default '',
  round         text not null default '',   -- 節
  match_date    date,
  kickoff       text not null default '',   -- 例: 10:00
  venue         text not null default '',
  home_team_id  int references public.teams(id) on delete set null,
  away_team_id  int references public.teams(id) on delete set null,
  note          text not null default '',
  updated_at    timestamptz not null default now()
);
create index if not exists matches_season on public.matches(season_id, match_date);

-- 閲覧コード（コードそのものは保存せず、ハッシュ＝復元できない変換値だけを保存）
create table if not exists public.access_codes (
  id            serial primary key,          -- 購入番号（透かしに使う）
  season_id     int  not null references public.seasons(id) on delete cascade,
  code_hash     text not null unique,
  hint          text not null,               -- コードの末尾4文字（問い合わせ時の照合用）
  memo          text not null default '',    -- 注文番号など（購入者の氏名は入れない運用を推奨）
  status        text not null default 'active' check (status in ('active','stopped')),
  created_at    timestamptz not null default now(),
  stopped_at    timestamptz,
  first_used_at timestamptz,
  last_used_at  timestamptz,
  use_count     int not null default 0
);

-- ---------------------------------------------------------------------
-- RLS（表を直接読めるのは管理者だけ）
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

alter table public.admins       enable row level security;
alter table public.seasons      enable row level security;
alter table public.divisions    enable row level security;
alter table public.teams        enable row level security;
alter table public.team_photos  enable row level security;
alter table public.players      enable row level security;
alter table public.matches      enable row level security;
alter table public.access_codes enable row level security;

drop policy if exists admin_all on public.admins;
create policy admin_all on public.admins       for select to authenticated using (public.is_admin());
drop policy if exists admin_all on public.seasons;
create policy admin_all on public.seasons      for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.divisions;
create policy admin_all on public.divisions    for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.teams;
create policy admin_all on public.teams        for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.team_photos;
create policy admin_all on public.team_photos  for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.players;
create policy admin_all on public.players      for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.matches;
create policy admin_all on public.matches      for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists admin_all on public.access_codes;
create policy admin_all on public.access_codes for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 閲覧者（anon）からは表への権限そのものも外しておく（二重の鍵）
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- ---------------------------------------------------------------------
-- コードの照合
-- ---------------------------------------------------------------------

-- 入力ゆれを吸収（小文字→大文字、ハイフン・空白を除去）
create or replace function public._normalize_code(p_code text)
returns text language sql immutable
as $$ select regexp_replace(upper(coalesce(p_code,'')), '[^A-Z0-9]', '', 'g') $$;

create or replace function public._hash_code(p_code text)
returns text language sql immutable
set search_path = public, extensions
as $$ select encode(extensions.digest(public._normalize_code(p_code), 'sha256'), 'hex') $$;

-- 有効なコードなら access_codes の行を返す（無効なら null）
create or replace function public._check_code(p_code text, p_touch boolean)
returns public.access_codes language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  r public.access_codes;
  today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  if length(public._normalize_code(p_code)) <> 12 then
    return null;
  end if;
  select c.* into r
    from public.access_codes c
    join public.seasons s on s.id = c.season_id
   where c.code_hash = public._hash_code(p_code)
     and c.status = 'active'
     and today between s.valid_from and s.valid_to;
  if r.id is null then
    return null;
  end if;
  if p_touch then
    update public.access_codes
       set use_count = use_count + 1,
           last_used_at = now(),
           first_used_at = coalesce(first_used_at, now())
     where id = r.id;
  end if;
  return r;
end $$;

-- 閲覧者がコードを入れたときに呼ぶ。正しければ年度名と購入番号を返す
create or replace function public.verify_code(p_code text)
returns jsonb language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare r public.access_codes; s public.seasons;
begin
  r := public._check_code(p_code, true);
  if r.id is null then
    return jsonb_build_object('ok', false);
  end if;
  select * into s from public.seasons where id = r.season_id;
  return jsonb_build_object('ok', true, 'serial', r.id, 'season', s.title, 'valid_to', s.valid_to);
end $$;

-- プログラム本体（写真以外のすべて）を返す
create or replace function public.get_program(p_code text)
returns jsonb language plpgsql stable security definer
set search_path = public, extensions
as $$
declare r public.access_codes; result jsonb;
begin
  r := public._check_code(p_code, false);
  if r.id is null then
    raise exception 'invalid_code' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'serial', r.id,
    'season', jsonb_build_object('year', s.year, 'title', s.title, 'greeting', s.greeting,
                                 'regulation', s.regulation, 'valid_to', s.valid_to,
                                 'updated_at', s.updated_at),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'manager', t.manager,
        'coaches', to_jsonb(t.coaches), 'uniform', t.uniform,
        'intro', t.intro,
        'has_photo', (t.photo_ok and exists (select 1 from public.team_photos p where p.team_id = t.id)),
        'players', coalesce((
          select jsonb_agg(jsonb_build_object(
            'number', p.number, 'position', p.position, 'grade', p.grade, 'consent', p.consent,
            'name', p.name, 'name_kana', p.name_kana, 'club_u12', p.club_u12, 'club_u15', p.club_u15,
            'height', p.height,
            'league', coalesce((select d2.name from public.divisions d2 where d2.id = p.division_id), '')
          ) order by p.sort_order, p.id)
          -- 購入者に渡すのは掲載同意のある選手だけ（所属リーグ空欄の選手は、前半の学校紹介ページに「リーグ外の選手」として載る）
          from public.players p where p.team_id = t.id and p.consent), '[]'::jsonb)
      ) order by t.sort_order, t.id)
      from public.teams t
      where t.season_id = s.id), '[]'::jsonb),
    'divisions', coalesce((
      select jsonb_agg(d.name order by d.sort_order, d.id) from public.divisions d where d.season_id = s.id), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'league', m.league, 'round', m.round, 'date', m.match_date,
        'kickoff', m.kickoff, 'venue', m.venue,
        'home', m.home_team_id, 'away', m.away_team_id, 'note', m.note
      ) order by m.match_date nulls last, m.kickoff, m.id)
      from public.matches m where m.season_id = s.id), '[]'::jsonb)
  ) into result
  from public.seasons s where s.id = r.season_id;

  return result;
end $$;

-- チーム写真を1枚返す（同意確認済みのチームのみ）
create or replace function public.get_team_photo(p_code text, p_team_id int)
returns text language plpgsql stable security definer
set search_path = public, extensions
as $$
declare r public.access_codes; d text;
begin
  r := public._check_code(p_code, false);
  if r.id is null then
    raise exception 'invalid_code' using errcode = '28000';
  end if;
  select p.data_url into d
    from public.team_photos p join public.teams t on t.id = p.team_id
   where t.id = p_team_id and t.season_id = r.season_id and t.photo_ok;
  return d;
end $$;

-- ---------------------------------------------------------------------
-- 管理者用の関数
-- ---------------------------------------------------------------------

-- コードを n 個発行し、コード本体はこの1回だけ返す（あとから見ることはできません）
create or replace function public.admin_issue_codes(p_season_id int, p_count int, p_memo text default '')
returns table(serial int, code text) language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- 見間違えやすい 0 O 1 I を除いた32文字
  b bytea; raw text; i int; k int; new_id int;
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_count < 1 or p_count > 500 then raise exception '1〜500個の範囲で指定してください'; end if;
  for i in 1..p_count loop
    loop
      b := extensions.gen_random_bytes(12);
      raw := '';
      for k in 0..11 loop
        raw := raw || substr(alphabet, (get_byte(b, k) % 32) + 1, 1);  -- 256は32で割り切れるので偏りなし
      end loop;
      begin
        insert into public.access_codes(season_id, code_hash, hint, memo)
        values (p_season_id, public._hash_code(raw), right(raw, 4), coalesce(p_memo, ''))
        returning id into new_id;
        exit;
      exception when unique_violation then
        -- ごくまれな重複は作り直し
      end;
    end loop;
    serial := new_id;
    code := substr(raw,1,4) || '-' || substr(raw,5,4) || '-' || substr(raw,9,4);
    return next;
  end loop;
end $$;

-- 年度に既定のリーグ一覧（まだ1つもないときだけ）を入れる
create or replace function public.admin_seed_divisions(p_season_id int)
returns void language plpgsql volatile security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if exists (select 1 from public.divisions where season_id = p_season_id) then return; end if;
  insert into public.divisions(season_id, name, sort_order)
  select p_season_id, x.name, x.ord
    from unnest(array['DIVISION Ⅰ','DIVISION Ⅱ','DIVISION Ⅲ','DIVISION Ⅳ北','DIVISION Ⅳ南','DIVISION Ⅳサテライト'])
         with ordinality as x(name, ord);
end $$;

-- コードの停止・再開
create or replace function public.admin_set_code_status(p_id int, p_status text)
returns void language plpgsql volatile security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update public.access_codes
     set status = p_status,
         stopped_at = case when p_status = 'stopped' then now() else null end
   where id = p_id;
end $$;

-- 入力されたコードから購入番号を調べる（問い合わせ対応・流出時の特定用）
create or replace function public.admin_find_code(p_code text)
returns setof public.access_codes language plpgsql stable security definer
set search_path = public, extensions
as $$
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return query select * from public.access_codes where code_hash = public._hash_code(p_code);
end $$;

-- Excel 1チーム分の取り込み（チーム情報の上書き＋選手名簿の入れ替えを一括で行う）
-- 掲載不同意（consent = false）の選手も保存します（運営用）。購入者には get_program で除外されます。
create or replace function public.admin_import_team(p_season_id int, p jsonb)
returns int language plpgsql volatile security definer
set search_path = public
as $$
declare tid int; pdid int; pl jsonb; n int := 0; ok boolean;
begin
  if not public.is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'チーム名が空です'; end if;
  insert into public.teams(season_id, name, manager, coaches, uniform, intro)
  values (p_season_id, trim(p->>'name'), coalesce(p->>'manager',''),
          coalesce((select array_agg(x) from jsonb_array_elements_text(p->'coaches') x where trim(x) <> ''), '{}'),
          coalesce(p->'uniform','{}'::jsonb), coalesce(p->>'intro',''))
  on conflict (season_id, name) do update
     set manager = excluded.manager, coaches = excluded.coaches,
         uniform = excluded.uniform, intro = excluded.intro, updated_at = now()
  returning id into tid;

  delete from public.players where team_id = tid;

  for pl in select * from jsonb_array_elements(coalesce(p->'players','[]'::jsonb)) loop
    ok := coalesce((pl->>'consent')::boolean, false);
    n := n + 1;
    -- 選手の所属リーグ：空欄ならどのリーグにも所属しない（リーグの名簿には出ず、学校紹介ページにだけ載る）
    pdid := null;
    if coalesce(trim(pl->>'league'), '') <> '' then
      select id into pdid from public.divisions where season_id = p_season_id and name = trim(pl->>'league');
      if pdid is null then raise exception '背番号%の選手の所属リーグ「%」が、リーグ一覧にありません', pl->>'number', trim(pl->>'league'); end if;
    end if;
    insert into public.players(team_id, sort_order, consent, number, position, grade,
                               name, name_kana, club_u12, club_u15, height, division_id)
    values (tid, n, ok,
            nullif(trim(pl->>'number'),''), nullif(trim(pl->>'position'),''), nullif(trim(pl->>'grade'),''),
            nullif(trim(pl->>'name'),''),
            nullif(trim(pl->>'name_kana'),''),
            nullif(trim(pl->>'club_u12'),''),
            nullif(trim(pl->>'club_u15'),''),
            nullif(trim(pl->>'height'),''),
            pdid);
  end loop;
  return tid;
end $$;

-- ---------------------------------------------------------------------
-- 関数の実行権限
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.verify_code(text)            to anon, authenticated;
grant execute on function public.get_program(text)            to anon, authenticated;
grant execute on function public.get_team_photo(text, int)    to anon, authenticated;
grant execute on function public.is_admin()                   to authenticated;
grant execute on function public.admin_issue_codes(int, int, text) to authenticated;
grant execute on function public.admin_set_code_status(int, text)  to authenticated;
grant execute on function public.admin_seed_divisions(int)    to authenticated;
grant execute on function public.admin_find_code(text)        to authenticated;
grant execute on function public.admin_import_team(int, jsonb) to authenticated;
