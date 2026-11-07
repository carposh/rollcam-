// The film look, rendered once at develop time on a canvas:
// warm cast, slight saturation, faded blacks, vignette, grain, light leaks, date stamp.
const MAX_LONG_EDGE = 2400;
const THUMB_WIDTH = 480;

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

async function loadImage(blob) {
  if (window.createImageBitmap) {
    try { return await createImageBitmap(blob); } catch { /* fall through */ }
  }
  const url = URL.createObjectURL(blob);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    return img;
  } finally {
    URL.revokeObjectURL(url);
  }
}

const toBlob = (canvas, q) => new Promise((res) => canvas.toBlob(res, 'image/jpeg', q));

// Contrast/brightness + fade tone curve in one lookup table.
function buildLUT() {
  const pts = [[0, 0.07], [0.25, 0.25], [0.5, 0.52], [0.75, 0.77], [1, 0.95]];
  const lut = new Uint8ClampedArray(256);
  for (let v = 0; v < 256; v++) {
    let x = (v / 255 - 0.5) * 1.04 + 0.5 + 0.01;
    x = Math.min(1, Math.max(0, x));
    let j = 0;
    while (j < pts.length - 2 && x > pts[j + 1][0]) j++;
    const [x0, y0] = pts[j], [x1, y1] = pts[j + 1];
    lut[v] = Math.round((y0 + ((y1 - y0) * (x - x0)) / (x1 - x0)) * 255);
  }
  return lut;
}
const LUT = buildLUT();
const c255 = (v) => (v < 0 ? 0 : v > 255 ? 255 : v | 0);

function filmPass(d, W, H, rand) {
  const cx = W / 2, cy = H / 2, maxD = Math.hypot(cx, cy);
  const grainAmp = 15;
  let i = 0;
  for (let y = 0; y < H; y++) {
    const dy = (y - cy) / maxD, dy2 = dy * dy;
    for (let x = 0; x < W; x++, i += 4) {
      const r = d[i], g = d[i + 1], b = d[i + 2];
      // warm colour matrix
      let r1 = 1.06 * r + 0.05 * g + 6.4;
      let g1 = 0.02 * r + 0.99 * g + 0.01 * b + 3.1;
      let b1 = 0.04 * g + 0.84 * b;
      // saturation
      const l = 0.2126 * r1 + 0.7152 * g1 + 0.0722 * b1;
      r1 = l + (r1 - l) * 1.08; g1 = l + (g1 - l) * 1.08; b1 = l + (b1 - l) * 1.08;
      // contrast + fade
      const R = LUT[c255(r1)], G = LUT[c255(g1)], B = LUT[c255(b1)];
      // vignette
      const dx = (x - cx) / maxD, dist = Math.sqrt(dx * dx + dy2);
      let v = 1;
      if (dist > 0.42) { const t = (dist - 0.42) / 0.58; v = 1 - 0.5 * t * t * (3 - 2 * t); }
      // monochrome grain, strongest in the midtones
      const lum = R * 0.3 + G * 0.59 + B * 0.11;
      const n = (rand() + rand() - 1) * grainAmp * (1 - Math.abs(lum - 128) / 190);
      d[i] = R * v + n; d[i + 1] = G * v + n; d[i + 2] = B * v + n;
    }
  }
}

function lightLeak(g, W, H, rand) {
  const fromLeft = rand() < 0.5;
  const x = fromLeft ? -W * 0.05 : W * 1.05;
  const y = H * (0.15 + rand() * 0.7);
  const reach = W * (0.35 + rand() * 0.35);
  g.save();
  g.globalCompositeOperation = 'screen';
  const glow = (cx, cy, radius, rgb, alpha) => {
    const grad = g.createRadialGradient(cx, cy, 0, cx, cy, radius);
    grad.addColorStop(0, `rgba(${rgb},${alpha})`);
    grad.addColorStop(1, `rgba(${rgb},0)`);
    g.fillStyle = grad;
    g.fillRect(0, 0, W, H);
  };
  glow(x, y, reach, '255,82,20', 0.85);
  glow(x, y + H * 0.08, reach * 0.55, '255,184,64', 0.55);
  g.restore();
}

function dateStamp(g, W, H, time) {
  const d = new Date(time);
  const text = `'${String(d.getFullYear()).slice(-2)} ${d.getMonth() + 1} ${d.getDate()}`;
  const size = Math.round(H * 0.045);
  const margin = W * 0.045;
  g.save();
  g.font = `600 ${size}px ui-monospace, "SF Mono", Menlo, Consolas, monospace`;
  g.textAlign = 'right';
  g.textBaseline = 'bottom';
  if ('letterSpacing' in g) g.letterSpacing = `${Math.round(size * 0.08)}px`;
  g.shadowColor = 'rgba(255,90,0,0.9)';
  g.shadowBlur = size * 0.35;
  g.fillStyle = 'rgba(255,140,30,0.95)';
  g.fillText(text, W - margin, H - margin);
  g.restore();
}

/** Develops one frame. Returns { print, thumb } as JPEG Blobs. */
export async function develop(original, { dateStamp: stamp, capturedAt, seed }) {
  const rand = mulberry32(seed);
  const src = await loadImage(original);
  const sw0 = src.width, sh0 = src.height;

  // Print exactly the 3:2 landscape window the viewfinder showed.
  let sw = sw0, sh = sh0;
  if (sw0 / sh0 > 1.5) sw = Math.round(sh0 * 1.5); else sh = Math.round(sw0 / 1.5);
  const sx = Math.round((sw0 - sw) / 2), sy = Math.round((sh0 - sh) / 2);
  const scale = Math.min(1, MAX_LONG_EDGE / Math.max(sw, sh));
  const W = Math.round(sw * scale), H = Math.round(sh * scale);

  const canvas = document.createElement('canvas');
  canvas.width = W;
  canvas.height = H;
  const g = canvas.getContext('2d', { willReadFrequently: true });
  g.drawImage(src, sx, sy, sw, sh, 0, 0, W, H);
  if (src.close) src.close();

  if (rand() < 0.3) lightLeak(g, W, H, rand);
  const img = g.getImageData(0, 0, W, H);
  filmPass(img.data, W, H, rand);
  g.putImageData(img, 0, 0);
  if (stamp) dateStamp(g, W, H, capturedAt);

  const print = await toBlob(canvas, 0.9);

  const tw = THUMB_WIDTH, th = Math.round((THUMB_WIDTH * H) / W);
  const tc = document.createElement('canvas');
  tc.width = tw;
  tc.height = th;
  tc.getContext('2d').drawImage(canvas, 0, 0, tw, th);
  const thumb = await toBlob(tc, 0.8);

  canvas.width = canvas.height = 0; // release memory promptly on iOS
  tc.width = tc.height = 0;
  return { print, thumb };
}
