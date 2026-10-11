// Ride physics in the frame of the peel point.
//
// The surfer lives on the wave face, described by:
//   u  - along-crest distance from the peel point (m, + toward the shoulder)
//   s  - arc length up the face from the trough (m)
//   V  - board speed relative to the water (m/s)
//   th - board heading in the face plane (0 = down the line, +PI/2 = straight up)
// In this frame the water drifts back along the crest at the peel speed and
// creeps up the face as the wave moves under it, so the surfer has to keep
// harvesting gravity (angling down, pumping) to stay in the pocket.
import { ROWS, TROUGH_ROW, KEY_ROW, smoothstep } from './waveProfile.js';

const G = 9.8;
const TAU = Math.PI * 2;
const wrap = (a) => { a = (a + Math.PI) % TAU; if (a < 0) a += TAU; return a - Math.PI; };
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

// Signed rotation from heading `th` to `target`. A half-turn goes through
// "down the line" (th = 0) so presses never flip the board backwards.
function arcTo(th, target) {
  let d = wrap(target - th);
  if (Math.abs(d) > Math.PI - 0.2) {
    const viaZero = th > 0 ? -1 : 1;
    if (Math.abs(th) > Math.PI / 2) {
      // heading back toward the pocket: go through th = PI instead
      d = th > 0 ? Math.abs(d) : -Math.abs(d);
    } else d = viaZero * Math.abs(d);
  }
  return d;
}

export class Rider {
  constructor(wave) {
    this.wave = wave;
    this.z = new Float32Array(ROWS);
    this.y = new Float32Array(ROWS);
    this.arc = new Float32Array(ROWS);
    this.frontside = true;
    this.assist = 0.7; // 0 loose .. 1 the wave carries you back into trim
    this.reset();
  }

  reset() {
    this.state = 'idle';
    this.u = 5; this.s = 2; this.V = 9; this.th = -0.4; this.om = 0;
    this.pf = 0; this.pb = 0; this.st = 0;
    this.pivot = 0; this.pivotDir = 1; this.pivotTurned = 0;
    this.time = 0; this.slowTime = 0; this.drop = 0;
    this.barrel = 0; this.barrelTime = 0; this.inBarrel = false;
    this.cover = 0;
    this.spray = 0;
    this.air = null;
    this.float = null;
    this.events = [];
    this.result = null;
    this.lastLip = -9;
    this.compress = 0;
    this.pump = 0;
  }

  start(u, sFrac, V = 9.5, th = -0.35) {
    this.reset();
    this.state = 'ride';
    this.u = u;
    this.sampleAt(u);
    this.s = this.sTop * sFrac;
    this.V = V; this.th = th;
    this.drop = 1.3; // seconds of automatic drop down the face after the catch
  }

  // Sample the column at u and derive arc lengths and the ridable top.
  sampleAt(u) {
    const { z, y, arc } = this;
    this.wave.column(u, z, y, null, null, null);
    arc[0] = 0;
    for (let r = 1; r < ROWS; r++) arc[r] = arc[r - 1] + Math.hypot(z[r] - z[r - 1], y[r] - y[r - 1]);
    const s0 = arc[TROUGH_ROW];
    for (let r = 0; r < ROWS; r++) arc[r] -= s0;
    // ridable top: where the face rolls over the crest or turns into the ceiling
    let top = KEY_ROW[8];
    let ymax = 0;
    for (let r = TROUGH_ROW; r < ROWS; r++) ymax = Math.max(ymax, y[r]);
    for (let r = KEY_ROW[3]; r < KEY_ROW[8]; r++) {
      if (y[r] < ymax * 0.4) continue;
      const dz = z[r + 1] - z[r], dy = y[r + 1] - y[r];
      const l = Math.hypot(dz, dy) || 1;
      if (dy / l < 0.14 || dz / l > 0.25) { top = r; break; }
    }
    this.topRow = top;
    this.sTop = Math.max(0.5, arc[top]);
    this.sMin = Math.max(arc[KEY_ROW[1]], -7);
    this.b = this.wave.bAt(u);
    this.H = this.wave.hAt(u);
  }

  // Surface point and unit up-face tangent at arc length s.
  surface(s, out) {
    const { arc, z, y } = this;
    let lo = 0, hi = ROWS - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (arc[m] > s) hi = m; else lo = m; }
    const f = clamp((s - arc[lo]) / Math.max(1e-5, arc[hi] - arc[lo]), 0, 1);
    out.z = z[lo] + (z[hi] - z[lo]) * f;
    out.y = y[lo] + (y[hi] - y[lo]) * f;
    const dz = z[hi] - z[lo], dy = y[hi] - y[lo];
    const l = Math.hypot(dz, dy) || 1;
    out.tz = dz / l; out.ty = dy / l;
    return out;
  }

  emit(type, data = {}) { this.events.push({ type, ...data }); }

  end(result) {
    if (this.result) return;
    this.result = result;
    this.emit('end', { result });
  }

  step(dt, input) {
    this.events.length = 0;
    if (this.state === 'idle' || this.state === 'done') return;
    this.time += dt;
    const k = Math.min(1, dt * 14);
    this.pf += (input.front - this.pf) * k;
    this.pb += (input.back - this.pb) * k;
    this.st += ((input.steer || 0) - this.st) * k;
    if (this.state === 'air') return this.stepAir(dt);
    if (this.state === 'float') return this.stepFloat(dt);
    if (this.state === 'wipe' || this.state === 'over') {
      // off the wave: stay put in the water while the peel runs on
      this.u -= this.wave.peelSpeed * dt;
      if (this.air) this.air.x = this.u;
      return;
    }
    this.stepRide(dt);
  }

  stepRide(dt) {
    const wave = this.wave;
    const P = wave.peelSpeed;
    this.sampleAt(this.u);
    const b = this.b;
    const sf = this.surface(this.s, this._sf || (this._sf = {}));
    const pf = this.pf, pb = this.pb;
    const V = this.V;

    // ---- steering ----
    const A = this.assist;
    const rate = (0.9 + 2.5 * clamp(V / 9, 0, 1.25)) * (this.frontside ? 1.06 : 0.96) * (1 - 0.3 * A);
    const dDown = arcTo(this.th, -Math.PI / 2);
    const dUp = arcTo(this.th, Math.PI / 2);
    // carve toward the top or the bottom of the face; a half turn always
    // goes through "down the line" unless you are already heading back
    const st = this.st;
    let omT = st > 0 ? rate * st * clamp(dUp / 0.5, -1, 1) : rate * -st * clamp(dDown / 0.5, -1, 1);
    // leaning on the front foot also pulls the nose down a little
    omT += rate * 0.25 * pf * clamp(dDown / 0.5, -1, 1);

    // The wave carries you: with the fingers quiet, the board settles back
    // into a trim line through the pocket, a little above the middle of the
    // face. The more forgiving the feel, the stronger the pull.
    const quiet = 1 - Math.min(1, Math.abs(st) * 1.6);
    if (A > 0 && quiet > 0) {
      const thTrim = clamp(0.3 * (this.sTop * 0.52 - this.s) - 0.05 * (this.u - 4), -0.75, 0.75);
      omT += A * 2.6 * quiet * clamp(wrap(thTrim - this.th), -1.2, 1.2);
    }
    // straight after the catch: angle down the face and get going
    if (this.drop > 0) {
      this.drop -= dt;
      const w = clamp(this.drop / 0.5, 0, 1);
      const thDrop = this.s > this.sTop * 0.4 ? -0.85 : -0.25;
      omT = omT * (1 - w) + 5 * wrap(thDrop - this.th) * w;
      this.V = Math.max(this.V, 7.5);
    }

    // stomping the tail while carving up pivots the board (snaps, cutbacks)
    if (!this.pivot && pb > 0.75 && st > 0.25 && V > 4.2) {
      this.pivot = 1;
      this.pivotDir = Math.abs(dUp) < 0.4 ? (Math.sign(this.om) || 1) : Math.sign(dUp);
      this.pivotTurned = 0;
      this.emit('snap', { strength: clamp(V / 12, 0.3, 1) });
    }
    if (this.pivot) {
      omT = this.pivotDir * (4.6 + pb * 1.6) * (this.frontside ? 1 : 0.9);
      if (pb < 0.5 || this.pivotTurned > 2.9) this.pivot = 0;
    }
    this.om += (omT - this.om) * Math.min(1, dt * (this.pivot ? 16 : 7.5));
    const dth = this.om * dt;
    this.th = wrap(this.th + dth);
    if (this.pivot) this.pivotTurned += Math.abs(dth);

    // ---- speed ----
    const aG = -G * sf.ty * Math.sin(this.th);
    let drag = 0.033 * V + 0.008 * V * V;
    drag *= 1 - 0.3 * pf;
    const thrust = 1.0 * pf * clamp(V / 4, 0, 1);
    const stall = 3.4 * pb * clamp(V / 3, 0, 1) * (this.pivot ? 0.4 : 1);
    // pumping: rail-to-rail turns harvest energy while travelling down the line
    const along = Math.max(0, Math.cos(this.th));
    const pump = this.pivot ? 0 : 1.5 * Math.abs(this.om) * Math.sqrt(along) * (1 - smoothstep(11, 16, V)) * smoothstep(1.5, 4, V);
    this.pump += (pump - this.pump) * Math.min(1, dt * 4);
    const turnLoss = 0.045 * this.om * this.om * V + (this.pivot ? 0.55 * V : 0);
    // momentum of the wave: the face nudges you toward the speed that keeps
    // you in the pocket (forgiving feel only; it never does the riding for you)
    const vPocket = P + clamp((3 - this.u) * 0.35, -3, 3);
    const carry = A * 0.55 * clamp(vPocket - V * Math.max(0.2, Math.cos(this.th)), -2.5, 2.5) * (this.pivot ? 0 : 1);
    this.V = clamp(V + (aG - drag + thrust - stall + pump - turnLoss + carry) * dt, 0, 20);

    // ---- move ----
    const H0 = wave.H0;
    const w = 2.5 * clamp(b / 0.75, 0.3, 1.15) * clamp(this.H / H0, 0.4, 1.2) * (b > 1.75 ? 0 : 1);
    const vu = this.V * Math.cos(this.th) - P;
    const vs = this.V * Math.sin(this.th) + w;
    this.u += vu * dt;
    this.s += vs * dt;
    this.vu = vu; this.vs = vs;

    // spray from the rail
    this.spray = clamp(Math.abs(this.om) * this.V * 0.06 + (this.pivot ? 0.9 : 0) + pb * this.V * 0.03, 0, 1.5);

    // ---- barrel ----
    this.cover = clamp((b - 0.92) / 0.35, 0, 1) * (this.s < this.sTop + 0.2 ? 1 : 0);
    const inB = b > 0.97 && this.s > -0.5;
    if (inB && !this.inBarrel) { this.inBarrel = true; this.barrelTime = 0; this.emit('barrelStart'); }
    if (this.inBarrel) {
      this.barrelTime += dt;
      if (!inB) { this.inBarrel = false; this.emit('barrelEnd', { time: this.barrelTime }); }
    }

    // ---- limits ----
    if (this.s < this.sMin) { this.s = this.sMin; }

    // closed out by the lip / whitewater
    const landing = b > 1.42 && this.s < this.sTop * 0.35;
    if (b >= 1.72 || landing) {
      this.wipe(this.wave.close ? 'closeout' : 'closed');
      return;
    }

    if (this.s >= this.sTop) {
      const up = this.V * Math.sin(this.th);
      const sec = this.wave.close;
      if (b < 0.9) {
        if (up > 5.2 && this.th > 0.55) { this.launch(sf); return; }
        if (vs > 1.0 && this.th > 0.2) { this.goOver(); return; }
        this.s = this.sTop;
        this.redirectAtTop(dt);
      } else {
        const aheadB = wave.bAt(this.u + 3);
        if (sec && aheadB > 1.0 && this.th > 0.0 && this.th < 1.35 && this.V > 4.5 && !this.pivot) {
          this.startFloat();
          return;
        }
        if (sec && b < 1.3 && up > 5.5 && this.th > 0.8) { this.launch(sf); return; }
        this.s = this.sTop;
        if (this.time - this.lastLip > 0.4 && up > 2.5) { this.emit('lip', { strength: clamp(up / 8, 0.2, 1) }); this.lastLip = this.time; }
        this.redirectAtTop(dt);
      }
    }

    // lost the wave: too far onto the shoulder, or bogged down
    if (this.u > 60) { this.goOver('shoulder'); return; }
    if (this.V < 1.2) this.slowTime += dt; else this.slowTime = 0;
    if (this.slowTime > 1.6) { this.goOver('bogged'); return; }
  }

  // Riding into the top: the lip pushes the board back along the line.
  redirectAtTop(dt) {
    if (this.th > 0.05 && this.th < Math.PI - 0.05) {
      const k = Math.min(1, dt * 6);
      // bias toward whichever along-line direction is closer
      const target = this.th < Math.PI / 2 ? -0.15 : Math.PI + 0.15;
      this.th = wrap(this.th + wrap(target - this.th) * k * 0.6);
      this.V *= 1 - dt * 0.6;
      this.spray = Math.max(this.spray, 0.8);
    }
  }

  wipe(kind) {
    this.state = 'wipe';
    this.emit('wipeout', { kind });
    this.end(kind);
  }

  goOver(kind) {
    this.state = 'over';
    const late = this.wave.close || this.time > 26;
    this.emit('over', { kind });
    this.end(late ? 'kickout' : kind === 'shoulder' ? 'shoulder' : 'stalled');
  }

  launch(sf) {
    const P = this.wave.peelSpeed;
    const up = this.V * Math.sin(this.th);
    this.state = 'air';
    this.air = {
      x: this.u, y: sf.y, z: sf.z,
      vx: this.V * Math.cos(this.th) - P,
      vy: up * 0.5 + 1.2,
      vz: -up * 0.12,
      t: 0, spin: 0, th0: this.th,
      ny: -sf.tz, nz: sf.ty, // face normal at takeoff (y, z)
    };
    this.Vlaunch = this.V;
    this.emit('air');
  }

  stepAir(dt) {
    const a = this.air;
    a.t += dt;
    a.vy -= G * dt;
    a.x += a.vx * dt; a.y += a.vy * dt; a.z += a.vz * dt;
    // spin with the feet
    const sp = 5.2 * (this.pb - this.pf + this.st * 0.6);
    this.om += (sp - this.om) * Math.min(1, dt * 6);
    this.th = wrap(this.th + this.om * dt);
    a.spin += this.om * dt;
    this.u = a.x;
    this.sampleAt(this.u);
    if (a.vy > 0) return;
    // find the face below
    const { z, y, arc } = this;
    for (let r = TROUGH_ROW - 4; r < this.topRow + 2 && r < ROWS - 1; r++) {
      const z0 = z[r], z1 = z[r + 1];
      if ((a.z - z0) * (a.z - z1) <= 0 && z0 !== z1) {
        const f = (a.z - z0) / (z1 - z0);
        const ys = y[r] + (y[r + 1] - y[r]) * f;
        if (a.y <= ys + 0.05) {
          this.land(arc[r] + (arc[r + 1] - arc[r]) * f);
          return;
        }
      }
    }
    // came down behind the crest
    const crestZ = z[KEY_ROW[12]];
    if (a.z < crestZ && a.y < this.y[KEY_ROW[12]] * 0.85) {
      this.state = 'over';
      this.emit('over', { kind: 'air' });
      this.end('airback');
      return;
    }
    if (a.y < -1.5) this.landFlat();
  }

  land(s) {
    const th = this.th;
    const ok = th > -2.55 && th < 0.45;
    if (this.wave.close && this.wave.bAt(this.u) > 1.5) {
      // landing into the closeout whitewater after an air = done riding
      this.state = 'over';
      this.emit('land', { ok, hard: true });
      if (ok) this.end('air'); else this.wipe('landing');
      return;
    }
    if (!ok) { this.state = 'ride'; this.s = s; this.wipe('landing'); this.emit('land', { ok: false }); return; }
    this.state = 'ride';
    this.s = s;
    this.V = clamp(this.Vlaunch * 0.85, 4, 16);
    this.om = 0;
    this.emit('land', { ok: true, airTime: this.air.t });
    this.air = null;
  }

  landFlat() {
    this.state = 'over';
    this.emit('land', { ok: true, hard: true });
    this.end(this.wave.close ? 'air' : 'airback');
  }

  startFloat() {
    this.state = 'float';
    this.float = { t: 0 };
    this.emit('float');
  }

  stepFloat(dt) {
    const f = this.float;
    f.t += dt;
    const P = this.wave.peelSpeed;
    this.V = Math.max(3, this.V - dt * 2.2);
    this.th += (0 - this.th) * Math.min(1, dt * 5);
    this.u += (this.V - P * 0.35) * dt;
    this.sampleAt(this.u);
    this.spray = 0.5;
    if (f.t > 1.1 || this.b > 2.1) {
      // drop off the front of the section
      let topR = KEY_ROW[7];
      for (let r = KEY_ROW[6]; r <= KEY_ROW[12]; r++) if (this.y[r] > this.y[topR]) topR = r;
      this.Vlaunch = this.V;
      this.state = 'air';
      this.th = -0.5;
      this.air = { x: this.u, y: this.y[topR] + 0.1, z: this.z[topR], vx: this.V - P * 0.35, vy: 0.5, vz: 2.6, t: 0, spin: 0, th0: -0.5, nz: 0.3, ny: 0.95 };
      this.emit('floatEnd');
    }
  }

  // ---- outputs for rendering ----
  // world-space pose (before the scene mirror): fills pos, fwd, up
  pose(pos, fwd, up) {
    const wave = this.wave;
    if (this.state === 'air' || (this.state === 'over' && this.air)) {
      const a = this.air;
      pos.set(wave.peelX + a.x, a.y, wave.z + a.z);
      // orientation: heading in a plane tilted between the take-off face and level
      const ny = a.ny * 0.6 + 0.4, nz = a.nz * 0.6;
      const l = Math.hypot(ny, nz);
      up.set(0, ny / l, nz / l);
      // tangent pointing "up" in that plane is (0, up.z, -up.y)
      fwd.set(Math.cos(this.th), Math.sin(this.th) * up.z, -Math.sin(this.th) * up.y).normalize();
      return;
    }
    if (this.state === 'float') {
      let topR = KEY_ROW[7];
      for (let r = KEY_ROW[6]; r <= KEY_ROW[12]; r++) if (this.y[r] > this.y[topR]) topR = r;
      pos.set(wave.peelX + this.u, this.y[topR] + 0.04, wave.z + this.z[topR]);
      up.set(0, 1, 0.15).normalize();
      fwd.set(Math.cos(this.th), 0, -Math.sin(this.th) * 0.3).normalize();
      return;
    }
    const sf = this.surface(this.s, this._sf2 || (this._sf2 = {}));
    pos.set(wave.peelX + this.u, sf.y, wave.z + sf.z);
    up.set(0, -sf.tz, sf.ty);
    fwd.set(Math.cos(this.th), Math.sin(this.th) * sf.ty, Math.sin(this.th) * sf.tz);
    pos.addScaledVector(up, 0.03);
  }

  get roll() {
    if (this.state !== 'ride') return 0;
    return clamp(-this.om * this.V * 0.045, -1.0, 1.0);
  }
}
