// Procedural ocean sound: no samples, just shaped noise.
export class OceanAudio {
  constructor() {
    this.ctx = null;
    this.started = false;
  }

  start() {
    if (this.started) { this.ctx && this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.started = true;
    const ctx = (this.ctx = new AC());
    const len = ctx.sampleRate * 4;
    // brown-ish noise buffer
    const buf = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      let last = 0;
      for (let i = 0; i < len; i++) {
        const w = Math.random() * 2 - 1;
        last = (last + 0.02 * w) / 1.02;
        d[i] = last * 3.5 * 0.6 + w * 0.08;
      }
    }
    const white = ctx.createBuffer(1, len, ctx.sampleRate);
    { const d = white.getChannelData(0); for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1; }

    const master = (this.master = ctx.createGain());
    master.gain.value = 0.9;
    master.connect(ctx.destination);

    const loop = (b) => { const s = ctx.createBufferSource(); s.buffer = b; s.loop = true; s.start(0, Math.random() * 3); return s; };

    // ambient ocean wash
    const amb = loop(buf);
    const ambF = ctx.createBiquadFilter(); ambF.type = 'lowpass'; ambF.frequency.value = 520;
    this.ambG = ctx.createGain(); this.ambG.gain.value = 0.35;
    amb.connect(ambF).connect(this.ambG).connect(master);

    // wave roar (louder and darker near the curl)
    const roar = loop(buf);
    this.roarF = ctx.createBiquadFilter(); this.roarF.type = 'lowpass'; this.roarF.frequency.value = 300; this.roarF.Q.value = 0.6;
    this.roarG = ctx.createGain(); this.roarG.gain.value = 0;
    roar.connect(this.roarF).connect(this.roarG).connect(master);

    // rail hiss / spray
    const hiss = loop(white);
    this.hissF = ctx.createBiquadFilter(); this.hissF.type = 'bandpass'; this.hissF.frequency.value = 2400; this.hissF.Q.value = 0.7;
    this.hissG = ctx.createGain(); this.hissG.gain.value = 0;
    hiss.connect(this.hissF).connect(this.hissG).connect(master);

    // board chatter / water rush under the board
    const rush = loop(white);
    this.rushF = ctx.createBiquadFilter(); this.rushF.type = 'bandpass'; this.rushF.frequency.value = 700; this.rushF.Q.value = 1.2;
    this.rushG = ctx.createGain(); this.rushG.gain.value = 0;
    rush.connect(this.rushF).connect(this.rushG).connect(master);

    this.buf = buf;
  }

  // roar: 0..1 proximity to breaking water, tube: 0..1 inside the barrel,
  // speed m/s, spray 0..1
  update(roar, tube, speed, spray, riding) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const set = (p, v, tc = 0.12) => p.setTargetAtTime(v, t, tc);
    set(this.roarG.gain, 0.15 + roar * 0.75);
    set(this.roarF.frequency, 260 + roar * 500 - tube * 120);
    set(this.ambG.gain, riding ? 0.12 : 0.4);
    set(this.hissG.gain, Math.min(0.5, spray * 0.35), 0.05);
    set(this.hissF.frequency, 1800 + speed * 120);
    set(this.rushG.gain, riding ? Math.min(0.25, speed * 0.018) : 0);
    set(this.rushF.frequency, 400 + speed * 60);
  }

  // short noise burst
  hit(strength = 1, dark = false) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const s = ctx.createBufferSource(); s.buffer = this.buf;
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = dark ? 380 : 1600;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(0.9 * strength, t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.001, t + (dark ? 1.6 : 0.5));
    s.connect(f).connect(g).connect(this.master);
    s.start(t, Math.random() * 2);
    s.stop(t + 2);
  }
}
