// Fingerboard controls: rest two fingers (index + middle) anywhere on the
// screen, close together, and slide them like a fingerboard.
//   up / down          carve up or down the face
//   toward travel      weight on the front foot: nose down, drive speed
//   away from travel   weight on the back foot: stall, slow down
//   back + up hard     stomp the tail and snap
// Only the movement counts, not where the fingers are, so you can keep them
// low on the screen and out of the way of the surfer.
//
// Tuning (saved per device):
//   feel    0 loose .. 1 forgiving. Forgiving adds a dead zone and a soft
//           response curve, so small wobbles do nothing and it takes a
//           deliberate, exaggerated slide to really move the board.
//   reachX, reachY   how far (px) a full slide is, set by finger setup
//   scale   multiplies the reach (the "Reach" slider)
import { toStage } from './layout.js';

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

export const tune = { feel: 0.7, reachX: 0, reachY: 0, scale: 1, padX: 0.5, padY: 0.8, spread: 0, set: false };
try { Object.assign(tune, JSON.parse(localStorage.getItem('chabruh.tune') || '{}')); } catch (e) { /* storage unavailable */ }
export function saveTune() { try { localStorage.setItem('chabruh.tune', JSON.stringify(tune)); } catch (e) { /* ignore */ } }

// dead zone + expo curve, both growing with "feel"
export function shape(x, feel) {
  const dz = 0.05 + 0.17 * feel;
  const a = Math.abs(x);
  if (a <= dz) return 0;
  const t = Math.min(1, (a - dz) / (1 - dz));
  return Math.sign(x) * Math.pow(t, 1 + 1.1 * feel);
}

export class FingerboardInput {
  constructor(el, view) {
    this.el = el;
    this.view = view;
    this.pointers = new Map(); // id -> {x, y} in stage coordinates
    this.origin = null;        // centroid where the fingers landed
    this.centroid = { x: 0, y: 0 };
    this.keys = new Set();
    this.kx = 0; this.ky = 0;
    this.steer = 0;   // -1 down the face .. +1 up the face
    this.weight = 0;  // -1 back foot .. +1 front foot
    this.dx = 0; this.dy = 0; // raw normalised offsets, for the HUD
    this.touching = false;
    this.fingers = 0;
    this.frontIsRight = true;
    this.bot = null;
    this.listener = null; // finger setup hooks in here

    const centroid = () => {
      let x = 0, y = 0;
      for (const p of this.pointers.values()) { x += p.x; y += p.y; }
      const n = Math.max(1, this.pointers.size);
      return { x: x / n, y: y / n };
    };
    // When a finger lands or lifts the centroid jumps; shift the origin by the
    // same amount so the board does not jerk.
    const rebase = (before) => {
      if (!this.pointers.size) { this.origin = null; return; }
      const after = centroid();
      if (!this.origin) this.origin = { ...after };
      else if (before) { this.origin.x += after.x - before.x; this.origin.y += after.y - before.y; }
      this.centroid = after;
    };
    el.addEventListener('pointerdown', (e) => {
      if (this.pointers.size >= 2) return;
      const before = this.pointers.size ? centroid() : null;
      this.pointers.set(e.pointerId, toStage(e.clientX, e.clientY));
      rebase(before);
      this.listener?.('down', this);
    });
    window.addEventListener('pointermove', (e) => {
      if (!this.pointers.has(e.pointerId)) return;
      this.pointers.set(e.pointerId, toStage(e.clientX, e.clientY));
      this.centroid = centroid();
      this.listener?.('move', this);
    });
    const up = (e) => {
      if (!this.pointers.has(e.pointerId)) return;
      const before = centroid();
      this.pointers.delete(e.pointerId);
      rebase(before);
      this.listener?.('up', this);
    };
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);

    const KEYS = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'KeyA', 'KeyD', 'KeyW', 'KeyS', 'ShiftLeft', 'ShiftRight'];
    window.addEventListener('keydown', (e) => { if (KEYS.includes(e.code)) { this.keys.add(e.code); e.preventDefault(); } });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => { this.keys.clear(); this.pointers.clear(); this.origin = null; });
  }

  // finger spread (px) when two are down
  get spread() {
    if (this.pointers.size < 2) return 0;
    const [a, b] = [...this.pointers.values()];
    return Math.hypot(a.x - b.x, a.y - b.y);
  }

  // full-slide distance in px (x, y)
  reach() {
    const m = Math.min(this.view.w, this.view.h);
    const rx = tune.reachX || clamp(m * 0.3, 80, 240);
    const ry = tune.reachY || clamp(m * 0.22, 60, 180);
    return { x: rx * tune.scale, y: ry * tune.scale };
  }

  update(dt) {
    let dx = 0, dy = 0; // stage space, right / up positive
    this.fingers = this.pointers.size;
    this.touching = this.fingers > 0 && !!this.origin;
    if (this.touching) {
      const R = this.reach();
      dx = clamp((this.centroid.x - this.origin.x) / R.x, -1, 1);
      dy = clamp(-(this.centroid.y - this.origin.y) / R.y, -1, 1);
    }
    // keyboard: arrows ramp toward their targets
    const k = this.keys;
    const hard = k.has('ShiftLeft') || k.has('ShiftRight') ? 1 : 0.7;
    const tx = ((k.has('ArrowRight') || k.has('KeyD')) - (k.has('ArrowLeft') || k.has('KeyA'))) * hard;
    const ty = ((k.has('ArrowUp') || k.has('KeyW')) - (k.has('ArrowDown') || k.has('KeyS'))) * hard;
    const ramp = (v, t) => v + clamp(t - v, -dt * 5, dt * 5);
    this.kx = ramp(this.kx, tx); this.ky = ramp(this.ky, ty);
    if (!this.touching) { dx = this.kx; dy = this.ky; }
    this.dx = dx; this.dy = dy;
    const dir = this.frontIsRight ? 1 : -1;
    this.steer = shape(dy, tune.feel);
    this.weight = shape(dx * dir, tune.feel);
    if (this.bot) { const b = this.bot(); this.steer = b.steer; this.weight = b.weight; this.dx = b.weight * dir; this.dy = b.steer; }
  }

  get front() { return Math.max(0, this.weight); }
  get back() { return Math.max(0, -this.weight); }
}
