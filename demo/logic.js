/* Pure helpers for the window replay. No network, no DOM. */

(function (root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  root.ArtemisLogic = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function project(lon, lat, width, height) {
    const lon0 = 210;
    const lon1 = 330;
    const lat0 = -40;
    const lat1 = 45;
    return [
      ((lon - lon0) / (lon1 - lon0)) * width,
      ((lat1 - lat) / (lat1 - lat0)) * height,
    ];
  }

  function overlap(a, b, pad) {
    return a.x < b.x2 + pad && a.x2 + pad > b.x && a.y < b.y2 + pad && a.y2 + pad > b.y;
  }

  function inside(box, bounds) {
    return box.x >= bounds.x && box.y >= bounds.y && box.x2 <= bounds.x2 && box.y2 <= bounds.y2;
  }

  function box(x, y, w, h) {
    return { x: x, y: y, x2: x + w, y2: y + h };
  }

  function candidatesFor(item) {
    const { x, y, w, h } = item;
    const spots = [
      [x + 6, y - h],
      [x - w - 6, y - h],
      [x - w / 2, y - h - 8],
      [x - w / 2, y + 8],
      [x + 8, y - h * 2 - 8],
      [x + 8, y + h + 4],
      [x - w - 8, y - h * 2 - 8],
      [x - w - 8, y + h + 4],
    ];
    for (let ring = 1; ring <= 6; ring += 1) {
      const shift = ring * (h + 4);
      spots.push([x + 6, y - h - shift]);
      spots.push([x + 6, y + shift]);
      spots.push([x - w - 6, y - h - shift]);
      spots.push([x - w - 6, y + shift]);
      spots.push([x + shift, y - h]);
      spots.push([x - w - shift, y - h]);
    }
    return spots.map((pair) => box(pair[0], pair[1], w, h));
  }

  function gridSearch(item, bounds, placed, pad) {
    const step = Math.max(4, Math.round(item.h / 2));
    let best = null;
    let bestDist = Infinity;
    for (let y = bounds.y; y + item.h <= bounds.y2; y += step) {
      for (let x = bounds.x; x + item.w <= bounds.x2; x += step) {
        const candidate = box(x, y, item.w, item.h);
        if (placed.some((row) => overlap(candidate, row, pad))) continue;
        const dist = Math.hypot(x - item.x, (y + item.h) - item.y);
        if (dist < bestDist) {
          bestDist = dist;
          best = candidate;
        }
      }
    }
    return best;
  }

  // anchors: {name, x, y, w, h}. One label per name. Boxes stay inside bounds
  // and do not overlap. A leader is set when the label sits away from its dot.
  function placeLabels(anchors, bounds) {
    const pad = 3;
    const seen = new Set();
    const items = [];
    for (const anchor of anchors) {
      if (seen.has(anchor.name)) continue;
      seen.add(anchor.name);
      items.push(anchor);
    }
    items.sort((a, b) => a.x - b.x || a.y - b.y);
    const placed = [];
    for (const item of items) {
      let chosen = null;
      for (const candidate of candidatesFor(item)) {
        if (!inside(candidate, bounds)) continue;
        if (placed.every((row) => !overlap(candidate, row, pad))) {
          chosen = candidate;
          break;
        }
      }
      if (!chosen) chosen = gridSearch(item, bounds, placed, pad);
      if (!chosen) {
        chosen = box(
          Math.min(Math.max(bounds.x, item.x), bounds.x2 - item.w),
          Math.min(Math.max(bounds.y, item.y), bounds.y2 - item.h),
          item.w,
          item.h,
        );
      }
      const cx = (chosen.x + chosen.x2) / 2;
      const cy = (chosen.y + chosen.y2) / 2;
      const leader = Math.hypot(cx - item.x, cy - item.y) > Math.max(16, item.h * 1.7);
      placed.push({
        name: item.name,
        ax: item.x,
        ay: item.y,
        x: chosen.x,
        y: chosen.y,
        x2: chosen.x2,
        y2: chosen.y2,
        leader: leader,
      });
    }
    return placed;
  }

  function chooseFont(names, mapWidth, basePx, measure, widthRatio) {
    let px = basePx;
    const ratio = Number.isFinite(widthRatio) ? widthRatio : 0.46;
    const limit = mapWidth * ratio;
    while (px > 8) {
      let widest = 0;
      for (const name of names) widest = Math.max(widest, measure(name, px));
      if (widest <= limit) return px;
      px -= 1;
    }
    return px;
  }

  function pad(n, width) {
    return String(n).padStart(width, "0");
  }

  // launchMs is the guide's mission start, or null when the data has none.
  function formatClocks(utcMs, launchMs) {
    const date = new Date(utcMs);
    const utc = `${pad(date.getUTCHours(), 2)}:${pad(date.getUTCMinutes(), 2)}:${pad(date.getUTCSeconds(), 2)} UTC`;
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
      timeZoneName: "short",
    }).formatToParts(date);
    const pick = (type) => parts.find((part) => part.type === type).value;
    const eastern = `${pick("hour")}:${pick("minute")}:${pick("second")} ${pick("timeZoneName")}`;
    let met = null;
    if (typeof launchMs === "number" && Number.isFinite(launchMs)) {
      let seconds = Math.round((utcMs - launchMs) / 1000);
      const sign = seconds < 0 ? "-" : "";
      seconds = Math.abs(seconds);
      const hours = Math.floor(seconds / 3600);
      const minutes = Math.floor((seconds % 3600) / 60);
      const secs = seconds % 60;
      met = `${sign}${hours}:${pad(minutes, 2)}:${pad(secs, 2)} MET`;
    }
    return { utc: utc, eastern: eastern, met: met };
  }

  // Drop the control header below the corner clock. clockBottom and hudTop
  // are viewport y positions. The result is the HUD's top padding, in pixels.
  function hudTopPad(clockBottom, hudTop, basePad, gap) {
    const base = Number.isFinite(basePad) ? basePad : 18;
    const air = Number.isFinite(gap) ? gap : 10;
    if (!Number.isFinite(clockBottom) || !Number.isFinite(hudTop)) return base;
    return Math.max(base, Math.ceil(clockBottom - hudTop + air));
  }

  // Last few seconds of a hold. mix is 1 at the incoming frame's own time.
  const HOLD_FADE_MS = 4000;

  function crossfade(now, currentMs, nextMs, fadeMs) {
    const fade = Number.isFinite(fadeMs) && fadeMs > 0 ? fadeMs : HOLD_FADE_MS;
    if (!Number.isFinite(now) || !Number.isFinite(currentMs) || !Number.isFinite(nextMs) || !(nextMs > currentMs)) {
      return { mix: 0, dominant: "current" };
    }
    const windowMs = Math.min(fade, nextMs - currentMs);
    const start = nextMs - windowMs;
    let mix = 0;
    if (now >= nextMs) mix = 1;
    else if (now > start) mix = (now - start) / windowMs;
    return { mix: mix, dominant: mix >= 0.5 ? "next" : "current" };
  }

  // Slow drift across one hold. Scale change stays within 4%.
  function holdMotion(progress, index, floatX, floatY, lookX, lookY) {
    const p = Math.min(1, Math.max(0, Number(progress) || 0));
    const sign = index % 2 === 0 ? -1 : 1;
    const fx = Number.isFinite(floatX) ? floatX : 0;
    const fy = Number.isFinite(floatY) ? floatY : 0;
    const lx = Number.isFinite(lookX) ? lookX : 0;
    const ly = Number.isFinite(lookY) ? lookY : 0;
    return {
      scale: 1.025 + p * 0.035,
      x: sign * p * 0.65 + fx * 0.45 - lx * 0.45,
      y: p * 0.3 + fy * 0.45 - ly * 0.3,
    };
  }

  const GATE_DESKTOP = "Click or press any key to look out the window";
  const GATE_TOUCH = "Tap to begin";

  function gateLabel(touch) {
    return touch ? GATE_TOUCH : GATE_DESKTOP;
  }

  // Dock and the tap gate follow the primary pointer. A fine pointer keeps
  // mousemove reveal even when the screen also reports touch points, which
  // is a touchscreen laptop. Touch points are not an argument.
  function isTouchDevice(coarse, hoverNone, fine) {
    if (fine === true) return false;
    return coarse === true || hoverNone === true;
  }

  // Horizontal swipe between the two windows. A short drag, a vertical drag,
  // and a pinch (more than one finger — the caller passes null) do nothing.
  function swipeWindow(dx, dy, threshold) {
    const limit = Number.isFinite(threshold) && threshold > 0 ? threshold : 48;
    if (!Number.isFinite(dx) || !Number.isFinite(dy)) return null;
    if (Math.abs(dx) < limit || Math.abs(dx) <= Math.abs(dy)) return null;
    return dx < 0 ? "3" : "2";
  }

  // Sibling of the shipped WebP. Same exposure, long edge 720. Never a new file name
  // for a non-image, and never a second downscale of an existing 720 sibling.
  function variantFile(file, useSmall) {
    if (!useSmall || typeof file !== "string") return file;
    if (!/\.webp$/i.test(file) || /\.720\.webp$/i.test(file)) return file;
    return file.replace(/\.webp$/i, ".720.webp");
  }

  function wantsSmallImage(narrow, saveData, effectiveType, fold) {
    if (saveData === true) return true;
    if (effectiveType === "slow-2g" || effectiveType === "2g" || effectiveType === "3g") return true;
    // The open fold, including a Duo at 3x, keeps the shipped 1200 px frame.
    // The window is about 570 CSS px wide; at 3x that is ~1700 device pixels,
    // so the 720 sibling would be the blurrier source. A slow link still
    // stays on the smaller sibling.
    if (fold === true) return false;
    if (narrow) return true;
    return false;
  }

  // An open fold is wider than tall, tall enough not to be a phone on its
  // side, and narrower than a desktop. 6/5 is 1.2, 8/5 is 1.6. That shape
  // is also a 1024×768 desktop window, so the fold layout requires a coarse
  // pointer. Phone and desktop here describe the shape; the page applies
  // the phone rules only under (pointer: coarse) as well.
  function screenMode(width, height, coarse) {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return "desktop";
    const aspect = width / height;
    if (coarse === true && aspect >= 1.2 && aspect <= 1.6 && height >= 520 && width <= 1200) return "fold";
    if (aspect < 1 || height <= 500) return "phone";
    return "desktop";
  }

  // Real transcript rows already in the timeline. Nothing is added.
  function transcriptSlice(lines, utcMs, track, beforeMs, afterMs) {
    const before = Number.isFinite(beforeMs) ? beforeMs : 25000;
    const after = Number.isFinite(afterMs) ? afterMs : 12000;
    if (!Array.isArray(lines) || !Number.isFinite(utcMs)) return [];
    const rows = [];
    for (const line of lines) {
      if (!line || typeof line.utc !== "string" || typeof line.text !== "string") continue;
      if (track && line.track !== track) continue;
      const t = Date.parse(line.utc);
      if (!Number.isFinite(t) || t < utcMs - before || t > utcMs + after) continue;
      rows.push({ utc: line.utc, t: t, speaker: line.speaker || "", text: line.text });
    }
    rows.sort((a, b) => a.t - b.t);
    let currentUtc = null;
    for (const row of rows) {
      if (row.t <= utcMs) currentUtc = row.utc;
    }
    return rows.map((row) => ({
      utc: row.utc,
      speaker: row.speaker,
      text: row.text,
      current: row.utc === currentUtc,
    }));
  }

  // Cellular waits for the tap before the other window and the first recording.
  function prefetchBeforeTap(cellular) {
    return {
      opener: true,
      otherWindow: !cellular,
      audio: !cellular,
    };
  }

  return {
    project: project,
    placeLabels: placeLabels,
    chooseFont: chooseFont,
    formatClocks: formatClocks,
    overlap: overlap,
    hudTopPad: hudTopPad,
    crossfade: crossfade,
    holdMotion: holdMotion,
    HOLD_FADE_MS: HOLD_FADE_MS,
    GATE_DESKTOP: GATE_DESKTOP,
    GATE_TOUCH: GATE_TOUCH,
    gateLabel: gateLabel,
    isTouchDevice: isTouchDevice,
    swipeWindow: swipeWindow,
    variantFile: variantFile,
    wantsSmallImage: wantsSmallImage,
    prefetchBeforeTap: prefetchBeforeTap,
    screenMode: screenMode,
    transcriptSlice: transcriptSlice,
  };
});
