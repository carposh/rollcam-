import * as db from './db.js';
import * as vault from './vault.js';
import * as lab from './labclock.js';
import * as haptics from './haptics.js';
import { develop } from './film.js';
import { Camera } from './camera.js';

const BUILD = '__BUILD__';

// ---------- helpers ----------
const $ = (sel, root = document) => root.querySelector(sel);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pad2 = (n) => String(n).padStart(2, '0');
const uuid = () => (crypto.randomUUID ? crypto.randomUUID()
  : ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16)));

function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else if (k === 'text') el.textContent = v;
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

const ICONS = {
  box: '<svg viewBox="0 0 24 24"><path d="M3 7h18v13H3zM3 7l2-3h14l2 3M9 11h6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
  film: '<svg viewBox="0 0 24 24"><rect x="4" y="3" width="16" height="18" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 3v18M16 3v18M4 8h4M4 13h4M4 18h4M16 8h4M16 13h4M16 18h4" stroke="currentColor" stroke-width="1.4"/></svg>',
  close: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  share: '<svg viewBox="0 0 24 24"><path d="M12 3v12M7.5 7.5 12 3l4.5 4.5M5 12v8h14v-8" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>',
};

// ---------- settings ----------
const DURATIONS = [
  { ms: 3600e3, label: '1 hour' },
  { ms: 12 * 3600e3, label: '12 hours' },
  { ms: 24 * 3600e3, label: '24 hours' },
  { ms: 72 * 3600e3, label: '3 days' },
];
const settings = {
  get developMs() { return Number(localStorage.getItem('developMs')) || 24 * 3600e3; },
  set developMs(v) { localStorage.setItem('developMs', String(v)); },
  get dateStamp() { return localStorage.getItem('dateStamp') !== '0'; },
  set dateStamp(v) { localStorage.setItem('dateStamp', v ? '1' : '0'); },
};

// ---------- state ----------
const state = {
  rolls: [],
  printing: new Map(), // rollId -> progress 0..1
  flash: false,
  capturing: false,
  sheetCleanup: null,
};
const camera = new Camera($('#video'));

const isFull = (r) => r.frames.length >= r.capacity;
const remaining = (r) => Math.max(0, r.capacity - r.frames.length);
const activeRoll = () => state.rolls.find((r) => r.status === 'loaded');
const labRolls = () => state.rolls.filter((r) => r.status === 'atLab').sort((a, b) => b.lab.sentAt - a.lab.sentAt);
const developedRolls = () => state.rolls.filter((r) => r.status === 'developed').sort((a, b) => b.developedAt - a.developedAt);
const blobKey = {
  latent: (rollId, frameId) => `${rollId}/latent/${frameId}`,
  print: (rollId, i) => `${rollId}/print/${pad2(i + 1)}`,
  thumb: (rollId, i) => `${rollId}/thumb/${pad2(i + 1)}`,
};
const seedFrom = (id) => parseInt(id.replace(/-/g, '').slice(0, 8), 16) >>> 0;
const saveRoll = (r) => db.put('rolls', r);

// ---------- toast & confirm ----------
let toastTimer;
function toast(message, ms = 3800) {
  const el = $('#toast');
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), ms);
}

function confirmBox(title, message, buttons) {
  return new Promise((resolve) => {
    const overlay = h('div', { class: 'confirm' },
      h('div', { class: 'confirm-box', role: 'alertdialog', 'aria-label': title },
        h('h3', { text: title }),
        message ? h('p', { text: message }) : null,
        buttons.map((b) => h('button', {
          type: 'button',
          class: [b.destructive && 'destructive', b.bold && 'bold'].filter(Boolean).join(' '),
          text: b.label,
          onclick: () => { overlay.remove(); resolve(b.value); },
        }))));
    document.body.append(overlay);
  });
}

// ---------- shooting ----------
async function loadFilm(capacity, dateStamp) {
  if (activeRoll()) return;
  const roll = {
    id: uuid(), capacity, createdAt: Date.now(), dateStamp,
    frames: [], status: 'loaded', isWound: false, discarded: 0, lab: null, developedAt: null,
  };
  state.rolls.push(roll);
  await saveRoll(roll);
  wheel.reset();
  render();
}

async function markWound() {
  const r = activeRoll();
  if (!r || r.isWound || isFull(r)) return;
  r.isWound = true;
  await saveRoll(r);
  render();
}

async function fire() {
  const r = activeRoll();
  if (!r || isFull(r) || state.capturing) return;
  if (!r.isWound) {
    haptics.warn();
    wheel.nudge();
    return;
  }
  if (!camera.ready) {
    toast('Rollcam needs the camera. Allow camera access for this site, then try again.');
    startCamera();
    return;
  }
  state.capturing = true;
  haptics.heavy();
  const curtain = $('#curtain');
  curtain.classList.add('closed');
  const screenFlash = state.flash && !camera.torchSupported;
  let blob = null;
  try {
    if (screenFlash) { $('#screenflash').classList.add('on'); await sleep(220); }
    blob = await camera.capture({ torch: state.flash && camera.torchSupported });
  } catch (e) {
    console.error(e);
  } finally {
    $('#screenflash').classList.remove('on');
  }
  if (blob) {
    try {
      const frame = { id: uuid(), capturedAt: Date.now() };
      const sealed = await vault.seal(await blob.arrayBuffer());
      await db.set('blobs', blobKey.latent(r.id, frame.id), sealed);
      r.frames.push(frame);
      r.isWound = false;
      await saveRoll(r);
      wheel.reset();
    } catch (e) {
      console.error(e);
      toast("That frame didn't make it onto the film. Try again.");
    }
  } else {
    toast('The shutter jammed. Try again.');
  }
  setTimeout(() => curtain.classList.remove('closed'), 90);
  state.capturing = false;
  render();
}

async function sendToLab() {
  const r = activeRoll();
  if (!r) return;
  if (!r.frames.length) {
    await deleteRoll(r);
    return;
  }
  r.discarded = remaining(r);
  r.isWound = false;
  r.status = 'atLab';
  r.lab = lab.newTicket(settings.developMs);
  await saveRoll(r);
  haptics.success();
  render();
}

async function deleteRoll(r) {
  state.rolls = state.rolls.filter((x) => x.id !== r.id);
  await db.del('rolls', r.id);
  await db.delPrefix('blobs', `${r.id}/`);
  render();
}

// ---------- the lab ----------
async function refresh() {
  let tamperSeen = false;
  for (const r of labRolls()) {
    const before = r.lab.tamperCount;
    if (lab.advance(r.lab)) await saveRoll(r);
    if (r.lab.tamperCount !== before) tamperSeen = true;
    if (lab.isReady(r.lab)) printRoll(r);
  }
  render();
  if (tamperSeen) labView.redraw?.();
}

async function printRoll(r) {
  if (state.printing.has(r.id)) return;
  state.printing.set(r.id, 0);
  labView.redraw?.();
  try {
    for (let i = 0; i < r.frames.length; i++) {
      const f = r.frames[i];
      try {
        const sealed = await db.get('blobs', blobKey.latent(r.id, f.id));
        if (sealed) {
          const raw = await vault.open(sealed);
          const { print, thumb } = await develop(new Blob([raw], { type: 'image/jpeg' }), {
            dateStamp: r.dateStamp, capturedAt: f.capturedAt, seed: seedFrom(f.id),
          });
          await db.set('blobs', blobKey.print(r.id, i), await print.arrayBuffer());
          await db.set('blobs', blobKey.thumb(r.id, i), await thumb.arrayBuffer());
        }
      } catch (e) {
        console.error('Frame failed to develop', i, e);
      }
      state.printing.set(r.id, (i + 1) / r.frames.length);
      labView.progress?.(r.id);
      await sleep(0);
    }
    r.status = 'developed';
    r.developedAt = Date.now();
    await saveRoll(r);
    await db.delPrefix('blobs', `${r.id}/latent/`);
    haptics.success();
    toast(`Your roll is back from the lab: ${r.frames.length} photo${r.frames.length === 1 ? '' : 's'}.`);
  } finally {
    state.printing.delete(r.id);
    render();
    labView.redraw?.();
  }
}

/** No push server, so the "notification" is a calendar event with an alert. */
function calendarReminder(r) {
  const ready = new Date(Date.now() + lab.remaining(r.lab));
  const stamp = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
  const ics = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Rollcam//EN', 'BEGIN:VEVENT',
    `UID:${r.id}@rollcam`, `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(ready)}`, `DTEND:${stamp(new Date(ready.getTime() + 15 * 60e3))}`,
    'SUMMARY:Rollcam: your roll is developed', 'DESCRIPTION:Open Rollcam to pick up your photos.',
    `URL:${location.href.split('#')[0]}`,
    'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:Your Rollcam roll is developed', 'TRIGGER:PT0M', 'END:VALARM',
    'END:VEVENT', 'END:VCALENDAR',
  ].join('\r\n');
  const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }));
  const a = h('a', { href: url, download: 'rollcam-roll.ics' });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

// ---------- thumbwheel ----------
const wheel = (() => {
  const el = $('#wheel'), ridges = $('#ridges'), meter = $('#wheel-meter');
  const STEP = 14, NEEDED = 8, PITCH = 7;
  let startY = null, stepsThisDrag = 0, notches = 0, spin = 0;

  const needsWind = () => { const r = activeRoll(); return !!r && !r.isWound && !isFull(r); };
  const paint = () => {
    ridges.style.transform = `translateY(${((spin % PITCH) + PITCH) % PITCH}px)`;
    meter.style.opacity = needsWind() ? String(1 - notches / NEEDED) : '0';
  };

  el.addEventListener('pointerdown', (e) => {
    startY = e.clientY;
    stepsThisDrag = 0;
    el.setPointerCapture?.(e.pointerId);
  });
  el.addEventListener('pointermove', (e) => {
    if (startY == null || !needsWind()) return;
    const dy = e.clientY - startY;
    const steps = Math.floor(Math.abs(dy) / STEP);
    while (stepsThisDrag < steps && notches < NEEDED) {
      stepsThisDrag++;
      notches++;
      spin += dy >= 0 ? STEP : -STEP;
      haptics.tick();
    }
    paint();
    if (notches >= NEEDED) {
      notches = 0;
      startY = null;
      haptics.heavy();
      markWound();
    }
  });
  const end = () => { startY = null; };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
  el.addEventListener('keydown', (e) => {
    if (['ArrowUp', 'ArrowDown', ' ', 'Enter'].includes(e.key) && needsWind()) {
      e.preventDefault();
      markWound();
    }
  });

  return {
    reset() { notches = 0; paint(); },
    nudge() { el.classList.remove('nudge'); void el.offsetWidth; el.classList.add('nudge'); },
    paint,
  };
})();

// ---------- camera screen ----------
function render() {
  const r = activeRoll();
  const needsWind = !!r && !r.isWound && !isFull(r);
  $('#counter').textContent = r ? String(remaining(r)) : '–';
  $('#wrap-exp').textContent = r ? `${r.capacity} EXP` : 'NO FILM';
  const status = $('#wrap-status');
  status.textContent = needsWind ? 'WIND ▲▼' : r && isFull(r) ? 'ROLL FULL' : 'ISO 400';
  status.classList.toggle('alert', needsWind);
  $('#wheel').classList.toggle('needs-wind', needsWind);
  wheel.paint();
  $('#btn-early').hidden = !r;

  const badge = $('#lab-badge');
  const n = labRolls().length;
  badge.hidden = n === 0;
  badge.textContent = String(n);

  const flash = $('#btn-flash');
  flash.classList.toggle('on', state.flash);
  $('#flash-label').textContent = state.flash ? (camera.torchSupported ? 'FLASH ON' : 'SCREEN FLASH') : 'FLASH OFF';

  $('#btn-load').hidden = !!r;
  $('#btn-send').hidden = !(r && isFull(r));
  const shutter = $('#btn-shutter');
  shutter.hidden = !(r && !isFull(r));
  shutter.classList.toggle('armed', !!r && r.isWound && !state.capturing);
  shutter.setAttribute('aria-label', r && !r.isWound ? 'Shutter (wind the film first)' : 'Shutter');
}

function finderMessage(text) {
  const el = $('#finder-msg');
  el.hidden = !text;
  el.textContent = text || '';
}

async function startCamera() {
  try {
    await camera.start();
    finderMessage(null);
  } catch (e) {
    finderMessage(e.name === 'NotAllowedError' ? 'Camera blocked. Allow it for this site.' : 'No camera');
  }
  render();
}

// ---------- sheets ----------
function closeSheet() {
  const s = $('#sheet');
  if (s) s.remove();
  const cleanup = state.sheetCleanup;
  state.sheetCleanup = null;
  cleanup?.();
}

function openSheet(title, body, { left = null, right = null, onClose = null } = {}) {
  closeSheet();
  const backdrop = h('div', { class: 'sheet', id: 'sheet' },
    h('div', { class: 'sheet-panel', role: 'dialog', 'aria-label': title },
      h('header', { class: 'sheet-head' },
        left,
        h('h2', { text: title }),
        right,
        h('button', { class: 'link', type: 'button', text: 'Done', onclick: closeSheet })),
      h('div', { class: 'sheet-body' }, body)));
  backdrop.addEventListener('click', (e) => { if (e.target === backdrop) closeSheet(); });
  document.body.append(backdrop);
  requestAnimationFrame(() => backdrop.classList.add('open'));
  state.sheetCleanup = onClose;
}

function segmented(options, value, onChange) {
  const wrap = h('div', { class: 'seg', role: 'radiogroup' });
  const draw = (v) => {
    wrap.replaceChildren(...options.map((o) => h('button', {
      type: 'button', role: 'radio', 'aria-checked': String(o.value === v),
      class: o.value === v ? 'on' : '', text: o.label,
      onclick: () => { draw(o.value); onChange(o.value); },
    })));
  };
  draw(value);
  return wrap;
}

function toggle(label, value, onChange) {
  let on = value;
  const sw = h('button', { type: 'button', role: 'switch', class: `toggle${on ? ' on' : ''}`, 'aria-checked': String(on), 'aria-label': label });
  sw.addEventListener('click', () => {
    on = !on;
    sw.classList.toggle('on', on);
    sw.setAttribute('aria-checked', String(on));
    onChange(on);
  });
  return h('div', { class: 'card toggle-row' }, h('span', { text: label }), sw);
}

function showLoadFilm() {
  let capacity = 24, stamp = settings.dateStamp;
  const body = h('div', {},
    h('div', { class: 'section-title', text: 'Exposures' }),
    segmented([{ value: 24, label: '24 exposures' }, { value: 36, label: '36 exposures' }], capacity, (v) => { capacity = v; }),
    h('p', { class: 'note', text: "You won't see a single photo until the whole roll is developed." }),
    h('div', { class: 'section-title', text: 'Options' }),
    toggle('Orange date stamp', stamp, (v) => { stamp = v; }),
    h('button', {
      type: 'button', class: 'big yellow', style: 'margin-top:14px', text: 'Load film',
      onclick: async () => { closeSheet(); await loadFilm(capacity, stamp); haptics.heavy(); },
    }));
  openSheet('Load film', body);
}

function showSettings() {
  const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone;
  const body = h('div', {},
    h('div', { class: 'section-title', text: 'Developing time' }),
    segmented(DURATIONS.map((d) => ({ value: d.ms, label: d.label })), settings.developMs, (v) => { settings.developMs = v; }),
    h('p', { class: 'note', text: 'Applies to the next roll you send. Rolls already at the lab keep their time.' }),
    h('div', { class: 'section-title', text: 'New rolls' }),
    toggle('Date stamp', settings.dateStamp, (v) => { settings.dateStamp = v; }),
    h('div', { class: 'section-title', text: 'How the lab works' }),
    h('div', { class: 'card prose' },
      h('p', { html: 'Photos are <b>encrypted inside Rollcam</b> until they are developed. They never appear in your Photos library unless you save them.' }),
      h('p', { html: 'Only real time counts. If the phone\'s clock is <b>turned back</b>, the lab notices and doesn\'t credit it.' }),
      h('p', { html: 'A website can\'t send a notification when it\'s closed, so use <b>Remind me</b> on a roll at the lab to add a calendar alert.' }),
      standalone ? null : h('p', { html: '<b>Add Rollcam to your Home Screen</b> (Share ▸ Add to Home Screen). Safari can clear website data you haven\'t opened in 7 days, and that would include your rolls. Home Screen apps are kept.' })),
    h('p', { class: 'note', text: `Rollcam web · build ${BUILD}` }));
  openSheet('Settings', body);
}

const labView = { redraw: null, progress: null };

function showLab() {
  closeSheet(); // run the previous sheet's cleanup before creating new object URLs
  const body = h('div');
  const draw = () => {
    const at = labRolls(), dev = developedRolls();
    body.replaceChildren();
    if (!at.length && !dev.length) {
      body.append(h('div', { class: 'empty', html: `${ICONS.film}<p>No rolls yet.<br>Finish a roll and send it to the lab.</p>` }));
      return;
    }
    if (at.length) {
      body.append(h('div', { class: 'section-title', text: 'At the lab' }));
      at.forEach((r) => body.append(labRow(r)));
    }
    if (dev.length) {
      body.append(h('div', { class: 'section-title', text: 'Developed' }));
      dev.forEach((r) => body.append(developedRow(r)));
    }
  };
  draw();
  const timer = setInterval(() => {
    body.querySelectorAll('[data-countdown]').forEach((el) => {
      const r = state.rolls.find((x) => x.id === el.dataset.countdown);
      if (r?.lab) el.textContent = countdownText(r);
    });
  }, 1000);
  openSheet('Lab', body, {
    onClose: () => { clearInterval(timer); labView.redraw = null; labView.progress = null; revokeAll(); },
  });
  labView.redraw = draw;
  labView.progress = (id) => {
    const bar = body.querySelector(`[data-progress="${id}"] i`);
    if (bar) bar.style.width = `${Math.round((state.printing.get(id) || 0) * 100)}%`;
  };
}

function countdownText(r) {
  const left = lab.remaining(r.lab);
  return left > 0 ? `Ready in ${lab.format(left)}` : 'Coming out of the developer…';
}

function labRow(r) {
  const printing = state.printing.has(r.id);
  return h('div', { class: 'card' },
    h('div', { class: 'row' },
      h('div', { class: 'box', html: ICONS.box }),
      h('div', { class: 'main' },
        h('h4', { text: `${r.frames.length} exposure${r.frames.length === 1 ? '' : 's'}` }),
        printing
          ? h('div', {}, h('div', { class: 'sub', text: 'Printing…' }),
            h('div', { class: 'bar', 'data-progress': r.id }, h('i', { style: `width:${Math.round(state.printing.get(r.id) * 100)}%` })))
          : h('div', { class: 'sub', 'data-countdown': r.id, text: countdownText(r) }),
        r.lab.tamperCount > 0 ? h('div', { class: 'warn', text: '⚠︎ The lab noticed the clock going backwards. Only real time counts.' }) : null,
        r.discarded > 0 ? h('div', { class: 'fine', text: `Developed early · ${r.discarded} unused shots discarded` }) : null,
        printing ? null : h('button', { type: 'button', class: 'small-btn', text: '⏰ Remind me', onclick: () => calendarReminder(r) }))));
}

// Object URLs for thumbnails/prints, released when the sheet closes.
let liveURLs = [];
const objectURL = (buf) => { const u = URL.createObjectURL(new Blob([buf], { type: 'image/jpeg' })); liveURLs.push(u); return u; };
const revokeAll = () => { liveURLs.forEach((u) => URL.revokeObjectURL(u)); liveURLs = []; };

function developedRow(r) {
  const img = h('img', { class: 'thumb-sm', alt: '' });
  db.get('blobs', blobKey.thumb(r.id, 0)).then((buf) => { if (buf) img.src = objectURL(buf); });
  const when = new Date(r.createdAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
  return h('button', { type: 'button', class: 'card row', onclick: () => showRoll(r) },
    img,
    h('div', { class: 'main' }, h('h4', { text: when }), h('div', { class: 'sub', text: `${r.frames.length} photos` })),
    h('span', { class: 'chev', text: '›' }));
}

async function showRoll(r) {
  closeSheet();
  const dateTag = new Date(r.createdAt).toISOString().slice(0, 10);
  const items = [];
  for (let i = 0; i < r.frames.length; i++) {
    const buf = await db.get('blobs', blobKey.print(r.id, i));
    if (!buf) continue;
    const thumbBuf = await db.get('blobs', blobKey.thumb(r.id, i));
    items.push({
      file: new File([buf], `Rollcam-${dateTag}-${pad2(i + 1)}.jpg`, { type: 'image/jpeg' }),
      full: objectURL(buf),
      thumb: thumbBuf ? objectURL(thumbBuf) : null,
    });
  }

  const grid = h('div', { class: 'grid' }, items.map((it, i) =>
    h('button', { type: 'button', 'aria-label': `Photo ${i + 1}`, onclick: () => openViewer(items, i) },
      h('img', { src: it.thumb || it.full, alt: '', loading: 'lazy' }))));
  const body = h('div', {},
    items.length ? grid : h('div', { class: 'empty', text: 'Nothing came out on this roll.' }),
    items.length ? h('button', {
      type: 'button', class: 'big orange', style: 'margin-top:16px', text: `Save all ${items.length} to Photos`,
      onclick: () => shareFiles(items.map((it) => it.file)),
    }) : null,
    h('p', { class: 'note', text: 'On iPhone, choose “Save Images” in the share sheet.' }),
    h('button', {
      type: 'button', class: 'small-btn', style: 'margin-top:18px;color:#ff6b57', text: 'Delete roll',
      onclick: async () => {
        const ok = await confirmBox('Delete this roll?', "Photos you've already saved to Photos stay there.",
          [{ label: 'Delete roll', value: true, destructive: true }, { label: 'Cancel', value: false, bold: true }]);
        if (ok) { await deleteRoll(r); showLab(); }
      },
    }));

  const when = new Date(r.createdAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  openSheet(when, body, {
    left: h('button', { type: 'button', class: 'link', text: '‹ Lab', onclick: () => showLab() }),
    onClose: revokeAll,
  });
}

/** iOS share sheet ("Save Images" puts them in Photos). Falls back to downloads. */
async function shareFiles(files) {
  if (navigator.canShare && navigator.canShare({ files })) {
    try {
      await navigator.share({ files });
    } catch (e) {
      if (e.name !== 'AbortError') toast("Couldn't open the share sheet. Try fewer photos at a time.");
    }
    return;
  }
  for (const f of files) {
    const url = URL.createObjectURL(f);
    const a = h('a', { href: url, download: f.name });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
    await sleep(300);
  }
}

function openViewer(items, start) {
  let index = start;
  const pages = items.map(() => h('div', { class: 'viewer-page' }, h('img', { alt: '' })));
  const strip = h('div', { class: 'viewer-strip' }, pages);
  const count = h('span', { class: 'viewer-count glass' });
  const viewer = h('div', { class: 'viewer', role: 'dialog', 'aria-label': 'Photo viewer' },
    strip,
    h('div', { class: 'viewer-bar' },
      h('button', { type: 'button', class: 'icon glass', 'aria-label': 'Close', html: ICONS.close, onclick: () => viewer.remove() }),
      count,
      h('button', { type: 'button', class: 'icon glass', 'aria-label': 'Share', html: ICONS.share, onclick: () => shareFiles([items[index].file]) })));

  // Only decode the current photo and its neighbours: full prints are big on a phone.
  const load = () => {
    pages.forEach((p, i) => {
      const img = p.firstChild;
      if (Math.abs(i - index) <= 1) { if (img.getAttribute('src') !== items[i].full) img.src = items[i].full; }
      else img.removeAttribute('src');
    });
    count.textContent = `${index + 1} / ${items.length}`;
  };
  strip.addEventListener('scroll', () => {
    const i = Math.round(strip.scrollLeft / strip.clientWidth);
    if (i !== index && i >= 0 && i < items.length) { index = i; load(); }
  }, { passive: true });

  document.body.append(viewer);
  strip.scrollLeft = start * strip.clientWidth;
  load();
}

// ---------- wiring ----------
$('#btn-load').addEventListener('click', showLoadFilm);
$('#btn-send').addEventListener('click', async () => { await sendToLab(); showLab(); });
$('#btn-shutter').addEventListener('click', fire);
$('#btn-lab').addEventListener('click', showLab);
$('#btn-settings').addEventListener('click', showSettings);
$('#btn-flash').addEventListener('click', () => { state.flash = !state.flash; haptics.tick(); render(); });
$('#btn-flip').addEventListener('click', async () => {
  haptics.tick();
  try { await camera.flip(); finderMessage(null); } catch { finderMessage('No camera'); }
  render();
});
$('#btn-early').addEventListener('click', async () => {
  const r = activeRoll();
  if (!r) return;
  const empty = r.frames.length === 0;
  const ok = await confirmBox('End this roll now?',
    empty ? 'Nothing has been shot on this roll.'
      : `The ${remaining(r)} unused exposures will be thrown away. Developing still takes the normal time.`,
    [{ label: empty ? 'Throw away this roll' : `Send ${r.frames.length} shots to the lab`, value: true, destructive: true },
      { label: 'Keep shooting', value: false, bold: true }]);
  if (ok) {
    await sendToLab();
    if (!empty) showLab();
  }
});

document.addEventListener('visibilitychange', () => {
  if (document.hidden) camera.stop();
  else { startCamera(); refresh(); }
});
setInterval(refresh, 15000);

async function boot() {
  try {
    state.rolls = await db.getAll('rolls');
  } catch (e) {
    console.error(e);
    toast("Rollcam can't store photos in this browser (private browsing?).", 8000);
  }
  render();
  refresh();
  startCamera();
  if (navigator.storage?.persist) navigator.storage.persist().catch(() => {});
  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
}

boot();
