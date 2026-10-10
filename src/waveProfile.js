// Procedural breaking-wave profile.
//
// The wave is modelled in the frame of the peel point (the spot where the lip
// is pitching). Along-crest distance from the peel is `u` (positive = ahead,
// toward the unbroken shoulder). For each `u` the cross-section is a single
// continuous curve running from the flat water on the shore side, through the
// trough, up the face, over the tube ceiling, down the pitching lip, around the
// lip tip, back over the top of the lip, down the back of the wave and out to
// flat water on the sea side. Because the lip is just a fold in that curve,
// one mesh can go from an unbroken swell to a full tube to whitewater.
//
// Coordinates: z points toward shore (the face looks +z), y is up.
// Keypoints are [z, y, translucency, foam]. Values are multiplied by the wave
// height H except the two far keypoints, which are absolute.

const SWELL = [
  [40, 0, 0.05, 0], [4.2, -0.02, 0.05, 0], [2.6, -0.06, 0.05, 0], [1.7, 0.08, 0.08, 0],
  [1.05, 0.33, 0.08, 0], [0.55, 0.58, 0.14, 0], [0.25, 0.68, 0.22, 0], [0.08, 0.71, 0.32, 0],
  [0.0, 0.72, 0.34, 0], [-0.04, 0.72, 0.34, 0], [-0.08, 0.72, 0.34, 0], [-0.16, 0.715, 0.32, 0],
  [-0.6, 0.64, 0.25, 0], [-2.4, 0.22, 0.08, 0], [-50, 0, 0.05, 0],
];
const STEEP = [
  [40, 0, 0.05, 0], [3.8, -0.04, 0.05, 0], [2.3, -0.14, 0.05, 0], [1.45, 0.02, 0.1, 0],
  [0.85, 0.38, 0.12, 0], [0.45, 0.78, 0.25, 0], [0.28, 1.02, 0.5, 0], [0.3, 1.14, 0.8, 0.02],
  [0.42, 1.19, 1.0, 0.06], [0.52, 1.17, 1.0, 0.2], [0.48, 1.21, 0.95, 0.15], [0.36, 1.24, 0.85, 0.05],
  [0.0, 1.18, 0.6, 0], [-1.6, 0.55, 0.15, 0], [-50, 0, 0.05, 0],
];
const BARREL = [
  [40, 0, 0.05, 0], [3.6, -0.06, 0.05, 0], [2.2, -0.18, 0.05, 0], [1.4, -0.02, 0.1, 0],
  [0.85, 0.35, 0.12, 0], [0.55, 0.75, 0.25, 0], [0.52, 1.1, 0.55, 0.02], [0.78, 1.33, 0.85, 0.05],
  [1.25, 1.3, 1.0, 0.04], [1.62, 1.05, 1.0, 0.4], [1.5, 1.15, 1.0, 0.3], [1.05, 1.41, 0.85, 0.04],
  [0.35, 1.4, 0.6, 0.02], [-1.2, 0.75, 0.15, 0], [-50, 0, 0.05, 0],
];
const TUBE = [
  [40, 0, 0.05, 0], [3.6, -0.03, 0.05, 0.55], [2.3, -0.1, 0.05, 0.45], [1.45, 0.0, 0.1, 0.12],
  [0.9, 0.35, 0.12, 0.04], [0.6, 0.75, 0.25, 0.03], [0.58, 1.08, 0.55, 0.05], [0.85, 1.3, 0.9, 0.1],
  [1.6, 1.15, 0.95, 0.1], [2.15, 0.2, 0.9, 1.0], [2.04, 0.42, 0.8, 0.95], [1.65, 1.3, 0.75, 0.3],
  [0.5, 1.45, 0.55, 0.2], [-1.0, 0.8, 0.15, 0.05], [-50, 0, 0.05, 0],
];
const WHITE = [
  [40, 0, 0.05, 0], [4.5, 0.03, 0.1, 0.75], [3.2, 0.08, 0.15, 0.95], [2.6, 0.2, 0.2, 1],
  [2.1, 0.35, 0.2, 1], [1.6, 0.48, 0.2, 1], [1.2, 0.56, 0.2, 1], [0.85, 0.6, 0.2, 1],
  [0.55, 0.62, 0.2, 1], [0.3, 0.62, 0.2, 1], [0.1, 0.61, 0.2, 1], [-0.15, 0.58, 0.2, 1],
  [-0.5, 0.5, 0.2, 0.9], [-1.8, 0.2, 0.1, 0.5], [-50, 0, 0.05, 0],
];

const STATES = [
  { b: 0.0, k: SWELL },
  { b: 0.75, k: STEEP },
  { b: 1.0, k: BARREL },
  { b: 1.6, k: TUBE },
  { b: 2.5, k: WHITE },
];

export const NK = 15;
// Samples per spline segment (14 segments between 15 keypoints).
export const SEG = [10, 8, 8, 10, 10, 10, 10, 12, 12, 6, 8, 10, 10, 10];
export const ROWS = SEG.reduce((a, b) => a + b, 0) + 1;
export const TROUGH_ROW = SEG[0] + SEG[1];
// Rows belonging to each keypoint (row index where each keypoint sits).
export const KEY_ROW = (() => {
  const r = [0];
  for (let i = 0; i < SEG.length; i++) r.push(r[i] + SEG[i]);
  return r;
})();
// How much each keypoint takes part in the flat ocean swell (for blending
// into the surrounding ocean mesh).
const FLAT_W = [1, 0.7, 0.25, 0.05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.35, 1];

export function smoothstep(a, b, x) {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
}

// Break stage of the wave as a function of distance from the peel point.
export function breakAt(u) {
  if (u >= 40) return 0;
  if (u >= 8) return 0.75 * Math.pow(1 - (u - 8) / 32, 1.3);
  if (u >= 0) return 0.75 + 0.25 * (1 - u / 8);
  if (u >= -7) return 1 + 0.6 * (-u / 7);
  if (u >= -14) return 1.6 + 0.9 * ((-u - 7) / 7);
  return 2.5;
}

// Height multiplier along the crest (shoulder tapers, far ends fade out).
export function heightAt(u) {
  const shoulder = 0.42 + 0.58 * Math.exp(-Math.max(u, 0) / 38);
  const ends = smoothstep(115, 85, u) * smoothstep(-75, -55, u);
  return shoulder * ends;
}

// Interpolate keypoints for a break stage b. out: Float32Array(NK*4)
export function keysFor(b, out) {
  let i = 0;
  while (i < STATES.length - 2 && b > STATES[i + 1].b) i++;
  const A = STATES[i], B = STATES[i + 1];
  let t = (b - A.b) / (B.b - A.b);
  t = Math.min(1, Math.max(0, t));
  t = t * t * (3 - 2 * t);
  for (let k = 0; k < NK; k++) {
    for (let c = 0; c < 4; c++) out[k * 4 + c] = A.k[k][c] + (B.k[k][c] - A.k[k][c]) * t;
  }
  return out;
}

const _keys = new Float32Array(NK * 4);
const _kz = new Float32Array(NK), _ky = new Float32Array(NK);

// Sample one cross-section column.
// H: height in metres, b: break stage.
// Writes ROWS entries into the provided arrays (any can be null).
export function sampleColumn(H, b, zs, ys, trans, foam, flat) {
  keysFor(b, _keys);
  for (let k = 0; k < NK; k++) {
    const far = k === 0 || k === NK - 1;
    _kz[k] = far ? _keys[k * 4] : _keys[k * 4] * H;
    _ky[k] = far ? 0 : _keys[k * 4 + 1] * H;
  }
  let row = 0;
  for (let s = 0; s < SEG.length; s++) {
    const i0 = Math.max(0, s - 1), i1 = s, i2 = s + 1, i3 = Math.min(NK - 1, s + 2);
    // Centripetal Catmull-Rom knots
    const x0 = _kz[i0], y0 = _ky[i0], x1 = _kz[i1], y1 = _ky[i1];
    const x2 = _kz[i2], y2 = _ky[i2], x3 = _kz[i3], y3 = _ky[i3];
    const d01 = Math.max(1e-4, Math.pow((x1 - x0) ** 2 + (y1 - y0) ** 2, 0.25));
    const d12 = Math.max(1e-4, Math.pow((x2 - x1) ** 2 + (y2 - y1) ** 2, 0.25));
    const d23 = Math.max(1e-4, Math.pow((x3 - x2) ** 2 + (y3 - y2) ** 2, 0.25));
    const t0 = 0, t1 = d01, t2 = t1 + d12, t3 = t2 + d23;
    const n = SEG[s];
    const last = s === SEG.length - 1;
    for (let j = 0; j < (last ? n + 1 : n); j++) {
      let f = j / n;
      // denser sampling toward the wave on the long flat segments
      if (s === 0) f = 1 - Math.pow(1 - f, 2.2);
      if (last) f = Math.pow(f, 2.2);
      const t = t1 + (t2 - t1) * f;
      let px, py;
      if (i0 === i1 || i2 === i3 || d12 < 2e-4) {
        // fall back to linear at the ends
        px = x1 + (x2 - x1) * f; py = y1 + (y2 - y1) * f;
      } else {
        const a1x = ((t1 - t) * x0 + (t - t0) * x1) / (t1 - t0), a1y = ((t1 - t) * y0 + (t - t0) * y1) / (t1 - t0);
        const a2x = ((t2 - t) * x1 + (t - t1) * x2) / (t2 - t1), a2y = ((t2 - t) * y1 + (t - t1) * y2) / (t2 - t1);
        const a3x = ((t3 - t) * x2 + (t - t2) * x3) / (t3 - t2), a3y = ((t3 - t) * y2 + (t - t2) * y3) / (t3 - t2);
        const b1x = ((t2 - t) * a1x + (t - t0) * a2x) / (t2 - t0), b1y = ((t2 - t) * a1y + (t - t0) * a2y) / (t2 - t0);
        const b2x = ((t3 - t) * a2x + (t - t1) * a3x) / (t3 - t1), b2y = ((t3 - t) * a2y + (t - t1) * a3y) / (t3 - t1);
        px = ((t2 - t) * b1x + (t - t1) * b2x) / (t2 - t1);
        py = ((t2 - t) * b1y + (t - t1) * b2y) / (t2 - t1);
      }
      if (zs) zs[row] = px;
      if (ys) ys[row] = py;
      const g = j / n;
      if (trans) trans[row] = _keys[i1 * 4 + 2] + (_keys[i2 * 4 + 2] - _keys[i1 * 4 + 2]) * g;
      if (foam) foam[row] = _keys[i1 * 4 + 3] + (_keys[i2 * 4 + 3] - _keys[i1 * 4 + 3]) * g;
      if (flat) flat[row] = FLAT_W[i1] + (FLAT_W[i2] - FLAT_W[i1]) * g;
      row++;
    }
  }
}

// The wave as a whole: shape over time, peel position, sections.
export class Wave {
  constructor() {
    this.H0 = 3.0;          // base height multiplier (face ~ 4.3 m at the pocket)
    this.peelX = 0;          // world x of the peel point
    this.peelSpeed = 10;     // m/s
    this.z = 0;              // world z of the crest line
    this.breakAmt = 0;       // 0 = unbroken swell, 1 = fully peeling
    this.grow = 1;           // overall height factor (approach)
    this.close = null;       // closeout section {x0 (world), t}
    this.time = 0;
    this.version = 0;        // bumps when the shape (not just position) changes
  }

  // Break stage at u (distance from peel point).
  bAt(u) {
    let b = breakAt(u) * this.breakAmt;
    if (this.close) {
      const c = this.close;
      const d = u - (c.x0 - this.peelX);
      if (d > -4) {
        // the section ahead throws all at once, slightly earlier near its start
        const local = c.t * 0.55 - Math.max(0, d) * 0.012;
        b = Math.max(b, Math.min(2.5, Math.max(0, local)) * smoothstep(-4, 2, d));
      }
    }
    return b;
  }

  hAt(u) {
    let h = heightAt(u) * this.grow;
    if (this.close) {
      // closeout section stands up a bit as it breaks
      const d = u - (this.close.x0 - this.peelX);
      h *= 1 + 0.25 * smoothstep(-6, 10, d) * Math.min(1, this.close.t * 0.6) * (1 - smoothstep(50, 90, d));
      // keep the closeout section wide so it reads as a wall
      if (d > 0) h = Math.max(h, heightAt(Math.min(u, 6)) * this.grow * smoothstep(110, 80, u) * Math.min(1, this.close.t));
    }
    return h * this.H0;
  }

  column(u, zs, ys, trans, foam, flat) {
    sampleColumn(this.hAt(u), this.bAt(u), zs, ys, trans, foam, flat);
  }
}
