// Fingerboard controls: rest two fingers (index + middle) anywhere on the
// screen, close together, and slide them like a fingerboard.
//   up / down          carve up or down the face
//   toward travel      weight on the front foot: nose down, drive speed
//   away from travel   weight on the back foot: stall, slow down
//   back + up hard     stomp the tail and snap
// Only the movement counts, not where the fingers are, so you can keep them
// low on the screen and out of the way of the surfer.

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));

export class FingerboardInput {
  constructor(el) {
    this.el = el;
    this.pointers = new Map(); // id -> {x, y}
    this.origin = null;        // centroid where the fingers landed
    this.centroid = { x: 0, y: 0 };
    this.keys = new Set();
    this.kx = 0; this.ky = 0;
    this.steer = 0;   // -1 down the face .. +1 up the face
    this.weight = 0;  // -1 back foot .. +1 front foot
    this.dx = 0; this.dy = 0; // normalised screen offsets, for the HUD
    this.touching = false;
    this.fingers = 0;
    this.frontIsRight = true;
    this.bot = null;

    const radius = () => clamp(Math.min(window.innerWidth, window.innerHeight) * 0.13, 45, 110);
    this.radius = radius;
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
      this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      rebase(before);
    });
    window.addEventListener('pointermove', (e) => {
      const p = this.pointers.get(e.pointerId);
      if (!p) return;
      p.x = e.clientX; p.y = e.clientY;
      this.centroid = centroid();
    });
    const up = (e) => {
      if (!this.pointers.has(e.pointerId)) return;
      const before = centroid();
      this.pointers.delete(e.pointerId);
      rebase(before);
    };
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);

    const KEYS = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'KeyA', 'KeyD', 'KeyW', 'KeyS', 'ShiftLeft', 'ShiftRight'];
    window.addEventListener('keydown', (e) => { if (KEYS.includes(e.code)) { this.keys.add(e.code); e.preventDefault(); } });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => { this.keys.clear(); this.pointers.clear(); this.origin = null; });
  }

  update(dt) {
    let dx = 0, dy = 0; // screen space, right / up positive, unit circle
    this.fingers = this.pointers.size;
    this.touching = this.fingers > 0 && !!this.origin;
    if (this.touching) {
      const R = this.radius();
      dx = (this.centroid.x - this.origin.x) / R;
      dy = -(this.centroid.y - this.origin.y) / R;
    }
    // keyboard: arrows ramp toward their targets
    const k = this.keys;
    const hard = k.has('ShiftLeft') || k.has('ShiftRight') ? 1 : 0.65;
    const tx = ((k.has('ArrowRight') || k.has('KeyD')) - (k.has('ArrowLeft') || k.has('KeyA'))) * hard;
    const ty = ((k.has('ArrowUp') || k.has('KeyW')) - (k.has('ArrowDown') || k.has('KeyS'))) * hard;
    const ramp = (v, t) => v + clamp(t - v, -dt * 6, dt * 6);
    this.kx = ramp(this.kx, tx); this.ky = ramp(this.ky, ty);
    if (!this.touching) { dx = this.kx; dy = this.ky; }
    const len = Math.hypot(dx, dy);
    if (len > 1) { dx /= len; dy /= len; }
    this.dx = dx; this.dy = dy;
    const dir = this.frontIsRight ? 1 : -1;
    this.steer = dy;
    this.weight = dx * dir;
    if (this.bot) { const b = this.bot(); this.steer = b.steer; this.weight = b.weight; this.dx = b.weight * dir; this.dy = b.steer; }
  }

  get front() { return Math.max(0, this.weight); }
  get back() { return Math.max(0, -this.weight); }
}
