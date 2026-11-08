// 画面確認用の架空データ（実在の学校・人物ではありません）。?demo=1 のときだけ使われます。
(function () {
  const pos = ["GK", "DF", "DF", "DF", "DF", "MF", "MF", "MF", "FW", "FW", "MF", "GK"];
  const fam = ["佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤", "吉田", "山田"];
  const famK = ["さとう", "すずき", "たかはし", "たなか", "いとう", "わたなべ", "やまもと", "なかむら", "こばやし", "かとう", "よしだ", "やまだ"];
  const giv = ["翔太", "大輝", "陸", "蓮", "悠真", "颯太", "湊", "陽向", "樹", "蒼", "大和", "健"];
  const givK = ["しょうた", "だいき", "りく", "れん", "ゆうま", "そうた", "みなと", "ひなた", "いつき", "あおい", "やまと", "けん"];
  function players(seed, count) {
    return Array.from({ length: count }, (_, i) => pos[i % 12]).map((p, i) => {
      const consent = true; // 掲載不同意（×）の選手は購入者には届かないため、見本も全員掲載
      return consent
        ? { number: String(i + 1), position: p, grade: String((i % 3) + 1), consent: true,
            name: fam[(i + seed) % 12] + " " + giv[(i * 7 + seed) % 12],
            name_kana: famK[(i + seed) % 12] + " " + givK[(i * 7 + seed) % 12],
            club_u12: i % 7 === 3 ? "架空とてもながいサッカースポーツ少年団" : "架空FC" + ((i % 4) + 1), club_u15: i % 5 === 2 ? "架空フットボールクラブジュニアユースU-15" : "架空ジュニアユース" + ((i % 3) + 1),
            height: String(165 + ((i * 3 + seed) % 20)) }
        : { number: String(i + 1), position: p, grade: String((i % 3) + 1), consent: false,
            name: null, name_kana: null, club_u12: null, club_u15: null, height: null };
    });
  }
  const u = (a, b, c) => ({ top: a, bottom: b, socks: c });
  const names = ["架空A高校", "架空B高校", "架空C高校", "架空D高校"];
  const lgs = ["DIVISION Ⅰ", "DIVISION Ⅰ", "DIVISION Ⅱ", "DIVISION Ⅱ"];
  const divisions = ["DIVISION Ⅰ", "DIVISION Ⅱ", "DIVISION Ⅲ", "DIVISION Ⅳ北", "DIVISION Ⅳ南", "DIVISION Ⅳサテライト"];
  const teams = names.map((n, i) => ({
    id: i + 1, name: n, manager: ["架空 一郎", "架空 二郎", "架空 三郎", "架空 四郎"][i],
    coaches: ["見本 太郎", "見本 花子"],
    uniform: { field_main: u("青", "白", "青"), field_sub: u("白", "青", "白"),
               gk_main: u("黄", "黒", "黄"), gk_sub: u("緑", "緑", "緑") },
    intro: n + "は、粘り強い守備と素早い攻撃が持ち味のチームです。今季は全員で声をかけ合い、一戦一戦を大切に戦います。（見本の文章です）",
    has_photo: i % 2 === 0,
    // 1つの学校が複数リーグにチームを持つ例：架空A高校はⅠ部とⅣサテライト、架空C高校はⅡ部とⅣ南。架空B高校の5名は所属リーグ空欄（リーグ外）、架空D高校は全員リーグ外
    players: players(i, i === 0 ? 120 : i === 3 ? 12 : 50).map((p, k) => ({ ...p, league: i === 0 && k >= 60 ? "DIVISION Ⅳサテライト" : i === 2 && k >= 28 ? "DIVISION Ⅳ南" : i === 1 && k >= 45 ? "" : i === 3 ? "" : lgs[i] })),
  }));
  const matches = [];
  let id = 1;
  const pairs = [[1, 2, 3, 4], [1, 3, 2, 4], [1, 4, 2, 3]];
  pairs.forEach((p, r) => {
    const d = new Date(2027, 3, 12 + r * 14);
    const ds = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    matches.push({ id: id++, league: lgs[p[0] - 1] === lgs[p[1] - 1] ? lgs[p[0] - 1] : "", round: "第" + (r + 1) + "節", date: ds, kickoff: "10:00", venue: "架空グラウンド", home: p[0], away: p[1], note: "" });
    matches.push({ id: id++, league: lgs[p[2] - 1] === lgs[p[3] - 1] ? lgs[p[2] - 1] : "", round: "第" + (r + 1) + "節", date: ds, kickoff: "12:30", venue: "架空グラウンド", home: p[2], away: p[3], note: "" });
  });
  window.ILEAGUE_DEMO = {
    serial: 9999,
    season: {
      year: 2027, title: "2027 Iリーグ岩手 公式プログラム（見本）",
      greeting: "これは画面確認用の見本です。\n本番では協会からの挨拶文がここに入ります。",
      regulation: "・試合時間：90分（45分ハーフ）\n・勝点：勝ち3、引き分け1、負け0\n（見本の文章です）",
      valid_to: "2028-03-31", updated_at: new Date().toISOString(),
    },
    divisions, teams, matches,
  };
  // 見本のチーム写真（灰色の板に文字を描いた画像）
  window.ILEAGUE_DEMO_PHOTO = function (teamName) {
    const c = document.createElement("canvas"); c.width = 1270; c.height = 890;
    const g = c.getContext("2d"); g.fillStyle = "#7a8a99"; g.fillRect(0, 0, 1270, 890);
    g.fillStyle = "#fff"; g.font = "bold 64px sans-serif"; g.textAlign = "center";
    g.fillText(teamName + "（見本写真）", 635, 465);
    return c.toDataURL("image/jpeg", 0.7);
  };
})();
