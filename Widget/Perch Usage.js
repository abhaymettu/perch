// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-brown; icon-glyph: feather-alt;
//
// Perch Usage — a medium widget with the three Claude limit windows, watched
// over by the Perch owl. Data comes from perch-usage.json, which the Perch
// menu bar app on the Mac drops into Scriptable's iCloud folder on every poll.

const GROUND_TOP = new Color("#17171c");
const GROUND = new Color("#131317");
const INK = new Color("#ececf1");
const INK_MUTED = new Color("#9a9aa7");
const INK_FAINT = new Color("#646470");
const ACCENT = new Color("#d97757");
const WARN = new Color("#e0a458");
const ALERT = new Color("#f0616f");
const TRACK = new Color("#ffffff", 0.09);
const FACE = new Color("#2b2b32");
const EDGE = new Color("#77777f");

// ---------------------------------------------------------------- data

async function readUsage() {
  const fm = FileManager.iCloud();
  const path = fm.joinPath(fm.documentsDirectory(), "perch-usage.json");
  if (!fm.fileExists(path)) return null;
  await fm.downloadFileFromiCloud(path);
  try {
    return JSON.parse(fm.readString(path));
  } catch (e) {
    return null;
  }
}

function label(limit) {
  if (limit.kind === "session") return "SESSION";
  if (limit.kind === "weekly_all") return "WEEK · ALL";
  return "WEEK · " + (limit.model || "MODEL").toUpperCase();
}

function countdown(limit) {
  if (!limit.resetsAt) return "";
  const minutes = Math.floor((limit.resetsAt * 1000 - Date.now()) / 60000);
  if (minutes < 1) return "resets now";
  if (minutes < 60) return "resets " + minutes + "m";
  if (minutes < 1440) return "resets " + Math.floor(minutes / 60) + "h";
  return "resets " + Math.floor(minutes / 1440) + "d";
}

function tint(limit) {
  if (limit.severity === "critical") return ALERT;
  if (limit.severity === "warning") return WARN;
  return ACCENT;
}

// Session first, then the account week, then the hottest per-model week.
function pickThree(limits) {
  const session = limits.filter(l => l.kind === "session");
  const week = limits.filter(l => l.kind === "weekly_all");
  const scoped = limits
    .filter(l => l.kind === "weekly_scoped")
    .sort((a, b) => b.percent - a.percent);
  return [...session, ...week, ...scoped].slice(0, 3);
}

// ---------------------------------------------------------------- the owl

// The Perch owl, drawn from the same ratios as the app (OwlGeometry.swift):
// a squat squircle head, two sliced glaring eyes riding high, a small beak.
// eyes: openness 0..1.25. glance: -1, 0, or 1, a sideways look.
function drawOwl(size, openness, glance, alarmed) {
  const SS = 4; // supersample; the widget scales it back down
  const s = (size / 24) * SS;
  const ctx = new DrawContext();
  ctx.size = new Size(size * SS, size * SS);
  ctx.opaque = false;
  ctx.respectScreenScale = false;
  const mid = (size * SS) / 2;

  const faceW = 23 * s, faceH = 15.4 * s;
  const face = new Rect(mid - faceW / 2, mid - faceH / 2, faceW, faceH);
  const radius = faceH * 0.42;

  const head = new Path();
  head.addRoundedRect(face, radius, radius);
  ctx.addPath(head);
  ctx.setFillColor(FACE);
  ctx.fillPath();
  ctx.addPath(head);
  ctx.setStrokeColor(alarmed ? ALERT : EDGE);
  ctx.setLineWidth(Math.max(1, s));
  ctx.strokePath();

  const eyeColor = alarmed ? ALERT : INK;
  const eyeCenterY = mid - 0.8 * s;
  const eyeW = 5.8 * s;
  const eyeH = Math.max(5.8 * s * openness, 0.7 * s);
  const shift = glance * 1.1 * s;

  for (const side of [-1, 1]) {
    const x = mid + side * 3.7 * s + shift - eyeW / 2;
    const eye = new Rect(x, eyeCenterY - eyeH / 2, eyeW, eyeH);

    const ball = new Path();
    ball.addEllipse(eye);
    ctx.addPath(ball);
    ctx.setFillColor(eyeColor);
    ctx.fillPath();

    // The brow slice that makes it glare: shallow at the temple, deep by the
    // beak, painted back in face colour over the top of the eye.
    const outerY = eye.minY + 0.02 * eyeH;
    const innerY = eye.minY + 0.52 * eyeH;
    const leftY = side < 0 ? outerY : innerY;
    const rightY = side < 0 ? innerY : outerY;
    const cut = new Path();
    cut.move(new Point(eye.minX, leftY));
    cut.addLine(new Point(eye.maxX, rightY));
    cut.addLine(new Point(eye.maxX, eye.minY));
    cut.addLine(new Point(eye.minX, eye.minY));
    cut.closeSubpath();
    ctx.addPath(cut);
    ctx.setFillColor(FACE);
    ctx.fillPath();
  }

  const beakTop = eyeCenterY + 0.6 * s;
  const beak = new Path();
  beak.move(new Point(mid - 1.9 * s, beakTop));
  beak.addLine(new Point(mid + 1.9 * s, beakTop));
  beak.addLine(new Point(mid, beakTop + 5.4 * s));
  beak.closeSubpath();
  ctx.addPath(beak);
  ctx.setFillColor(alarmed ? ALERT : EDGE);
  ctx.fillPath();

  return ctx.getImage();
}

// ---------------------------------------------------------------- whimsy

function mood(limits) {
  const hottest = Math.max(0, ...limits.map(l => l.percent));
  if (limits.some(l => l.severity === "critical")) return "alarmed";
  if (hottest >= 75) return "watchful";
  if (hottest < 10) return "dozing";
  return "calm";
}

const OPENNESS = { alarmed: 1.25, watchful: 1.25, dozing: 0.35, calm: 1.0 };

const QUIPS = {
  dozing: ["all quiet on the perch", "barely a flutter", "the owl naps, the quota rests"],
  calm: ["keeping watch", "plenty of runway", "the owl sees everything"],
  watchful: ["burning through it", "the owl is side-eyeing you", "pace yourself"],
  alarmed: ["feathers ruffled, limit close", "the owl says cool it", "nearly out of perch"],
};

// ---------------------------------------------------------------- widget

function meter(width, percent, fill) {
  const SS = 4;
  const h = 3 * SS;
  const ctx = new DrawContext();
  ctx.size = new Size(width * SS, h);
  ctx.opaque = false;
  ctx.respectScreenScale = false;

  const track = new Path();
  track.addRoundedRect(new Rect(0, 0, width * SS, h), h / 2, h / 2);
  ctx.addPath(track);
  ctx.setFillColor(TRACK);
  ctx.fillPath();

  // A barely used window still shows a sliver, so it never reads as no data.
  const fillW = Math.max(h, (width * SS * percent) / 100);
  const bar = new Path();
  bar.addRoundedRect(new Rect(0, 0, fillW, h), h / 2, h / 2);
  ctx.addPath(bar);
  ctx.setFillColor(fill);
  ctx.fillPath();

  return ctx.getImage();
}

function column(stack, limit) {
  const col = stack.addStack();
  col.layoutVertically();

  const name = col.addText(label(limit));
  name.font = Font.semiboldSystemFont(8);
  name.textColor = INK_FAINT;
  name.lineLimit = 1;

  col.addSpacer(4);
  const value = col.addText(limit.percent + "%");
  value.font = Font.semiboldRoundedSystemFont(23);
  value.textColor = limit.severity === "normal" ? INK : tint(limit);
  value.lineLimit = 1;

  col.addSpacer(5);
  const bar = col.addImage(meter(84, limit.percent, tint(limit)));
  bar.imageSize = new Size(84, 3);

  col.addSpacer(4);
  const foot = col.addText(countdown(limit));
  foot.font = Font.regularMonospacedSystemFont(8);
  foot.textColor = INK_FAINT;
  foot.lineLimit = 1;
}

function build(data) {
  const w = new ListWidget();
  const gradient = new LinearGradient();
  gradient.colors = [GROUND_TOP, GROUND];
  gradient.locations = [0, 1];
  w.backgroundGradient = gradient;
  w.setPadding(13, 14, 12, 14);
  w.refreshAfterDate = new Date(Date.now() + 10 * 60 * 1000);

  if (!data || !data.limits || data.limits.length === 0) {
    w.addSpacer();
    const owl = w.addImage(drawOwl(30, 0.35, 0, false));
    owl.imageSize = new Size(30, 30);
    owl.centerAlignImage();
    w.addSpacer(8);
    const note = w.addText("waiting for the mac to publish perch-usage.json");
    note.font = Font.systemFont(10);
    note.textColor = INK_MUTED;
    note.centerAlignText();
    w.addSpacer();
    return w;
  }

  const limits = pickThree(data.limits);
  const state = mood(limits);

  // The garnish: a calm owl occasionally blinks or glances sideways, so the
  // widget is not the same picture every time you look at it.
  let openness = OPENNESS[state];
  let glance = 0;
  if (state === "calm" || state === "dozing") {
    const roll = Math.random();
    if (roll < 0.15) openness = 0;
    else if (roll < 0.3) glance = Math.random() < 0.5 ? -1 : 1;
  }

  // Header: the owl beside the wordmark, exactly the menu bar pairing.
  const header = w.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();
  const owl = header.addImage(drawOwl(21, openness, glance, state === "alarmed"));
  owl.imageSize = new Size(21, 21);
  header.addSpacer(7);
  const wordmark = header.addText("Perch");
  wordmark.font = Font.semiboldRoundedSystemFont(13);
  wordmark.textColor = INK;
  header.addSpacer();

  // "as of 6:10 PM", going amber once the mac has not published in a while.
  const df = new DateFormatter();
  df.useShortTimeStyle();
  const age = Math.floor((Date.now() / 1000 - data.fetchedAt) / 60);
  const asOf = header.addText("as of " + df.string(new Date(data.fetchedAt * 1000)));
  asOf.font = Font.regularMonospacedSystemFont(8);
  asOf.textColor = age >= 30 ? WARN : INK_FAINT;

  w.addSpacer();

  const row = w.addStack();
  row.layoutHorizontally();
  row.topAlignContent();
  limits.forEach((limit, i) => {
    if (i > 0) row.addSpacer();
    column(row, limit);
  });

  w.addSpacer();

  const quips = QUIPS[state];
  const quip = w.addText(quips[Math.floor(Math.random() * quips.length)]);
  quip.font = Font.systemFont(9);
  quip.textColor = INK_FAINT;
  quip.lineLimit = 1;

  return w;
}

const widget = build(await readUsage());
if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();
