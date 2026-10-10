// Mesh for the breaking wave, rebuilt from the profile whenever its shape changes.
import * as THREE from 'three';
import { ROWS } from './waveProfile.js';

export const U_MIN = -78, U_MAX = 118, DU = 0.7;
export const COLS = Math.round((U_MAX - U_MIN) / DU) + 1;

export class WaveMesh {
  constructor(wave, material) {
    this.wave = wave;
    const n = COLS * ROWS;
    this.pos = new Float32Array(n * 3);
    this.nrm = new Float32Array(n * 3);
    this.data = new Float32Array(n * 4);
    this._z = new Float32Array(ROWS);
    this._y = new Float32Array(ROWS);
    this._tr = new Float32Array(ROWS);
    this._fo = new Float32Array(ROWS);
    this._fl = new Float32Array(ROWS);

    const idx = new Uint32Array((COLS - 1) * (ROWS - 1) * 6);
    let k = 0;
    for (let c = 0; c < COLS - 1; c++) {
      for (let r = 0; r < ROWS - 1; r++) {
        const a = c * ROWS + r, b = (c + 1) * ROWS + r;
        idx[k++] = a; idx[k++] = b; idx[k++] = a + 1;
        idx[k++] = a + 1; idx[k++] = b; idx[k++] = b + 1;
      }
    }
    const g = new THREE.BufferGeometry();
    this.posAttr = new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage);
    this.nrmAttr = new THREE.BufferAttribute(this.nrm, 3).setUsage(THREE.DynamicDrawUsage);
    this.dataAttr = new THREE.BufferAttribute(this.data, 4).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.posAttr);
    g.setAttribute('normal', this.nrmAttr);
    g.setAttribute('aData', this.dataAttr);
    g.setIndex(new THREE.BufferAttribute(idx, 1));
    g.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 0, 0), 400);
    this.geometry = g;
    this.mesh = new THREE.Mesh(g, material);
    this.mesh.frustumCulled = false;
    this.material = material;
    this.builtVersion = -1;
  }

  // Rebuild columns from cMin to cMax (inclusive).
  rebuild(cMin = 0, cMax = COLS - 1) {
    const { pos, nrm, data, _z, _y, _tr, _fo, _fl, wave } = this;
    cMin = Math.max(0, cMin); cMax = Math.min(COLS - 1, cMax);
    for (let c = cMin; c <= cMax; c++) {
      const u = U_MIN + c * DU;
      wave.column(u, _z, _y, _tr, _fo, _fl);
      const h = wave.hAt(u) / wave.H0;
      const flatBoost = 1 - Math.min(1, h * 3); // tapered ends behave like open ocean
      let arc = 0;
      for (let r = 0; r < ROWS; r++) {
        const i = c * ROWS + r;
        if (r > 0) arc += Math.hypot(_z[r] - _z[r - 1], _y[r] - _y[r - 1]);
        pos[i * 3] = u;
        pos[i * 3 + 1] = _y[r];
        pos[i * 3 + 2] = _z[r];
        data[i * 4] = _tr[r];
        data[i * 4 + 1] = _fo[r];
        data[i * 4 + 2] = Math.max(_fl[r], flatBoost);
        data[i * 4 + 3] = arc;
      }
    }
    // normals from the grid: N = dP/du x dP/dt
    const nMin = Math.max(0, cMin - 1), nMax = Math.min(COLS - 1, cMax + 1);
    for (let c = nMin; c <= nMax; c++) {
      const c0 = Math.max(0, c - 1), c1 = Math.min(COLS - 1, c + 1);
      for (let r = 0; r < ROWS; r++) {
        const r0 = Math.max(0, r - 1), r1 = Math.min(ROWS - 1, r + 1);
        const a = (c0 * ROWS + r) * 3, b = (c1 * ROWS + r) * 3;
        const d = (c * ROWS + r0) * 3, e = (c * ROWS + r1) * 3;
        const ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2];
        let tx = pos[e] - pos[d], ty = pos[e + 1] - pos[d + 1], tz = pos[e + 2] - pos[d + 2];
        if (tx * tx + ty * ty + tz * tz < 1e-10) { tx = 0; ty = 0; tz = -1; }
        let nx = uy * tz - uz * ty, ny = uz * tx - ux * tz, nz = ux * ty - uy * tx;
        const l = Math.hypot(nx, ny, nz) || 1;
        const i = (c * ROWS + r) * 3;
        nrm[i] = nx / l; nrm[i + 1] = ny / l; nrm[i + 2] = nz / l;
      }
    }
    for (const [attr, size] of [[this.posAttr, 3], [this.nrmAttr, 3], [this.dataAttr, 4]]) {
      attr.clearUpdateRanges();
      attr.addUpdateRange(nMin * ROWS * size, (nMax - nMin + 1) * ROWS * size);
      attr.needsUpdate = true;
    }
    this.builtVersion = wave.version;
  }

  update(dt) {
    this.since = (this.since || 0) + dt;
    if (this.builtVersion === this.wave.version) return this.place();
    // shape changes are slow morphs: ~30 rebuilds a second is plenty
    if (this.builtVersion >= 0 && this.since < 1 / 30) return this.place();
    this.since = 0;
    const w = this.wave;
    let cMin = 0;
    if (w.breakAmt >= 1 && w.grow >= 1 && w.close && this.builtVersion >= 0) {
      cMin = Math.floor((w.close.x0 - w.peelX - 8 - U_MIN) / DU);
    }
    this.rebuild(cMin, COLS - 1);
    this.place();
  }

  place() {
    this.material.uniforms.uPeelX.value = this.wave.peelX;
    this.material.uniforms.uWaveZ.value = this.wave.z;
  }
}
