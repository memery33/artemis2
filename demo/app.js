/* Orion window replay. Audio from the archive is the clock. No synthesized sound. */

const ORION = new Set(["saw2", "saw3", "saw4", "cab2", "onav", "dcam"]);
const stage = document.getElementById("stage");
const hud = document.getElementById("hud");
const enter = document.getElementById("enter");
const photoA = document.getElementById("photoA");
const photoB = document.getElementById("photoB");
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
let offsetS = 0;
let currentFile = null;
let loadGen = 0;
let hideTimer = 0;
let lastWall = 0;
let shownId = null;
let seeking = false;
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

function frames() {
  return doc.frames.filter((frame) => {
    if (camera === "window2") return frame.instrument === "nkd5015";
    if (camera === "z9") return frame.instrument === "nkz9019";
    if (camera === "orion") return ORION.has(frame.instrument);
    return true;
  });
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
    audio.src = media(seg.file);
    audio.playbackRate = rate;
    try {
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
  const view = pair(utcMs);
  const frame = view.cur;
  clock.textContent = fmt(utcMs);
  if (!frame) {
    photoA.style.opacity = 0;
    photoB.style.opacity = 0;
    if (view.list.length === 0) {
      empty.hidden = false;
      empty.textContent = camera === "orion"
        ? "No Orion vehicle still falls in this window. SAW Cam 3’s science cadence is about one frame every eight minutes, and none of those frames is in the shipped set."
        : "No shipped frame for this camera.";
    } else {
      empty.hidden = true;
    }
    credit.textContent = "";
  } else {
    empty.hidden = true;
    const progress = view.next
      ? Math.min(1, Math.max(0, (utcMs - (tOf(frame.utc) + offsetS * 1000)) / (tOf(view.next.utc) - tOf(frame.utc))))
      : 0;
    const fade = !reduceMotion && view.next && progress > 0.9;
    if (shownId !== frame.nasa_id) {
      shownId = frame.nasa_id;
      photoA.src = media(frame.file);
      photoA.alt = `${frame.credit}. ${frame.camera_label}.`;
    }
    if (fade) {
      const nextUrl = media(view.next.file);
      if (photoB.src !== nextUrl) {
        photoB.src = nextUrl;
        photoB.alt = view.next.credit;
      }
      photoB.style.opacity = (progress - 0.9) / 0.1;
      photoA.style.opacity = 1 - photoB.style.opacity;
    } else {
      photoA.style.opacity = 1;
      photoB.style.opacity = 0;
    }
    if (!reduceMotion) {
      const drift = (view.index % 2 === 0 ? -1 : 1) * progress * 1.6;
      const scale = 1.05 + progress * 0.07;
      photoA.style.transform = `scale(${scale}) translate(${drift}%, ${progress * 0.6}%)`;
      photoB.style.transform = `scale(1.05) translate(${-drift * 0.3}%, 0)`;
    }
    credit.textContent = `${frame.credit}. Independent viewer, not a NASA product.`;
  }

  const line = lineAt(utcMs);
  if (!line) {
    subs.innerHTML = "";
  } else {
    const mine = highlight && line.speaker === highlight;
    subs.className = mine ? "mine" : highlight ? "dim" : "";
    const who = document.createElement("span");
    who.className = "who";
    who.textContent = line.role ? `${line.speaker} · ${line.role}` : (line.speaker || "Crew");
    const say = document.createElement("span");
    say.className = "say";
    say.textContent = line.text;
    subs.replaceChildren(who, say);
  }

  const span = tOf(doc.window.end) - tOf(doc.window.start);
  if (!seeking) scrub.value = String(Math.round(((utcMs - tOf(doc.window.start)) / span) * 1000));
  const gap = !segmentAt(utcMs);
  const who = highlight || "the crew";
  note.textContent = [
    highlight
      ? `${who}'s narration is highlighted. Photos are not attributed to ${who}; the credit on every frame is NASA/Artemis II Crew. Filtering is by camera and by the guide's window note.`
      : "Photos are credited to NASA/Artemis II Crew. There is no per-person photographer field.",
    gap ? "Gap between recordings. The clock keeps moving. No sound is added." : "",
    doc.pointing.note,
  ].filter(Boolean).join(" ");
  drawMap(view.cur);
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

function loop(now) {
  requestAnimationFrame(loop);
  if (!doc) return;
  if (playing) {
    let seg = segmentAt(utcMs);
    if (seg && currentFile === seg.file && !audio.paused && audio.readyState >= 2) {
      const rel = (utcMs - tOf(seg.start)) / 1000;
      // A seek is applied on the element asynchronously. Until currentTime
      // catches the mission clock, leave utcMs where the seek put it.
      if (Math.abs(audio.currentTime - rel) < 0.8) {
        utcMs = tOf(seg.start) + audio.currentTime * 1000;
      }
    } else if (lastWall) {
      utcMs += (now - lastWall) * rate;
    }
    const end = tOf(doc.window.end);
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
  utcMs = Math.min(tOf(doc.window.end), Math.max(tOf(doc.window.start), ms));
  shownId = null;
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
    const span = tOf(doc.window.end) - tOf(doc.window.start);
    seekTo(tOf(doc.window.start) + (Number(scrub.value) / 1000) * span);
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
  document.querySelectorAll("[data-track]").forEach((button) => {
    button.addEventListener("click", () => setTrack(button.dataset.track));
  });
  window.addEventListener("mousemove", poke);
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
