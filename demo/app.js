/* Orion window replay. Audio from the archive is the clock. No synthesized sound. */

const ORION = new Set(["saw2", "saw3", "saw4", "cab2", "onav", "dcam"]);
// art002e016183 is a Z9 frame of a lit rectangle in an otherwise black cabin
// (bright pixels sit in the middle; they do not form a lunar limb). It is
// not shown through the glass.
const CABIN_IDS = new Set(["art002e016183"]);
const glance = document.getElementById("glance");
const glanceImg = document.getElementById("glanceImg");
const glanceCap = document.getElementById("glanceCap");
const stage = document.getElementById("stage");
const wall = document.getElementById("wall");
const windowEl = document.getElementById("window");
const reflectEl = document.querySelector(".reflect");
const hud = document.getElementById("hud");
const enter = document.getElementById("enter");
let photoA = document.getElementById("photoA");
let photoB = document.getElementById("photoB");
const subs = document.getElementById("subs");
const credit = document.getElementById("credit");
const empty = document.getElementById("empty");
const clock = document.getElementById("clock");
const note = document.getElementById("note");
const scrub = document.getElementById("scrub");
const offsetInput = document.getElementById("offset");
const offsetVal = document.getElementById("offsetval");
const map = document.getElementById("map");
const playBtn = document.getElementById("play");
const taken = document.getElementById("taken");
const clockNote = document.getElementById("clocknote");
const backFly = document.getElementById("backfly");

const audio = new Audio();
audio.id = "voice";
audio.preload = "auto";
document.body.appendChild(audio);

// Timeline paths are relative to demo/data/, next to timeline.json.
// The page itself is served from demo/.
const DATA = new URL("data/", document.baseURI);
function media(file) {
  return new URL(file, DATA).href;
}

let doc = null;
let utcMs = 0;
let playing = false;
let rate = 1;
let track = "pcd3";
let highlight = null;
let camera = "all";
let windowView = "2";
let rangeKey = "flyby";
let savedFlybyMs = null;
let savedTrack = null;
let offsetS = 0;
let currentFile = null;
let loadGen = 0;
let hideTimer = 0;
let lastWall = 0;
let shownId = null;
let seeking = false;
let shownLine = "";
let shownNote = "";
let shownClock = "";
let shownPlate = "";
let shownTaken = "";
let shownRange = "";
let scrubStamp = null;
let aimX = 0;
let aimY = 0;
let lookX = 0;
let lookY = 0;
let floatX = 0;
let floatY = 0;
let floatR = 0;
let plate = 0;
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const tOf = (iso) => Date.parse(iso);
const pad = (n) => String(n).padStart(2, "0");

function fmt(ms) {
  const d = new Date(ms);
  return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;
}

function poke() {
  hud.hidden = false;
  hud.classList.add("show");
  clearTimeout(hideTimer);
  hideTimer = setTimeout(() => hud.classList.remove("show"), 3400);
}

function cameraMatch(frame) {
  const cab = frame.instrument === "cab2";
  if (windowView === "3") return cab;
  if (cab) return false;
  if (camera === "window2") return frame.instrument === "nkd5015";
  if (camera === "z9") return frame.instrument === "nkz9019";
  if (camera === "orion") return ORION.has(frame.instrument);
  return true;
}

function activeSpan() {
  if (rangeKey === "cab" && doc.cab_run) return doc.cab_run;
  return doc.window;
}

function isCabin(frame) {
  return frame.view === "cabin" || CABIN_IDS.has(frame.nasa_id);
}

function frames() {
  return doc.frames.filter((frame) => cameraMatch(frame) && !isCabin(frame));
}

function cabinAt(t) {
  const row = doc.frames.find((frame) => isCabin(frame) && cameraMatch(frame) && t >= tOf(frame.utc) && t < tOf(frame.utc) + 9000);
  return row || null;
}

function pair(t) {
  const list = frames();
  let index = 0;
  for (; index < list.length; index += 1) {
    if (tOf(list[index].utc) + offsetS * 1000 > t) break;
  }
  return {
    cur: list[index - 1] || null,
    next: list[index] || null,
    index: Math.max(0, index - 1),
    list,
  };
}

// A Nikon frame from the flyby is hours older than the Cab Cam run.
// Holding it would pretend the 19:46 exposure is still the view.
function visiblePair(t) {
  const view = pair(t);
  if (windowView !== "3" && view.cur) {
    const age = t - (tOf(view.cur.utc) + offsetS * 1000);
    if (age > 15 * 60 * 1000) {
      return { cur: null, next: null, index: 0, list: view.list, stale: view.cur };
    }
  }
  return view;
}

function takenText(frame) {
  if (!frame || windowView !== "3") return "";
  const when = `${frame.utc.slice(11, 19)} UTC`;
  const age = utcMs - tOf(frame.utc);
  const parts = [`Taken ${when} · ${frame.nasa_id}.`];
  if (frame.look === "dark") {
    parts.push("Real GoPro exposure, nearly black. Not a mask, and not brightened.");
  } else {
    parts.push("Shown as photographed. No window frame is drawn over this picture.");
  }
  if (age > 45000) {
    parts.push(`Orion clock is ${fmt(utcMs)} UTC. This frame was not moved to match it.`);
  }
  return parts.join(" ");
}

function segmentAt(t) {
  const rows = doc.segments.filter((seg) => seg.track === track);
  return rows.find((seg) => t >= tOf(seg.start) && t < tOf(seg.end)) || null;
}

function lineAt(t) {
  const rows = doc.lines.filter((line) => line.track === track);
  let current = null;
  for (const line of rows) {
    if (tOf(line.utc) <= t) current = line;
    else break;
  }
  if (!current) return null;
  const next = rows.find((line) => tOf(line.utc) > tOf(current.utc));
  const until = next ? tOf(next.utc) : tOf(current.utc) + 7000;
  if (t > until || t > tOf(current.utc) + 8000) return null;
  return current;
}

// python -m http.server does not send Accept-Ranges, and Chrome then reports
// the m4a as not seekable. A blob URL is seekable, so the scrubber and the
// crew switch can land inside a recording.
const audioBlobs = new Map();

function sourceUrl(file) {
  let pending = audioBlobs.get(file);
  if (!pending) {
    pending = fetch(media(file)).then(async (response) => {
      if (!response.ok) throw new Error("audio");
      return URL.createObjectURL(await response.blob());
    }).catch((err) => {
      audioBlobs.delete(file);
      throw err;
    });
    audioBlobs.set(file, pending);
  }
  return pending;
}

async function ensureAudio() {
  const seg = segmentAt(utcMs);
  if (!seg) {
    loadGen += 1;
    if (!audio.paused) audio.pause();
    currentFile = null;
    return false;
  }
  let gen = loadGen;
  if (currentFile !== seg.file) {
    gen = ++loadGen;
    currentFile = seg.file;
    try {
      const url = await sourceUrl(seg.file);
      if (gen !== loadGen) return false;
      audio.src = url;
      audio.dataset.file = seg.file;
      audio.playbackRate = rate;
      const loaded = audio.readyState >= 1 && audio.currentSrc === audio.src;
      if (!loaded) {
        await new Promise((resolve, reject) => {
          const ready = () => {
            cleanup();
            resolve();
          };
          const fail = () => {
            cleanup();
            reject(new Error("audio"));
          };
          const cleanup = () => {
            audio.removeEventListener("loadedmetadata", ready);
            audio.removeEventListener("error", fail);
          };
          if (audio.readyState >= 1 && audio.currentSrc === audio.src) {
            resolve();
            return;
          }
          audio.addEventListener("loadedmetadata", ready);
          audio.addEventListener("error", fail);
        });
      }
    } catch (_err) {
      if (gen === loadGen) currentFile = null;
      return false;
    }
  }
  // A newer seek may have started another load while this one was in flight.
  if (gen !== loadGen || currentFile !== seg.file) return false;
  // Recompute after the await so a seek during load is not discarded.
  const rel = Math.max(0, (utcMs - tOf(seg.start)) / 1000);
  if (audio.readyState >= 1 && Math.abs(audio.currentTime - rel) > 0.35) {
    audio.currentTime = rel;
  }
  if (gen !== loadGen || segmentAt(utcMs)?.file !== seg.file) return false;
  audio.playbackRate = rate;
  if (playing && audio.paused) {
    try { await audio.play(); } catch (_err) { /* gesture already happened; ignore autoplay races */ }
  }
  if (gen !== loadGen) return false;
  if (!playing && !audio.paused) audio.pause();
  return true;
}

function paint() {
  const view = visiblePair(utcMs);
  const frame = view.cur;
  const clockStr = fmt(utcMs);
  if (clockStr !== shownClock) {
    shownClock = clockStr;
    clock.textContent = clockStr;
  }
  if (!frame && view.next) {
    // The glass stays on the next real exposure and fades it up to the
    // timestamp. Nothing is invented for the gap before 19:33:26.
    empty.hidden = true;
    const arrival = view.next;
    const start = tOf(doc.window.start);
    const at = tOf(arrival.utc) + offsetS * 1000;
    const along = Math.min(1, Math.max(0, (utcMs - start) / Math.max(1, at - start)));
    // A faint hold of that same frame, then up to full at its timestamp.
    const fadeIn = reduceMotion ? 1 : 0.14 + 0.86 * (along * along);
    useFrame(arrival);
    photoB.style.opacity = "0";
    photoA.style.opacity = String(fadeIn);
    applyMotion(photoA, photoB, 0, 0);
    credit.textContent = fadeIn > 0.18
      ? `${arrival.credit}. Independent viewer, not a NASA product.`
      : "";
    const moon = photoA.complete && photoA.naturalWidth ? sampleMoon(photoA) * fadeIn : 0;
    stage.style.setProperty("--moon", moon.toFixed(3));
    easePlate(fadeIn > 0.2 ? photoA : null);
  } else if (!frame) {
    photoA.style.opacity = 0;
    photoB.style.opacity = 0;
    empty.hidden = false;
    if (view.stale) {
      empty.textContent = `No Window 2 frame was taken at ${fmt(utcMs)} UTC. The newest matching frame is ${view.stale.utc.slice(11, 19)} UTC (${view.stale.nasa_id}) and was not moved here.`;
    } else if (camera === "orion") {
      empty.textContent = "No Orion vehicle still falls in this window. SAW Cam 3’s science cadence is about one frame every eight minutes, and none of those frames is in the shipped set.";
    } else if (windowView === "3") {
      empty.textContent = "No Cab Cam frame was taken at this time. Times are not shifted to fill the gap.";
    } else {
      empty.textContent = "No shipped frame for this camera.";
    }
    credit.textContent = "";
    stage.style.setProperty("--moon", "0");
    easePlate(null);
  } else {
    empty.hidden = true;
    const progress = view.next
      ? Math.min(1, Math.max(0, (utcMs - (tOf(frame.utc) + offsetS * 1000)) / (tOf(view.next.utc) - tOf(frame.utc))))
      : 0;
    // Decode the next exposure before the dissolve so the glass does not dip to black.
    if (view.next && progress > 0.35) {
      const nextUrl = media(view.next.file);
      if (photoB.src !== nextUrl) {
        photoB.src = nextUrl;
        photoB.alt = view.next.credit;
      }
    }
    const fade = !reduceMotion && view.next && progress > 0.9;
    useFrame(frame);
    if (fade) {
      const ready = photoB.complete && photoB.naturalWidth > 0;
      if (ready) {
        const mix = (progress - 0.9) / 0.1;
        photoB.style.opacity = String(mix);
        photoA.style.opacity = String(1 - mix);
      } else {
        photoA.style.opacity = "1";
        photoB.style.opacity = "0";
      }
    } else {
      photoA.style.opacity = "1";
      photoB.style.opacity = "0";
    }
    applyMotion(photoA, photoB, progress, view.index);
    credit.textContent = `${frame.credit}. Independent viewer, not a NASA product.`;
    const aOp = parseFloat(photoA.style.opacity) || 0;
    const bOp = parseFloat(photoB.style.opacity) || 0;
    const visible = aOp >= bOp ? photoA : photoB;
    if (visible.complete && visible.naturalWidth) stage.style.setProperty("--moon", sampleMoon(visible).toFixed(3));
    easePlate(visible.complete && visible.naturalWidth ? visible : null);
  }

  const cabin = cabinAt(utcMs);
  if (!cabin) {
    glance.hidden = true;
  } else {
    glance.hidden = false;
    const src = media(cabin.file);
    if (glanceImg.src !== src) {
      glanceImg.src = src;
      glanceImg.alt = `${cabin.credit}. Cabin interior, not the view through the window.`;
    }
    glanceCap.textContent = `${cabin.credit}. This Z9 frame is inside the cabin, so it stays off the glass.`;
  }

  const line = lineAt(utcMs);
  const mine = line && highlight && line.speaker === highlight;
  const lineKey = line ? `${line.utc}|${mine ? 1 : 0}|${highlight || ""}` : "";
  if (lineKey !== shownLine) {
    shownLine = lineKey;
    if (!line) {
      subs.replaceChildren();
      subs.className = "";
    } else {
      subs.className = mine ? "mine" : highlight ? "dim" : "";
      const who = document.createElement("span");
      who.className = "who";
      who.textContent = line.role ? `${line.speaker} · ${line.role}` : (line.speaker || "Crew");
      const say = document.createElement("span");
      say.className = "say";
      say.textContent = line.text;
      subs.replaceChildren(who, say);
    }
  }

  const spanDoc = activeSpan();
  const takenLine = takenText(frame);
  if (takenLine !== shownTaken) {
    shownTaken = takenLine;
    taken.textContent = takenLine;
  }
  const rangeLine = rangeKey === "cab"
    ? "Cab Cam run, real UTC. Pictures were not shifted into the flyby."
    : "UTC on the Orion clock. Audio is the master.";
  if (rangeLine !== shownRange) {
    shownRange = rangeLine;
    clockNote.textContent = rangeLine;
  }
  const span = tOf(spanDoc.end) - tOf(spanDoc.start);
  if (!seeking) {
    const next = String(Math.round(((utcMs - tOf(spanDoc.start)) / span) * 1000));
    if (scrub.value !== next) {
      scrubStamp = next;
      scrub.value = next;
    }
  }
  const gap = !segmentAt(utcMs);
  const who = highlight || "the crew";
  const noteText = [
    highlight
      ? `${who}'s narration is highlighted. Photos are not attributed to ${who}; the credit on every frame is NASA/Artemis II Crew. Filtering is by camera and by the guide's window note.`
      : "Photos are credited to NASA/Artemis II Crew. There is no per-person photographer field.",
    gap ? "Gap between recordings. The clock keeps moving. No sound is added." : "",
    "art002e016183 is a cabin interior and stays off the glass. The PCD recording is not panned, and no sound is added.",
    doc.pointing.note,
  ].filter(Boolean).join(" ");
  if (noteText !== shownNote) {
    shownNote = noteText;
    note.textContent = noteText;
  }
  if (!hud.hidden) drawMap(view.cur);
}

function drawMap(current) {
  const ctx = map.getContext("2d");
  const w = map.width;
  const h = map.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#10141c";
  ctx.fillRect(0, 0, w, h);
  const lon0 = 210;
  const lon1 = 330;
  const lat0 = -40;
  const lat1 = 45;
  const xy = (lon, lat) => [
    ((lon - lon0) / (lon1 - lon0)) * w,
    ((lat1 - lat) / (lat1 - lat0)) * h,
  ];
  ctx.strokeStyle = "rgba(244,241,234,0.12)";
  ctx.lineWidth = 1;
  for (let lon = 220; lon <= 320; lon += 20) {
    ctx.beginPath();
    const [x] = xy(lon, 0);
    ctx.moveTo(x, 0);
    ctx.lineTo(x, h);
    ctx.stroke();
  }
  for (let lat = -30; lat <= 40; lat += 15) {
    ctx.beginPath();
    const [, y] = xy(0, lat);
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }
  const nearby = doc.frames.filter((frame) => {
    if (!frame.footprint || !frame.footprint.length) return false;
    return Math.abs(tOf(frame.utc) - utcMs) < 3 * 60 * 1000;
  });
  for (const frame of nearby) {
    const ring = frame.footprint;
    ctx.beginPath();
    ring.forEach((pairLonLat, i) => {
      const [x, y] = xy(pairLonLat[0], pairLonLat[1]);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.closePath();
    const on = current && frame.nasa_id === current.nasa_id;
    ctx.fillStyle = on ? "rgba(240,215,162,0.35)" : "rgba(180,198,214,0.16)";
    ctx.strokeStyle = on ? "#f0d7a2" : "rgba(180,198,214,0.7)";
    ctx.fill();
    ctx.stroke();
  }
  ctx.font = "11px Helvetica, sans-serif";
  for (const target of doc.targets) {
    if (!target.geographic) continue;
    if (target.lon < lon0 || target.lon > lon1 || target.lat < lat0 || target.lat > lat1) continue;
    const [x, y] = xy(target.lon, target.lat);
    ctx.fillStyle = "#f4f1ea";
    ctx.beginPath();
    ctx.arc(x, y, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillText(target.name, x + 6, y - 4);
  }
}

const lumCanvas = document.createElement("canvas");
lumCanvas.width = 32;
lumCanvas.height = 16;
const moonCache = new Map();
const plateCache = new Map();

function meanLuma(data) {
  let sum = 0;
  const count = data.length / 4;
  for (let i = 0; i < data.length; i += 4) {
    sum += (0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) / 255;
  }
  return sum / count;
}

function sampleMoon(img) {
  const key = img.currentSrc;
  if (moonCache.has(key)) return moonCache.get(key);
  const ctx = lumCanvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, 16, 16);
  const value = meanLuma(ctx.getImageData(0, 0, 16, 16).data);
  moonCache.set(key, value);
  return value;
}

function regionLuma(img) {
  const key = img.currentSrc;
  if (plateCache.has(key)) return plateCache.get(key);
  const ctx = lumCanvas.getContext("2d", { willReadFrequently: true });
  const sw = img.naturalWidth;
  const sh = img.naturalHeight;
  ctx.clearRect(0, 0, 32, 16);
  ctx.drawImage(img, sw * 0.2, sh * 0.55, sw * 0.6, sh * 0.32, 0, 0, 32, 16);
  const value = meanLuma(ctx.getImageData(0, 0, 32, 16).data);
  plateCache.set(key, value);
  return value;
}

function easePlate(img) {
  const target = img && img.complete && img.naturalWidth ? regionLuma(img) : 0;
  plate += (target - plate) * (reduceMotion ? 1 : 0.18);
  const next = plate.toFixed(3);
  if (next !== shownPlate) {
    shownPlate = next;
    subs.style.setProperty("--plate", next);
  }
}

function applyMotion(a, b, progress, index) {
  if (reduceMotion || windowView === "3") {
    a.style.transform = "none";
    b.style.transform = "none";
    return;
  }
  const drift = (index % 2 === 0 ? -1 : 1) * progress * 1.1;
  const panX = -lookX * 2.2 + floatX;
  const panY = -lookY * 1.4 + floatY;
  const scale = 1.06 + progress * 0.05;
  const rot = floatR.toFixed(3);
  a.style.transform = `translate(${panX + drift}%, ${panY + progress * 0.4}%) rotate(${rot}deg) scale(${scale})`;
  b.style.transform = `translate(${panX * 0.6}%, ${panY * 0.6}%) rotate(${rot}deg) scale(1.06)`;
}

function useFrame(frame) {
  if (shownId === frame.nasa_id) return;
  const url = media(frame.file);
  const alt = `${frame.credit}. ${frame.camera_label}.`;
  // The back buffer already holds this exposure from the dissolve. Promote
  // that decoded bitmap instead of assigning a new src, which blanks the glass.
  if (photoB.src === url && photoB.complete && photoB.naturalWidth) {
    const hold = photoA;
    photoA = photoB;
    photoB = hold;
    photoA.alt = alt;
  } else {
    photoA.src = url;
    photoA.alt = alt;
  }
  shownId = frame.nasa_id;
}

function loop(now) {
  requestAnimationFrame(loop);
  if (!reduceMotion) {
    lookX += (aimX - lookX) * 0.08;
    lookY += (aimY - lookY) * 0.08;
    const t = now / 1000;
    // Slow, uneven drift. Two incommensurate sines, not a mechanical loop.
    floatX = Math.sin(t / 7.4) * 0.28 + Math.sin(t / 12.8) * 0.14;
    floatY = Math.cos(t / 9.2) * 0.2 + Math.sin(t / 16.5) * 0.09;
    floatR = Math.sin(t / 11.3) * 0.07 + Math.sin(t / 18.7) * 0.035;
    // Direct transforms. Writing the custom properties every frame repainted
    // the gradients and the blurred lip, and the replay fell to a few fps.
    wall.style.transform = `translate(${(lookX * 14 + floatX * 5).toFixed(2)}px, ${(lookY * 10 + floatY * 4).toFixed(2)}px)`;
    windowEl.style.transform = `translate(calc(-50% + ${(lookX * 10 + floatX * 7).toFixed(2)}px), calc(-50% + ${(lookY * 7 + floatY * 5).toFixed(2)}px)) rotate(${floatR.toFixed(3)}deg)`;
    reflectEl.style.transform = `translate(${(-lookX * 28 - floatX * 10).toFixed(2)}px, ${(-lookY * 16).toFixed(2)}px)`;
  }
  if (!doc) return;
  if (playing) {
    let seg = segmentAt(utcMs);
    if (audio.seeking) {
      // The element has not landed yet. Keep the mission clock on the seek.
    } else if (seg && currentFile === seg.file && !audio.paused && audio.readyState >= 2) {
      const rel = (utcMs - tOf(seg.start)) / 1000;
      // A seek is applied on the element asynchronously. Until currentTime
      // catches the mission clock, leave utcMs where the seek put it.
      if (Math.abs(audio.currentTime - rel) < 0.8) {
        utcMs = tOf(seg.start) + audio.currentTime * 1000;
      }
    } else if (lastWall) {
      utcMs += (now - lastWall) * rate;
    }
    const end = tOf(activeSpan().end);
    if (utcMs >= end) {
      utcMs = end;
      playing = false;
      playBtn.textContent = "Play";
      audio.pause();
    }
    seg = segmentAt(utcMs);
    const needLoad = seg
      ? currentFile !== seg.file || (audio.paused && audio.readyState >= 2)
      : currentFile !== null;
    if (needLoad) ensureAudio();
  }
  lastWall = now;
  paint();
}

async function toggle() {
  playing = !playing;
  playBtn.textContent = playing ? "Pause" : "Play";
  if (playing) await ensureAudio();
  else audio.pause();
}

function seekTo(ms) {
  const span = activeSpan();
  utcMs = Math.min(tOf(span.end), Math.max(tOf(span.start), ms));
  ensureAudio();
}

function setTrack(next) {
  track = next;
  currentFile = null;
  document.querySelectorAll("[data-track]").forEach((button) => {
    button.classList.toggle("on", button.dataset.track === next);
  });
  if (playing) ensureAudio();
}

function setCrew(name) {
  const on = highlight === name ? null : name;
  highlight = on;
  document.querySelectorAll("[data-crew]").forEach((button) => {
    button.classList.toggle("on", button.dataset.crew === on);
    button.setAttribute("aria-pressed", button.dataset.crew === on ? "true" : "false");
  });
  if (on) {
    const row = doc.crew.find((person) => person.id === on);
    if (row) setTrack(row.track);
  }
}

function setCamera(next) {
  camera = next;
  shownId = null;
  document.querySelectorAll("[data-cam]").forEach((button) => {
    button.classList.toggle("on", button.dataset.cam === next);
  });
}

function setWindow(next) {
  windowView = next;
  shownId = null;
  stage.classList.toggle("cab", next === "3");
  document.querySelectorAll("[data-win]").forEach((button) => {
    button.classList.toggle("on", button.dataset.win === next);
    button.setAttribute("aria-pressed", button.dataset.win === next ? "true" : "false");
  });
  document.querySelector(".cameras").hidden = next === "3";
}

function enterCabRun() {
  if (rangeKey !== "cab") {
    savedFlybyMs = utcMs;
    savedTrack = track;
  }
  rangeKey = "cab";
  backFly.hidden = false;
  setWindow("3");
  setTrack("pcd2");
  seekTo(tOf(doc.cab_run.start));
}

function backToFlyby() {
  rangeKey = "flyby";
  backFly.hidden = true;
  const back = savedFlybyMs == null ? tOf(doc.window.start) : savedFlybyMs;
  const trackBack = savedTrack;
  savedFlybyMs = null;
  savedTrack = null;
  setWindow("2");
  if (trackBack) setTrack(trackBack);
  seekTo(back);
}

async function boot() {
  doc = await fetch("data/timeline.json").then((response) => response.json());
  utcMs = tOf(doc.window.start);
  enter.addEventListener("click", async () => {
    enter.hidden = true;
    playing = true;
    playBtn.textContent = "Pause";
    await ensureAudio();
  });
  playBtn.addEventListener("click", toggle);
  document.getElementById("full").addEventListener("click", () => {
    if (document.fullscreenElement) document.exitFullscreen();
    else stage.requestFullscreen();
  });
  scrub.addEventListener("pointerdown", () => { seeking = true; });
  scrub.addEventListener("input", () => {
    if (scrub.value === scrubStamp) {
      scrubStamp = null;
      return;
    }
    scrubStamp = null;
    const spanDoc = activeSpan();
    const span = tOf(spanDoc.end) - tOf(spanDoc.start);
    seekTo(tOf(spanDoc.start) + (Number(scrub.value) / 1000) * span);
  });
  scrub.addEventListener("pointerup", () => { seeking = false; });
  offsetInput.addEventListener("input", () => {
    offsetS = Number(offsetInput.value);
    offsetVal.textContent = `${offsetS.toFixed(1)} s`;
    shownId = null;
  });
  document.querySelectorAll("[data-crew]").forEach((button) => {
    button.addEventListener("click", () => setCrew(button.dataset.crew));
  });
  document.querySelectorAll("[data-cam]").forEach((button) => {
    button.addEventListener("click", () => setCamera(button.dataset.cam));
  });
  document.querySelectorAll("[data-win]").forEach((button) => {
    button.addEventListener("click", () => setWindow(button.dataset.win));
  });
  document.getElementById("cabrun").addEventListener("click", enterCabRun);
  backFly.addEventListener("click", backToFlyby);
  document.querySelectorAll("[data-win]").forEach((button) => {
    button.setAttribute("aria-pressed", button.dataset.win === "2" ? "true" : "false");
  });
  document.querySelectorAll("[data-track]").forEach((button) => {
    button.addEventListener("click", () => setTrack(button.dataset.track));
  });
  window.addEventListener("mousemove", poke);
  window.addEventListener("pointermove", (event) => {
    if (reduceMotion) return;
    aimX = (event.clientX / window.innerWidth) * 2 - 1;
    aimY = (event.clientY / window.innerHeight) * 2 - 1;
  });
  window.addEventListener("deviceorientation", (event) => {
    if (reduceMotion || event.gamma == null) return;
    aimX = Math.max(-1, Math.min(1, event.gamma / 28));
    aimY = Math.max(-1, Math.min(1, ((event.beta || 0) - 45) / 32));
  });
  window.addEventListener("keydown", (event) => {
    poke();
    if (event.key === " ") {
      event.preventDefault();
      if (enter.hidden) toggle();
      else enter.click();
    } else if (event.key === "f") {
      document.getElementById("full").click();
    } else if (event.key === "ArrowRight") {
      seekTo(utcMs + 5000);
    } else if (event.key === "ArrowLeft") {
      seekTo(utcMs - 5000);
    }
  });
  requestAnimationFrame(loop);
}

boot();
