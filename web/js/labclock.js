// Light anti-cheat for developing time, browser edition.
//
// Only wall-clock time *beyond the latest moment we have ever seen* counts towards developing.
// Winding the clock back is detected (and earns nothing); winding it back and forward again
// cannot re-credit the same hours. A browser has no tamper-proof clock, so a forward jump
// cannot be told apart from real time passing.
export const TOLERANCE = 2 * 60 * 1000;

export function newTicket(durationMs, now = Date.now()) {
  return { sentAt: now, duration: durationMs, credited: 0, highWater: now, tamperCount: 0, clockBehind: false, lastTamperAt: null };
}

/** Mutates the ticket. Returns true if something changed. */
export function advance(t, now = Date.now()) {
  if (now < t.highWater - TOLERANCE) {
    if (!t.clockBehind) {
      t.clockBehind = true;
      t.tamperCount += 1;
      t.lastTamperAt = now;
      return true;
    }
    return false;
  }
  if (now > t.highWater) {
    t.credited = Math.min(t.duration, t.credited + (now - t.highWater));
    t.highWater = now;
    t.clockBehind = false;
    return true;
  }
  return false;
}

export const isReady = (t) => t.credited >= t.duration;

export function remaining(t, now = Date.now()) {
  const pending = now > t.highWater ? now - t.highWater : 0;
  return Math.max(0, t.duration - t.credited - pending);
}

export function format(ms) {
  const s = Math.max(0, Math.ceil(ms / 1000));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}
