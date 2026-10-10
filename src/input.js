// Two thumbs = two feet. Each thumb is tracked from where it lands; sliding it
// down presses that foot into the board. Left half of the screen is the left
// foot, right half the right foot. Which one is the front foot depends on the
// direction you are travelling on screen.

export class FootInput {
  constructor(el) {
    this.el = el;
    this.pointers = new Map(); // id -> {side, x0, y0, y, p}
    this.keys = { left: 0, right: 0 };
    this.keyHeld = { left: false, right: false, hard: false };
    this.left = 0; this.right = 0;
    this.leftDown = false; this.rightDown = false;
    this.frontIsRight = true;
    this.enabled = true;
    this.bot = null;
    this.onAny = null;
    const scale = () => Math.max(38, Math.min(90, window.innerHeight * 0.16));
    const down = (e) => {
      if (!this.enabled) return;
      const side = e.clientX < window.innerWidth / 2 ? 'left' : 'right';
      // one pointer per side; a new thumb on the same side takes over
      for (const [id, p] of this.pointers) if (p.side === side) this.pointers.delete(id);
      this.pointers.set(e.pointerId, { side, x0: e.clientX, y0: e.clientY, x: e.clientX, y: e.clientY, p: 0, force: 0 });
      this.onAny && this.onAny();
    };
    const move = (e) => {
      const p = this.pointers.get(e.pointerId);
      if (!p) return;
      p.x = e.clientX; p.y = e.clientY;
      // sliding up re-centres, so the press is always relative to the highest point
      if (p.y < p.y0) p.y0 = p.y;
      p.p = Math.min(1, Math.max(0, (p.y - p.y0) / scale()));
      p.force = e.pressure && e.pointerType === 'touch' && e.pressure !== 0.5 ? e.pressure : 0;
    };
    const up = (e) => { this.pointers.delete(e.pointerId); };
    el.addEventListener('pointerdown', down);
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', up);

    const keyMap = { ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right', KeyJ: 'left', KeyL: 'right' };
    window.addEventListener('keydown', (e) => {
      if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') this.keyHeld.hard = true;
      const s = keyMap[e.code];
      if (s) { this.keyHeld[s] = true; e.preventDefault(); this.onAny && this.onAny(); }
      if (e.code === 'ArrowDown' || e.code === 'KeyS') { this.keyHeld.left = this.keyHeld.right = true; e.preventDefault(); }
    });
    window.addEventListener('keyup', (e) => {
      if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') this.keyHeld.hard = false;
      const s = keyMap[e.code];
      if (s) this.keyHeld[s] = false;
      if (e.code === 'ArrowDown' || e.code === 'KeyS') { this.keyHeld.left = this.keyHeld.right = false; }
    });
  }

  update(dt) {
    // keyboard presses ramp in and out
    for (const s of ['left', 'right']) {
      const target = this.keyHeld[s] ? (this.keyHeld.hard ? 1 : 0.7) : 0;
      const rate = target > this.keys[s] ? 5 : 8;
      this.keys[s] += Math.sign(target - this.keys[s]) * Math.min(Math.abs(target - this.keys[s]), rate * dt);
    }
    let l = this.keys.left, r = this.keys.right;
    this.leftDown = this.keyHeld.left; this.rightDown = this.keyHeld.right;
    for (const p of this.pointers.values()) {
      const v = Math.max(p.p, p.force > 0.15 ? (p.force - 0.15) / 0.6 : 0);
      if (p.side === 'left') { l = Math.max(l, v); this.leftDown = true; }
      else { r = Math.max(r, v); this.rightDown = true; }
    }
    if (this.bot) { const b = this.bot(); l = b.left; r = b.right; this.leftDown = this.rightDown = true; }
    this.left = Math.min(1, l); this.right = Math.min(1, r);
  }

  get front() { return this.frontIsRight ? this.right : this.left; }
  get back() { return this.frontIsRight ? this.left : this.right; }

  pointerFor(side) {
    for (const p of this.pointers.values()) if (p.side === side) return p;
    return null;
  }
}
