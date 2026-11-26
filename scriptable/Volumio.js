// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-green; icon-glyph: music;

// Volumio widget for Scriptable (iOS / iPadOS).
//
// Shows what a Volumio player is playing, with play/pause, previous, next,
// mute, volume -/+ and a tappable 10-step volume bar. Best as a large
// (full-width) widget; medium and small work too.
//
// Setup:
//   1. Paste this whole file into a new script in Scriptable and name it "Volumio".
//   2. Set DEFAULT_HOST below to your player's IP (e.g. "192.168.1.40").
//   3. Add a Scriptable widget (large) to the home screen, long-press it,
//      choose Edit Widget, pick this script, and set "When Interacting" to
//      "Run Script". Optionally put the player's IP in "Parameter" to
//      override DEFAULT_HOST for that widget.
//
// Tapping a control in the widget opens Scriptable for a moment, sends the
// command, and shows a small remote with the new state. Swipe home when done.
// iOS decides how often the widget itself refreshes (usually every few minutes).

// ---------- Settings ----------

const DEFAULT_HOST = "volumio.local";   // IP or hostname, port 3000 is added if missing
const VOLUME_STEP = 5;                  // used by the - and + buttons
const VOLUME_PRESETS = [10, 20, 30, 40, 50, 60, 70, 80];  // buttons in the in-app remote
const SHOW_REMOTE_AFTER_TAP = true;     // false: just send the command and stop
const REFRESH_MINUTES = 1;              // a hint only; iOS usually waits longer
const REQUEST_TIMEOUT = 5;              // seconds

const ACCENT = new Color("#54c688");    // Volumio green
const TEXT = Color.white();
const TEXT_DIM = new Color("#ffffff", 0.65);
const TEXT_FAINT = new Color("#ffffff", 0.4);
const BAR_OFF = new Color("#ffffff", 0.18);

// ---------- Volumio API ----------

function normalizeHost(raw) {
  let text = String(raw || "").trim();
  text = text.replace(/^https?:\/\//i, "").replace(/\/.*$/, "");
  if (!text) return null;
  return /:\d+$/.test(text) ? text : `${text}:3000`;
}

async function apiJSON(host, path) {
  const req = new Request(`http://${host}${path}`);
  req.timeoutInterval = REQUEST_TIMEOUT;
  return await req.loadJSON();
}

async function getState(host) {
  const s = await apiJSON(host, "/api/v1/getState");
  if (!s || typeof s !== "object") throw new Error("Unexpected reply from Volumio");
  return s;
}

async function getPlayerName(host) {
  try {
    const info = await apiJSON(host, "/api/v1/getSystemInfo");
    return info && info.name ? String(info.name) : null;
  } catch (e) {
    return null;
  }
}

async function sendCommand(host, cmd, volume) {
  let path = `/api/v1/commands/?cmd=${encodeURIComponent(cmd)}`;
  if (volume !== undefined) path += `&volume=${encodeURIComponent(volume)}`;
  const req = new Request(`http://${host}${path}`);
  req.timeoutInterval = REQUEST_TIMEOUT;
  await req.loadString();
}

// Volumio sometimes sends numbers as strings, or null.
function num(value, fallback) {
  const n = Number(value);
  return value === null || value === undefined || value === "" || isNaN(n) ? fallback : n;
}

function isTrue(value) {
  return value === true || value === "true" || value === 1;
}

function clampVolume(v) {
  return Math.max(0, Math.min(100, Math.round(v)));
}

function albumArtURL(host, art) {
  if (!art) return null;
  if (/^https?:\/\//i.test(art)) return art;
  return `http://${host}${art.startsWith("/") ? "" : "/"}${art}`;
}

async function loadAlbumArt(host, state) {
  const url = albumArtURL(host, state.albumart);
  if (!url) return null;
  try {
    const req = new Request(url);
    req.timeoutInterval = REQUEST_TIMEOUT;
    return await req.loadImage();
  } catch (e) {
    return null;
  }
}

function sleep(ms) {
  return new Promise((resolve) => Timer.schedule(ms, false, resolve));
}

// Runs one control action. `state` is a fresh getState result, used for
// relative volume changes and mute toggling.
async function runAction(host, action, value, state) {
  const volume = num(state && state.volume, 0);
  switch (action) {
    case "toggle":
    case "play":
    case "pause":
    case "stop":
    case "next":
    case "prev":
      await sendCommand(host, action);
      break;
    case "volup":
      await sendCommand(host, "volume", clampVolume(volume + VOLUME_STEP));
      break;
    case "voldown":
      await sendCommand(host, "volume", clampVolume(volume - VOLUME_STEP));
      break;
    case "vol":
      await sendCommand(host, "volume", clampVolume(num(value, volume)));
      break;
    case "mute":
      await sendCommand(host, "volume", isTrue(state && state.mute) ? "unmute" : "mute");
      break;
    default:
      return false;
  }
  return true;
}

// ---------- Widget ----------

function actionURL(host, action, value) {
  const base = URLScheme.forRunningScript();
  let url = `${base}${base.includes("?") ? "&" : "?"}action=${encodeURIComponent(action)}&host=${encodeURIComponent(host)}`;
  if (value !== undefined) url += `&value=${encodeURIComponent(value)}`;
  return url;
}

function symbol(name, size) {
  const sym = SFSymbol.named(name) || SFSymbol.named("questionmark");
  sym.applyFont(Font.systemFont(size));
  return sym.image;
}

// A fixed-size tappable box with an SF Symbol in the middle.
function addButton(parent, symbolName, url, box, iconSize, color) {
  const btn = parent.addStack();
  btn.size = new Size(box, box);
  btn.centerAlignContent();
  btn.url = url;
  const img = btn.addImage(symbol(symbolName, iconSize));
  img.imageSize = new Size(iconSize, iconSize);
  img.tintColor = color || TEXT;
  return btn;
}

function addText(parent, text, font, color, lines) {
  const t = parent.addText(text);
  t.font = font;
  t.textColor = color;
  t.lineLimit = lines || 1;
  t.minimumScaleFactor = 0.8;
  return t;
}

function placeholderArt(size) {
  const ctx = new DrawContext();
  ctx.size = new Size(size, size);
  ctx.opaque = false;
  ctx.respectScreenScale = true;
  const path = new Path();
  path.addRoundedRect(new Rect(0, 0, size, size), size * 0.1, size * 0.1);
  ctx.addPath(path);
  ctx.setFillColor(new Color("#ffffff", 0.12));
  ctx.fillPath();
  const icon = symbol("music.note", size * 0.4);
  const s = size * 0.4;
  ctx.drawImageInRect(icon, new Rect((size - s) / 2, (size - s) / 2, s, s));
  return ctx.getImage();
}

function addArt(parent, image, size) {
  const img = parent.addImage(image || placeholderArt(size));
  img.imageSize = new Size(size, size);
  img.cornerRadius = image ? size * 0.08 : 0;
  if (!image) img.tintColor = TEXT_DIM;
  return img;
}

function statusLine(state) {
  const status = String(state.status || "stop");
  const label = status === "play" ? "Playing" : status === "pause" ? "Paused" : "Stopped";
  const service = state.service && state.service !== "mpd" ? state.service : state.trackType;
  return service ? `${label} · ${service}` : label;
}

function timeLabel() {
  const df = new DateFormatter();
  df.useNoDateStyle();
  df.useShortTimeStyle();
  return df.string(new Date());
}

// Mute button, -, 10 tappable volume segments, +, and the level.
function addVolumeRow(w, host, state, compact) {
  const row = w.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();

  if (isTrue(state.disableVolumeControl)) {
    addText(row, "Volume control is off on this player", Font.systemFont(12), TEXT_FAINT);
    return;
  }

  const volume = clampVolume(num(state.volume, 0));
  const muted = isTrue(state.mute);
  const box = compact ? 26 : 30;
  const icon = compact ? 16 : 18;

  addButton(row, muted ? "speaker.slash.fill" : "speaker.wave.2.fill", actionURL(host, "mute"), box, icon, muted ? ACCENT : TEXT);
  addButton(row, "minus", actionURL(host, "voldown"), box, icon - 2);

  const segW = compact ? 11 : 14;
  const segments = row.addStack();
  segments.layoutHorizontally();
  segments.centerAlignContent();
  for (let i = 1; i <= 10; i++) {
    const target = i * 10;
    const tap = segments.addStack();
    tap.size = new Size(segW, box);
    tap.centerAlignContent();
    tap.url = actionURL(host, "vol", target);
    const pill = tap.addStack();
    pill.size = new Size(segW - 4, compact ? 12 : 16);
    pill.cornerRadius = 3;
    const lit = volume >= target - 5;
    pill.backgroundColor = lit ? (muted ? TEXT_FAINT : ACCENT) : BAR_OFF;
  }

  addButton(row, "plus", actionURL(host, "volup"), box, icon - 2);
  row.addSpacer(4);
  const label = addText(row, muted ? "Muted" : `${volume}`, Font.semiboldSystemFont(compact ? 13 : 15), muted ? TEXT_DIM : TEXT);
  label.rightAlignText();
}

function addTransportRow(w, host, state, compact) {
  const playing = String(state.status) === "play";
  const row = w.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  if (!compact) row.addSpacer();
  addButton(row, "backward.fill", actionURL(host, "prev"), compact ? 34 : 50, compact ? 18 : 24);
  row.addSpacer(compact ? 4 : 18);
  addButton(row, playing ? "pause.circle.fill" : "play.circle.fill", actionURL(host, "toggle"), compact ? 38 : 60, compact ? 30 : 50, compact ? TEXT : ACCENT);
  row.addSpacer(compact ? 4 : 18);
  addButton(row, "forward.fill", actionURL(host, "next"), compact ? 34 : 50, compact ? 18 : 24);
  if (!compact) row.addSpacer();
}

function newWidget(host) {
  const w = new ListWidget();
  const bg = new LinearGradient();
  bg.colors = [new Color("#23272e"), new Color("#0f1114")];
  bg.locations = [0, 1];
  w.backgroundGradient = bg;
  w.setPadding(14, 14, 14, 14);
  w.refreshAfterDate = new Date(Date.now() + REFRESH_MINUTES * 60 * 1000);
  w.url = actionURL(host, "open");
  return w;
}

function errorWidget(host, error) {
  const w = newWidget(host);
  const row = w.addStack();
  row.centerAlignContent();
  const img = row.addImage(symbol("wifi.exclamationmark", 18));
  img.imageSize = new Size(18, 18);
  img.tintColor = TEXT_DIM;
  row.addSpacer(6);
  addText(row, "Volumio", Font.boldSystemFont(14), TEXT);
  w.addSpacer(8);
  addText(w, `Can't reach ${host}`, Font.systemFont(13), TEXT_DIM, 2);
  addText(w, "Only works on the same Wi-Fi as the player.", Font.systemFont(11), TEXT_FAINT, 2);
  w.addSpacer();
  addText(w, `Tried ${timeLabel()}`, Font.systemFont(10), TEXT_FAINT);
  return w;
}

async function buildWidget(host, family) {
  let state, name;
  try {
    [state, name] = await Promise.all([getState(host), getPlayerName(host)]);
  } catch (e) {
    return errorWidget(host, e);
  }
  const art = await loadAlbumArt(host, state);
  const title = state.title || "Nothing playing";
  const artist = [state.artist, state.album].filter(Boolean).join(" — ");
  const w = newWidget(host);

  if (family === "small") {
    addArt(w, art, 64);
    w.addSpacer(8);
    addText(w, title, Font.boldSystemFont(13), TEXT, 2);
    if (state.artist) addText(w, state.artist, Font.systemFont(11), TEXT_DIM);
    w.addSpacer();
    addText(w, `${statusLine(state)} · ${isTrue(state.mute) ? "muted" : clampVolume(num(state.volume, 0))}`, Font.systemFont(10), TEXT_FAINT);
    return w;
  }

  if (family === "medium") {
    const top = w.addStack();
    top.centerAlignContent();
    addArt(top, art, 58);
    top.addSpacer(10);
    const info = top.addStack();
    info.layoutVertically();
    addText(info, title, Font.boldSystemFont(14), TEXT);
    if (artist) addText(info, artist, Font.systemFont(12), TEXT_DIM);
    addText(info, statusLine(state), Font.systemFont(10), TEXT_FAINT);
    top.addSpacer();
    addTransportRow(top, host, state, true);
    w.addSpacer();
    addVolumeRow(w, host, state, true);
    return w;
  }

  // Large (and extra large on iPad).
  const header = w.addStack();
  header.centerAlignContent();
  addText(header, (name || "Volumio").toUpperCase(), Font.semiboldSystemFont(11), ACCENT);
  header.addSpacer();
  addText(header, timeLabel(), Font.systemFont(10), TEXT_FAINT);
  w.addSpacer(10);

  const top = w.addStack();
  top.centerAlignContent();
  addArt(top, art, 112);
  top.addSpacer(14);
  const info = top.addStack();
  info.layoutVertically();
  addText(info, title, Font.boldSystemFont(18), TEXT, 3);
  info.addSpacer(4);
  if (state.artist) addText(info, state.artist, Font.systemFont(14), TEXT_DIM, 2);
  if (state.album) addText(info, state.album, Font.systemFont(12), TEXT_FAINT);
  info.addSpacer(6);
  addText(info, statusLine(state), Font.mediumSystemFont(11), TEXT_FAINT);
  top.addSpacer();

  w.addSpacer();
  addTransportRow(w, host, state, false);
  w.addSpacer();
  addVolumeRow(w, host, state, false);
  return w;
}

// ---------- In-app remote ----------

async function showRemote(host, notice) {
  const table = new UITable();
  table.showSeparators = true;

  const act = (action, value) => async () => {
    try {
      const state = await getState(host);
      await runAction(host, action, value, state);
      await sleep(300);
      notice = null;
    } catch (e) {
      notice = `Failed: ${e.message || e}`;
    }
    await render();
  };

  function buttonRow(buttons) {
    const row = new UITableRow();
    row.height = 54;
    for (const [label, handler] of buttons) {
      const cell = row.addButton(label);
      cell.centerAligned();
      cell.onTap = handler;
    }
    table.addRow(row);
  }

  async function render() {
    let state = null;
    let error = null;
    try {
      state = await getState(host);
    } catch (e) {
      error = e;
    }
    table.removeAllRows();

    const head = new UITableRow();
    head.isHeader = true;
    head.addText("Volumio", host);
    table.addRow(head);

    if (notice) {
      const row = new UITableRow();
      row.addText(notice).titleColor = Color.red();
      table.addRow(row);
    }

    if (error) {
      const row = new UITableRow();
      row.height = 70;
      row.addText(`Can't reach ${host}`, "Check that you're on the same Wi-Fi and that the address is right.");
      table.addRow(row);
    } else {
      const now = new UITableRow();
      now.height = 110;
      const artURL = albumArtURL(host, state.albumart);
      if (artURL) {
        const img = now.addImageAtURL(artURL);
        img.widthWeight = 25;
      }
      const text = now.addText(state.title || "Nothing playing", [state.artist, state.album].filter(Boolean).join(" — ") + `\n${statusLine(state)}`);
      text.widthWeight = 75;
      text.titleFont = Font.boldSystemFont(17);
      table.addRow(now);

      const playing = String(state.status) === "play";
      buttonRow([
        ["⏮", act("prev")],
        [playing ? "⏸" : "▶️", act("toggle")],
        ["⏭", act("next")],
      ]);

      if (isTrue(state.disableVolumeControl)) {
        const row = new UITableRow();
        row.addText("Volume control is off on this player");
        table.addRow(row);
      } else {
        const muted = isTrue(state.mute);
        const vol = clampVolume(num(state.volume, 0));
        buttonRow([
          [`− ${VOLUME_STEP}`, act("voldown")],
          [muted ? "🔇 Muted" : `🔊 ${vol}`, act("mute")],
          [`+ ${VOLUME_STEP}`, act("volup")],
        ]);
        buttonRow(VOLUME_PRESETS.map((v) => [`${v}`, act("vol", v)]));
      }
    }

    buttonRow([["↻ Refresh", async () => render()]]);
    if (!config.runsWithSiri) {
      buttonRow([["Preview large widget", async () => (await buildWidget(host, "large")).presentLarge()]]);
    }
    table.reload();
  }

  await render();
  await table.present(false);
}

// ---------- Entry point ----------

async function main() {
  const params = args.queryParameters || {};
  const host =
    normalizeHost(params.host) ||
    normalizeHost(args.widgetParameter) ||
    normalizeHost(DEFAULT_HOST);

  if (config.runsInWidget) {
    Script.setWidget(await buildWidget(host, config.widgetFamily));
    return;
  }

  const action = params.action;
  let notice = null;
  if (action && action !== "open") {
    try {
      const state = await getState(host);
      await runAction(host, action, params.value, state);
      await sleep(300);
    } catch (e) {
      notice = `Couldn't send "${action}" to ${host}: ${e.message || e}`;
    }
    if (!SHOW_REMOTE_AFTER_TAP && !notice) return;
  }

  await showRemote(host, notice);
}

await main();
Script.complete();
