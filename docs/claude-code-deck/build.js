const pptxgen = require("pptxgenjs");

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.3 x 7.5
pres.author = "takuha";
pres.title = "Claude Code 完全入門 — 要点まとめ";

const W = 13.3, H = 7.5, M = 0.75;

// ---- palette -------------------------------------------------------------
const INK = "12151C";
const INK2 = "1D2230";
const SLATE = "39435A";
const MUTED = "6E7891";
const MUTED_D = "9AA3B8";
const ACCENT = "E2603C";
const TEAL = "1C7293";
const WHITE = "FFFFFF";
const CARD = "F3F4F7";
const LINE = "E2E5EB";

const JP = "Yu Gothic";

// ---- helpers -------------------------------------------------------------
const shadow = () => ({ type: "outer", color: "1A1F2C", blur: 14, offset: 3, angle: 90, opacity: 0.1 });

function lightSlide() {
  const s = pres.addSlide();
  s.background = { color: WHITE };
  return s;
}
function darkSlide() {
  const s = pres.addSlide();
  s.background = { color: INK };
  return s;
}

// numbered chapter badge + section label (the repeated motif)
function badge(s, num, label, opts = {}) {
  const dark = !!opts.dark;
  const y = opts.y == null ? 0.6 : opts.y;
  s.addShape(pres.ShapeType.ellipse, {
    x: M, y: y, w: 0.5, h: 0.5, fill: { color: ACCENT },
  });
  s.addText(num, {
    x: M, y: y, w: 0.5, h: 0.5, align: "center", valign: "middle", margin: 0,
    fontFace: JP, fontSize: 15, bold: true, color: WHITE,
  });
  s.addText(label, {
    x: M + 0.68, y: y, w: 8.0, h: 0.5, valign: "middle", margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: dark ? MUTED_D : MUTED, charSpacing: 1.5,
  });
}

function heading(s, text, opts = {}) {
  const dark = !!opts.dark;
  s.addText(text, {
    x: M, y: opts.y == null ? 1.28 : opts.y, w: opts.w == null ? W - M * 2 : opts.w, h: 0.95,
    valign: "middle", margin: 0,
    fontFace: JP, fontSize: opts.size == null ? 33 : opts.size, bold: true,
    color: dark ? WHITE : INK, lineSpacing: opts.size ? opts.size * 1.35 : 44,
  });
}

function card(s, x, y, w, h, opts = {}) {
  s.addShape(pres.ShapeType.roundRect, {
    x, y, w, h, rectRadius: 0.1,
    fill: { color: opts.fill || CARD },
    line: opts.line === false ? { color: opts.fill || CARD, width: 0 } : { color: opts.lineColor || LINE, width: 1 },
    shadow: opts.shadow ? shadow() : undefined,
  });
}

// terminal-style mock block (visual motif for "実行するAI")
function terminal(s, x, y, w, h, lines, opts = {}) {
  s.addShape(pres.ShapeType.roundRect, {
    x, y, w, h, rectRadius: 0.08,
    fill: { color: opts.fill || INK2 }, line: { color: opts.fill || INK2, width: 0 },
    shadow: shadow(),
  });
  ["E2603C", "D8B24A", "63A87B"].forEach((c, i) => {
    s.addShape(pres.ShapeType.ellipse, { x: x + 0.26 + i * 0.26, y: y + 0.26, w: 0.13, h: 0.13, fill: { color: c } });
  });
  s.addText(
    lines.map((l, i) => ({
      text: l.t,
      options: { color: l.c || "D7DBE6", bold: !!l.b, breakLine: i !== lines.length - 1 },
    })),
    {
      x: x + 0.26, y: y + 0.66, w: w - 0.52, h: h - 0.9, margin: 0, valign: "top",
      fontFace: JP, fontSize: opts.size == null ? 13 : opts.size, lineSpacing: opts.lh == null ? 25 : opts.lh,
    }
  );
}

// =========================================================================
// 1. Title
// =========================================================================
{
  const s = darkSlide();
  s.addText("YOUTUBE 要点まとめ", {
    x: M, y: 1.15, w: 7.2, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 2.5,
  });
  s.addText("Claude Code\n完全入門", {
    x: M, y: 1.7, w: 7.2, h: 2.3, margin: 0,
    fontFace: JP, fontSize: 52, bold: true, color: WHITE, lineSpacing: 64,
  });
  s.addText("誰でも使えるツール／実行革命／ChatGPTとの違い／5体のAIエージェント／\n願望の質＝アウトプットの質／Skills活用法／経営者こそ使うべき", {
    x: M, y: 4.15, w: 7.2, h: 1.0, margin: 0,
    fontFace: JP, fontSize: 14, color: MUTED_D, lineSpacing: 26,
  });
  s.addText("takuha ／ 社内共有用", {
    x: M, y: 6.35, w: 7.2, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 12, color: MUTED, charSpacing: 1,
  });

  terminal(s, 8.55, 1.7, 3.95, 3.6, [
    { t: "$ claude", c: "8C93A8" },
    { t: "", c: "8C93A8" },
    { t: "> 先週の投稿をまとめて", b: true, c: WHITE },
    { t: "  レポートにして", b: true, c: WHITE },
    { t: "", c: "8C93A8" },
    { t: "● ファイルを読んでいます", c: "9DC7B4" },
    { t: "● 集計しています", c: "9DC7B4" },
    { t: "● report.md を書きました", c: "9DC7B4" },
  ], { size: 13, lh: 26 });
  s.addText("聞くのではなく、終わらせてもらう", {
    x: 8.55, y: 5.45, w: 3.95, h: 0.35, margin: 0, align: "center",
    fontFace: JP, fontSize: 12, color: MUTED, italic: true,
  });

  s.addNotes("元動画は視聴できていないため、タイトルに並ぶ論点とClaude Codeの実際の仕様をもとに構成している。最終ページの注記を参照。");
}

// =========================================================================
// 2. 全体像
// =========================================================================
{
  const s = lightSlide();
  s.addText("OVERVIEW", {
    x: M, y: 0.62, w: 6, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 2.5,
  });
  heading(s, "動画の8つの論点を、6つの要点に整理した", { y: 1.05, size: 31 });

  const items = [
    ["01", "実行革命", "提案するAIから、手を動かすAIへ。ChatGPTとは役割が違う"],
    ["02", "誰でも使える", "打つのは日本語だけ。コードが読めなくても投げられる"],
    ["03", "5体のAIを並列で", "作業を分けて同時に持たせる。速い理由は待ち時間の重なり"],
    ["04", "願望の質＝出力の質", "出力がボヤけるのは、欲しいものがボヤけているから"],
    ["05", "Skills活用法", "前提と手順を預けておくと、二度と説明しなくてよくなる"],
    ["06", "経営者こそ使うべき", "任せると判断が人づてになる。手が空いていない人ほど効く"],
  ];
  const cw = 3.75, ch = 1.85, gx = 0.28, gy = 0.3, x0 = M, y0 = 2.5;
  items.forEach((it, i) => {
    const x = x0 + (i % 3) * (cw + gx);
    const y = y0 + Math.floor(i / 3) * (ch + gy);
    card(s, x, y, cw, ch, { fill: CARD });
    s.addShape(pres.ShapeType.ellipse, { x: x + 0.3, y: y + 0.3, w: 0.44, h: 0.44, fill: { color: ACCENT } });
    s.addText(it[0], {
      x: x + 0.3, y: y + 0.3, w: 0.44, h: 0.44, align: "center", valign: "middle", margin: 0,
      fontFace: JP, fontSize: 12, bold: true, color: WHITE,
    });
    s.addText(it[1], {
      x: x + 0.88, y: y + 0.3, w: cw - 1.18, h: 0.44, valign: "middle", margin: 0,
      fontFace: JP, fontSize: 16, bold: true, color: INK,
    });
    s.addText(it[2], {
      x: x + 0.3, y: y + 0.92, w: cw - 0.6, h: 0.75, margin: 0, valign: "top",
      fontFace: JP, fontSize: 12, color: SLATE, lineSpacing: 20,
    });
  });
  s.addNotes("6本立て。01と02が入口、03が実演、04と05が実務、06が経営視点。");
}

// =========================================================================
// 3. 実行革命
// =========================================================================
{
  const s = lightSlide();
  badge(s, "01", "実行革命");
  heading(s, "「提案するAI」から「実行するAI」へ");

  const cw = 5.75, cy = 2.55, chh = 3.2;
  card(s, M, cy, cw, chh, { fill: CARD });
  s.addText("これまで", {
    x: M + 0.42, y: cy + 0.35, w: cw - 0.84, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: MUTED, charSpacing: 1.5,
  });
  s.addText("答えを教えてもらう", {
    x: M + 0.42, y: cy + 0.75, w: cw - 0.84, h: 0.45, margin: 0,
    fontFace: JP, fontSize: 21, bold: true, color: SLATE,
  });
  s.addText([
    { text: "AIに聞く", options: { bullet: true, breakLine: true } },
    { text: "返ってきたものを自分でコピペする", options: { bullet: true, breakLine: true } },
    { text: "動かない → また聞く、をくり返す", options: { bullet: true, breakLine: true } },
    { text: "手を動かすのは、最後まで自分", options: { bullet: true } },
  ], {
    x: M + 0.42, y: cy + 1.4, w: cw - 0.84, h: 1.4, margin: 0, valign: "top",
    fontFace: JP, fontSize: 13.5, color: SLATE, paraSpaceAfter: 8,
  });

  const x2 = M + cw + 0.3;
  card(s, x2, cy, cw, chh, { fill: "FCEFE9", lineColor: "F0C9B8" });
  s.addText("これから", {
    x: x2 + 0.42, y: cy + 0.35, w: cw - 0.84, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 1.5,
  });
  s.addText("終わったものを受け取る", {
    x: x2 + 0.42, y: cy + 0.75, w: cw - 0.84, h: 0.45, margin: 0,
    fontFace: JP, fontSize: 21, bold: true, color: INK,
  });
  s.addText([
    { text: "日本語で指示を出す", options: { bullet: true, breakLine: true } },
    { text: "AIが自分でファイルを開いて書き換える", options: { bullet: true, breakLine: true } },
    { text: "コマンドを実行し、動くところまで確認する", options: { bullet: true, breakLine: true } },
    { text: "こちらは何も貼り付けていない", options: { bullet: true } },
  ], {
    x: x2 + 0.42, y: cy + 1.4, w: cw - 0.84, h: 1.4, margin: 0, valign: "top",
    fontFace: JP, fontSize: 13.5, color: INK2, paraSpaceAfter: 8,
  });

  s.addText("この差が「実行革命」。作業の主語がこちらから向こうへ移る", {
    x: M, y: 6.2, w: W - M * 2, h: 0.5, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 15, bold: true, color: ACCENT,
  });
  s.addNotes("ポイントは速さではなく、主語が移ること。コピペの往復が丸ごと消える。");
}

// =========================================================================
// 4. ChatGPTとの違い
// =========================================================================
{
  const s = lightSlide();
  badge(s, "01", "実行革命 ／ ChatGPTとの違い");
  heading(s, "敵ではない。相談する相手と、作業する相手は別");

  const rows = [
    [{ text: "", options: { fill: { color: WHITE } } },
     { text: "チャット型のAI", options: { fill: { color: "E8F1F5" }, color: TEAL, bold: true, align: "center" } },
     { text: "Claude Code", options: { fill: { color: "FCEFE9" }, color: ACCENT, bold: true, align: "center" } }],
    [{ text: "立ち位置", options: { bold: true, color: INK } },
     { text: "相談する相手", options: { color: SLATE } },
     { text: "作業する相手", options: { color: INK, bold: true } }],
    [{ text: "出てくるもの", options: { bold: true, color: INK } },
     { text: "文章・案・書かれたコード", options: { color: SLATE } },
     { text: "書き換わったファイル・実行結果", options: { color: INK, bold: true } }],
    [{ text: "こちらの作業", options: { bold: true, color: INK } },
     { text: "読んで、選んで、自分で反映する", options: { color: SLATE } },
     { text: "指示と、出てきたものの確認", options: { color: INK, bold: true } }],
    [{ text: "向いている場面", options: { bold: true, color: INK } },
     { text: "考えを整理する・発散させる", options: { color: SLATE } },
     { text: "決まったことを終わらせる", options: { color: INK, bold: true } }],
  ];
  s.addTable(rows, {
    x: M, y: 2.5, w: W - M * 2, colW: [2.6, 4.6, 4.6],
    rowH: [0.5, 0.62, 0.62, 0.62, 0.62],
    fontFace: JP, fontSize: 13.5, valign: "middle",
    border: { type: "solid", pt: 1, color: LINE },
    margin: [6, 14, 6, 14],
  });
  s.addText("「どちらが優れているか」ではなく、渡すものが違う。考えを固めるのは前者、終わらせるのは後者。", {
    x: M, y: 6.25, w: W - M * 2, h: 0.5, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 13, color: MUTED,
  });
  s.addNotes("比較を勝ち負けで語らない。役割分担として話すほうが納得されやすい。");
}

// =========================================================================
// 5. 誰でも使える
// =========================================================================
{
  const s = lightSlide();
  badge(s, "02", "誰でも使えるツール");
  heading(s, "コードが書けない人ほど、得をする", { w: 7.6 });

  const rows = [
    ["打つのは日本語だけ", "黒い画面で動くが、入力するのは日本語。コマンドを覚える必要はない"],
    ["コードが読めなくていい", "中身の判断は任せられる。確認するのは「やりたいことになっているか」"],
    ["扱うのはコードだけじゃない", "調べてまとめる、ファイルを整理する、決まった手順を毎回同じようにやる"],
  ];
  rows.forEach((r, i) => {
    const y = 2.55 + i * 1.28;
    s.addShape(pres.ShapeType.ellipse, { x: M, y: y + 0.06, w: 0.46, h: 0.46, fill: { color: ACCENT } });
    s.addText("✓", {
      x: M, y: y + 0.06, w: 0.46, h: 0.46, align: "center", valign: "middle", margin: 0,
      fontFace: "Arial", fontSize: 15, bold: true, color: WHITE,
    });
    s.addText(r[0], {
      x: M + 0.68, y: y, w: 6.6, h: 0.42, margin: 0, valign: "middle",
      fontFace: JP, fontSize: 18, bold: true, color: INK,
    });
    s.addText(r[1], {
      x: M + 0.68, y: y + 0.46, w: 6.6, h: 0.7, margin: 0, valign: "top",
      fontFace: JP, fontSize: 13, color: SLATE, lineSpacing: 21,
    });
  });

  terminal(s, 8.35, 2.4, 4.2, 2.95, [
    { t: "> 請求書のPDFを月ごとに", b: true, c: WHITE },
    { t: "  フォルダ分けして", b: true, c: WHITE },
    { t: "", c: "8C93A8" },
    { t: "● 42件を確認しました", c: "9DC7B4" },
    { t: "● 12フォルダに整理しました", c: "9DC7B4" },
  ], { size: 13, lh: 26 });
  s.addText("コードが1行も出てこない使い方", {
    x: 8.35, y: 5.5, w: 4.2, h: 0.35, margin: 0, align: "center",
    fontFace: JP, fontSize: 12, color: MUTED, italic: true,
  });
  s.addText("完璧に理解してから触ろうとしないこと。1個投げてみるのが早い", {
    x: M, y: 6.5, w: 7.6, h: 0.45, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 14, bold: true, color: ACCENT,
  });
  s.addNotes("「今までは人に頼むか諦めるかの二択だった。そこに三つ目が増える」が一番刺さる言い方。");
}

// =========================================================================
// 6. 5体のAIエージェント
// =========================================================================
{
  const s = darkSlide();
  badge(s, "03", "5体のAIエージェントで実演", { dark: true });
  heading(s, "作業を分けて、同時に持たせる", { dark: true });

  const lx = M, lw = 7.5;
  // 逐次
  s.addText("1体で順番に", {
    x: lx, y: 2.5, w: lw, h: 0.32, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: MUTED_D, charSpacing: 1.5,
  });
  for (let i = 0; i < 5; i++) {
    s.addShape(pres.ShapeType.roundRect, {
      x: lx + i * 1.5, y: 2.92, w: 1.34, h: 0.5, rectRadius: 0.06,
      fill: { color: "2C3346" }, line: { color: "3B4459", width: 1 },
    });
    s.addText(String(i + 1), {
      x: lx + i * 1.5, y: 2.92, w: 1.34, h: 0.5, align: "center", valign: "middle", margin: 0,
      fontFace: JP, fontSize: 12, color: MUTED_D,
    });
  }
  s.addText("待ち時間 × 5", {
    x: lx, y: 3.5, w: lw, h: 0.32, margin: 0,
    fontFace: JP, fontSize: 12, color: MUTED, italic: true,
  });

  // 並列
  s.addText("5体で同時に", {
    x: lx, y: 4.15, w: lw, h: 0.32, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 1.5,
  });
  for (let i = 0; i < 5; i++) {
    s.addShape(pres.ShapeType.roundRect, {
      x: lx, y: 4.57 + i * 0.42, w: 1.34, h: 0.32, rectRadius: 0.05,
      fill: { color: ACCENT }, line: { color: ACCENT, width: 0 },
    });
    s.addText(String(i + 1), {
      x: lx, y: 4.57 + i * 0.42, w: 1.34, h: 0.32, align: "center", valign: "middle", margin: 0,
      fontFace: JP, fontSize: 11, bold: true, color: WHITE,
    });
  }
  s.addText("待ち時間 × 1", {
    x: lx + 1.55, y: 5.35, w: 2.6, h: 0.35, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 14, bold: true, color: WHITE,
  });

  s.addShape(pres.ShapeType.roundRect, {
    x: 8.6, y: 2.5, w: 3.95, h: 4.15, rectRadius: 0.1,
    fill: { color: INK2 }, line: { color: "2E3648", width: 1 },
  });
  s.addText("速い理由", {
    x: 8.95, y: 2.85, w: 3.25, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 1.5,
  });
  s.addText("「たくさん動くから」ではなく、待ち時間が重なるから。1個ずつなら5回待つところが、1回分で終わる。", {
    x: 8.95, y: 3.25, w: 3.25, h: 1.2, margin: 0, valign: "top",
    fontFace: JP, fontSize: 13, color: "D7DBE6", lineSpacing: 22,
  });
  s.addText("向き・不向き", {
    x: 8.95, y: 4.6, w: 3.25, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 1.5,
  });
  s.addText([
    { text: "向く：互いに関係のない作業", options: { bullet: true, breakLine: true } },
    { text: "向かない：前の結果を見て次を決める作業", options: { bullet: true, breakLine: true } },
    { text: "最初にやるなら「調べる」を分ける", options: { bullet: true } },
  ], {
    x: 8.95, y: 5.0, w: 3.25, h: 1.4, margin: 0, valign: "top",
    fontFace: JP, fontSize: 12, color: "D7DBE6", paraSpaceAfter: 7,
  });
  s.addNotes("何でも並列にすればいいわけではない、と必ず添える。ここを言わないと薄い話になる。");
}

// =========================================================================
// 7. 願望の質（ステートメント）
// =========================================================================
{
  const s = darkSlide();
  badge(s, "04", "願望の質＝アウトプットの質", { dark: true });

  s.addText("願望の質が、\nそのまま出力の質になる", {
    x: M, y: 1.8, w: 7.3, h: 2.2, margin: 0,
    fontFace: JP, fontSize: 40, bold: true, color: WHITE, lineSpacing: 54,
  });
  s.addText("AIの出してくるものが微妙なとき、原因はAIではないことが多い。\n自分が何を欲しいか分かっていない分だけ、出力もボヤける。", {
    x: M, y: 4.2, w: 7.3, h: 1.0, margin: 0,
    fontFace: JP, fontSize: 15, color: MUTED_D, lineSpacing: 28,
  });

  card(s, 8.35, 1.85, 4.2, 1.75, { fill: INK2, lineColor: "2E3648" });
  s.addText("雑な指示", {
    x: 8.7, y: 2.1, w: 3.5, h: 0.3, margin: 0,
    fontFace: JP, fontSize: 12, bold: true, color: MUTED, charSpacing: 1.5,
  });
  s.addText("「いい感じにして」", {
    x: 8.7, y: 2.45, w: 3.5, h: 0.42, margin: 0,
    fontFace: JP, fontSize: 17, bold: true, color: "D7DBE6",
  });
  s.addText("→ いい感じの何かが返ってくる", {
    x: 8.7, y: 2.92, w: 3.5, h: 0.42, margin: 0,
    fontFace: JP, fontSize: 12.5, color: MUTED,
  });

  card(s, 8.35, 3.85, 4.2, 2.4, { fill: "FCEFE9", line: false });
  s.addText("3行足した指示", {
    x: 8.7, y: 4.1, w: 3.5, h: 0.3, margin: 0,
    fontFace: JP, fontSize: 12, bold: true, color: ACCENT, charSpacing: 1.5,
  });
  s.addText("「新規の顧客向けに、\n問い合わせを減らす目的で、\nFAQ 10問が出たら完了」", {
    x: 8.7, y: 4.45, w: 3.5, h: 1.15, margin: 0,
    fontFace: JP, fontSize: 14, bold: true, color: INK, lineSpacing: 24,
  });
  s.addText("→ 返ってくるものが別物になる", {
    x: 8.7, y: 5.65, w: 3.5, h: 0.42, margin: 0,
    fontFace: JP, fontSize: 12.5, color: SLATE,
  });
  s.addNotes("ここが動画で一番引用されやすい論点。実例は自分の仕事から出すと強い。");
}

// =========================================================================
// 8. 言語化の3行フレーム
// =========================================================================
{
  const s = lightSlide();
  badge(s, "04", "言語化が全て");
  heading(s, "指示に足すのは、この3行だけでいい");

  const items = [
    ["誰のためか", "その作業の受け取り手を決める", "新規の顧客向けに"],
    ["何のためにやるのか", "達成したい状態を1つに絞る", "問い合わせを減らす目的で"],
    ["どうなったら終わりか", "止める条件を数か形で置く", "FAQが10問できたら完了"],
  ];
  const cw = 3.75, gx = 0.28;
  items.forEach((it, i) => {
    const x = M + i * (cw + gx);
    card(s, x, 2.5, cw, 3.1, { fill: CARD });
    s.addShape(pres.ShapeType.ellipse, { x: x + 0.35, y: 2.85, w: 0.5, h: 0.5, fill: { color: ACCENT } });
    s.addText(String(i + 1), {
      x: x + 0.35, y: 2.85, w: 0.5, h: 0.5, align: "center", valign: "middle", margin: 0,
      fontFace: JP, fontSize: 14, bold: true, color: WHITE,
    });
    s.addText(it[0], {
      x: x + 0.35, y: 3.55, w: cw - 0.7, h: 0.45, margin: 0,
      fontFace: JP, fontSize: 17, bold: true, color: INK,
    });
    s.addText(it[1], {
      x: x + 0.35, y: 4.05, w: cw - 0.7, h: 0.6, margin: 0, valign: "top",
      fontFace: JP, fontSize: 12.5, color: SLATE, lineSpacing: 21,
    });
    s.addText("例）" + it[2], {
      x: x + 0.35, y: 4.75, w: cw - 0.7, h: 0.62, margin: 0, valign: "top",
      fontFace: JP, fontSize: 12.5, color: ACCENT, italic: true, lineSpacing: 21,
    });
  });

  s.addText("これはAIを使う技術ではなく、欲しいものを言葉にする技術。伸ばすとAI以外の仕事も速くなる。", {
    x: M, y: 6.0, w: W - M * 2, h: 0.5, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 15, bold: true, color: ACCENT,
  });
  s.addNotes("3行フレームは持ち帰りやすいので、資料の中で一番使われるページになりやすい。");
}

// =========================================================================
// 9. Skills
// =========================================================================
{
  const s = lightSlide();
  badge(s, "05", "Skills活用法");
  heading(s, "一度書けば、二度と説明しなくていい");

  const cw = 5.75;
  card(s, M, 2.5, cw, 2.55, { fill: CARD });
  s.addText("CLAUDE.md", {
    x: M + 0.42, y: 2.8, w: cw - 0.84, h: 0.42, margin: 0,
    fontFace: JP, fontSize: 19, bold: true, color: INK,
  });
  s.addText("前提を置いておく", {
    x: M + 0.42, y: 3.24, w: cw - 0.84, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: MUTED,
  });
  s.addText("プロジェクトのルール、うちのやり方、触ってほしくない場所。1回書けば毎回読まれるので、説明のやり直しが消える。", {
    x: M + 0.42, y: 3.68, w: cw - 0.84, h: 1.1, margin: 0, valign: "top",
    fontFace: JP, fontSize: 13, color: SLATE, lineSpacing: 22,
  });

  const x2 = M + cw + 0.3;
  card(s, x2, 2.5, cw, 2.55, { fill: "FCEFE9", lineColor: "F0C9B8" });
  s.addText("Skills（SKILL.md）", {
    x: x2 + 0.42, y: 2.8, w: cw - 0.84, h: 0.42, margin: 0,
    fontFace: JP, fontSize: 19, bold: true, color: INK,
  });
  s.addText("手順そのものを預ける", {
    x: x2 + 0.42, y: 3.24, w: cw - 0.84, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT,
  });
  s.addText("「この作業はこう進める」を書いておくと、その場面が来たときに自分で読み込み、その通りに動く。", {
    x: x2 + 0.42, y: 3.68, w: cw - 0.84, h: 1.1, margin: 0, valign: "top",
    fontFace: JP, fontSize: 13, color: INK2, lineSpacing: 22,
  });

  card(s, M, 5.3, W - M * 2, 1.4, { fill: INK, line: false });
  s.addText("効くのは速さより、頭の中にしかなかった「うちのやり方」が外に出ること。", {
    x: M + 0.5, y: 5.55, w: 8.0, h: 0.42, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 15, bold: true, color: WHITE,
  });
  s.addText("人に引き継ぐときにも、そのまま渡せる。", {
    x: M + 0.5, y: 6.0, w: 8.0, h: 0.4, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 13, color: MUTED_D,
  });
  s.addText("同じ説明を\n2回したら、書く", {
    x: 9.1, y: 5.5, w: 3.35, h: 1.0, margin: 0, align: "right", valign: "middle",
    fontFace: JP, fontSize: 16, bold: true, color: ACCENT, lineSpacing: 26,
  });
  s.addNotes("判断基準を1つだけ渡すのが大事。「2回説明したら書く」以外は覚えてもらわなくていい。");
}

// =========================================================================
// 10. 経営者こそ
// =========================================================================
{
  const s = lightSlide();
  badge(s, "06", "経営者こそ使うべき");
  heading(s, "「詳しい人に任せる」が、いちばん損をする");

  const items = [
    ["判断が人づてになる", "できる？と聞いて、返事を待って、また聞く。使えるかどうかの判断が自分の手から離れる"],
    ["できることの地図が持てない", "地図がないと投資判断も採用もふわっとする。触れば報告を聞いた瞬間に妥当さが分かる"],
    ["手が空いていない人ほど効く", "細かい作業を自分でやる時間がない。そこに入ると効き方が大きい"],
    ["諦めていた側が動き出す", "やらずに見送っていた仕事が実行の対象になる。増えるのは速度ではなく手数"],
  ];
  const cw = 5.75, chh = 1.72, gx = 0.3, gy = 0.28;
  items.forEach((it, i) => {
    const x = M + (i % 2) * (cw + gx);
    const y = 2.5 + Math.floor(i / 2) * (chh + gy);
    card(s, x, y, cw, chh, { fill: i < 2 ? CARD : "FCEFE9", lineColor: i < 2 ? LINE : "F0C9B8" });
    s.addText(it[0], {
      x: x + 0.42, y: y + 0.28, w: cw - 0.84, h: 0.42, margin: 0, valign: "middle",
      fontFace: JP, fontSize: 17, bold: true, color: INK,
    });
    s.addText(it[1], {
      x: x + 0.42, y: y + 0.75, w: cw - 0.84, h: 0.8, margin: 0, valign: "top",
      fontFace: JP, fontSize: 12.5, color: SLATE, lineSpacing: 21,
    });
  });
  s.addText("全部を自分でやる必要はない。1個だけ最後まで自分の手で通すと、判断の精度が変わる。", {
    x: M, y: 6.45, w: W - M * 2, h: 0.5, margin: 0, valign: "middle",
    fontFace: JP, fontSize: 15, bold: true, color: ACCENT,
  });
  s.addNotes("経営者向けの結論は「全部やれ」ではなく「1個だけ通せ」。ここを外すと実行されない。");
}

// =========================================================================
// 11. 明日からの一歩
// =========================================================================
{
  const s = lightSlide();
  s.addText("NEXT ACTION", {
    x: M, y: 0.62, w: 6, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 13, bold: true, color: ACCENT, charSpacing: 2.5,
  });
  heading(s, "明日からやること、3つ", { y: 1.05 });

  const steps = [
    ["STEP 1", "1個だけ、最後まで通す", "小さくていい。指示から、出てきたものの確認までを自分の手で1周する"],
    ["STEP 2", "同じ説明を2回したら書く", "前提はCLAUDE.mdへ、手順はSkillsへ。書いた分だけ次から説明が消える"],
    ["STEP 3", "関係ない作業から並列にする", "まずは「調べる」を分けて同時に走らせ、最後に自分でまとめる"],
  ];
  steps.forEach((st, i) => {
    const y = 2.4 + i * 1.45;
    s.addShape(pres.ShapeType.roundRect, {
      x: M, y: y, w: 1.5, h: 1.15, rectRadius: 0.08,
      fill: { color: i === 0 ? ACCENT : INK }, line: { color: i === 0 ? ACCENT : INK, width: 0 },
    });
    s.addText(st[0], {
      x: M, y: y, w: 1.5, h: 1.15, align: "center", valign: "middle", margin: 0,
      fontFace: JP, fontSize: 13, bold: true, color: WHITE, charSpacing: 1,
    });
    s.addText(st[1], {
      x: M + 1.8, y: y + 0.1, w: 9.9, h: 0.45, margin: 0, valign: "middle",
      fontFace: JP, fontSize: 19, bold: true, color: INK,
    });
    s.addText(st[2], {
      x: M + 1.8, y: y + 0.6, w: 9.9, h: 0.5, margin: 0, valign: "top",
      fontFace: JP, fontSize: 13, color: SLATE, lineSpacing: 21,
    });
  });
  s.addNotes("3つとも「今日中に着手できる大きさ」に落としてある。");
}

// =========================================================================
// 12. 出典・注記
// =========================================================================
{
  const s = darkSlide();
  s.addText("出典・注記", {
    x: M, y: 1.1, w: 8, h: 0.6, margin: 0,
    fontFace: JP, fontSize: 30, bold: true, color: WHITE,
  });

  s.addText("元動画", {
    x: M, y: 2.15, w: 11.8, h: 0.3, margin: 0,
    fontFace: JP, fontSize: 12, bold: true, color: ACCENT, charSpacing: 2,
  });
  s.addText("【Claude Code完全入門】誰でも使えるツール／実行革命／ChatGPTとの違い／5体のAIエージェントで実演／\n願望の質＝アウトプットの質／Skills活用法／経営者こそ使うべき／言語化が全て（2026年3月公開）", {
    x: M, y: 2.5, w: 11.8, h: 0.8, margin: 0,
    fontFace: JP, fontSize: 13, color: "D7DBE6", lineSpacing: 24,
  });
  s.addText("https://youtu.be/LRSSjGwsuv0", {
    x: M, y: 3.3, w: 11.8, h: 0.35, margin: 0,
    fontFace: "Arial", fontSize: 12, color: MUTED_D,
  });

  s.addText("本資料の作り方", {
    x: M, y: 4.0, w: 11.8, h: 0.3, margin: 0,
    fontFace: JP, fontSize: 12, bold: true, color: ACCENT, charSpacing: 2,
  });
  s.addText([
    { text: "本編映像・字幕は取得できていない。タイトルに並ぶ8つの論点と、Claude Code の実際の仕様をもとに構成している", options: { bullet: true, breakLine: true } },
    { text: "元動画固有のエピソードや数字は含まれていない。引用する場合は本編を確認のうえ追記すること", options: { bullet: true, breakLine: true } },
    { text: "料金・プラン・モデル世代は変わるため、意図的に触れていない。必要なら公式ドキュメントを参照", options: { bullet: true } },
  ], {
    x: M, y: 4.4, w: 11.8, h: 1.5, margin: 0, valign: "top",
    fontFace: JP, fontSize: 13, color: "D7DBE6", paraSpaceAfter: 10, lineSpacing: 22,
  });

  s.addText("takuha", {
    x: M, y: 6.45, w: 11.8, h: 0.35, margin: 0,
    fontFace: JP, fontSize: 12, color: MUTED, charSpacing: 1,
  });
  s.addNotes("引用前提で配る場合は、この注記ページを外さないこと。");
}

const out = process.argv[2] || "claude-code-summary.pptx";
pres.writeFile({ fileName: out }).then(() => console.log("wrote", out));
