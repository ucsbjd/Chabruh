// Procedural, tileable textures generated at startup (no image downloads).
import * as THREE from 'three';

function makePerm(seed) {
  const p = new Uint8Array(512);
  const a = [...Array(256).keys()];
  let s = seed >>> 0;
  for (let i = 255; i > 0; i--) {
    s = (s * 1664525 + 1013904223) >>> 0;
    const j = s % (i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  for (let i = 0; i < 512; i++) p[i] = a[i & 255];
  return p;
}

// Periodic 2D gradient noise, period `per` lattice cells.
function perlin(perm, x, y, per) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = x - xi, yf = y - yi;
  const g = (ix, iy, dx, dy) => {
    const h = perm[(perm[((ix % per) + per) % per] + (((iy % per) + per) % per)) & 511] & 7;
    const gx = [1, -1, 1, -1, 1.41, -1.41, 0, 0][h], gy = [1, 1, -1, -1, 0, 0, 1.41, -1.41][h];
    return gx * dx + gy * dy;
  };
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  const u = fade(xf), v = fade(yf);
  const n00 = g(xi, yi, xf, yf), n10 = g(xi + 1, yi, xf - 1, yf);
  const n01 = g(xi, yi + 1, xf, yf - 1), n11 = g(xi + 1, yi + 1, xf - 1, yf - 1);
  const nx0 = n00 + (n10 - n00) * u, nx1 = n01 + (n11 - n01) * u;
  return nx0 + (nx1 - nx0) * v;
}

function fbm(perm, x, y, per, oct, gain = 0.5) {
  let a = 1, f = 1, s = 0, n = 0;
  for (let o = 0; o < oct; o++) {
    s += a * perlin(perm, x * f, y * f, per * f);
    n += a; a *= gain; f *= 2;
  }
  return s / n;
}

// Tileable water normal map: a choppy, slightly directional fbm.
export function makeWaterNormalMap(size = 256) {
  const perm = makePerm(7);
  const h = new Float32Array(size * size);
  const per = 8;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = (x / size) * per, v = (y / size) * per;
      let n = fbm(perm, u, v, per, 5, 0.55);
      // sharpen crests a little (trochoidal look)
      n = n - 0.6 * Math.abs(fbm(perm, u * 2 + 3.1, v * 2 + 1.7, per * 2, 3)) ;
      h[y * size + x] = n;
    }
  }
  const data = new Uint8Array(size * size * 4);
  const k = 2.5;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const l = h[y * size + ((x - 1 + size) % size)], r = h[y * size + ((x + 1) % size)];
      const d = h[((y - 1 + size) % size) * size + x], uu = h[((y + 1) % size) * size + x];
      let nx = (l - r) * k, ny = (d - uu) * k, nz = 1;
      const len = Math.hypot(nx, ny, nz);
      nx /= len; ny /= len; nz /= len;
      const i = (y * size + x) * 4;
      data[i] = (nx * 0.5 + 0.5) * 255;
      data[i + 1] = (ny * 0.5 + 0.5) * 255;
      data[i + 2] = (nz * 0.5 + 0.5) * 255;
      data[i + 3] = (h[y * size + x] * 0.5 + 0.5) * 255;
    }
  }
  const tex = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.anisotropy = 4;
  tex.needsUpdate = true;
  return tex;
}

// Tileable foam: R = lacy cellular network, G = soft blotches, B = fine bubbles.
export function makeFoamMap(size = 512) {
  const perm = makePerm(19);
  const cells = 10;
  // jittered feature points per cell (periodic)
  const pts = [];
  let s = 12345;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  for (let j = 0; j < cells; j++) for (let i = 0; i < cells; i++) pts.push([i + rnd(), j + rnd()]);
  const data = new Uint8Array(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = (x / size) * cells, v = (y / size) * cells;
      // warp
      const wu = u + 0.6 * fbm(perm, u * 0.5, v * 0.5, cells * 0.5, 3);
      const wv = v + 0.6 * fbm(perm, u * 0.5 + 9, v * 0.5 + 4, cells * 0.5, 3);
      const ci = Math.floor(wu), cj = Math.floor(wv);
      let f1 = 9, f2 = 9;
      for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
        const ii = ci + di, jj = cj + dj;
        const p = pts[(((jj % cells) + cells) % cells) * cells + (((ii % cells) + cells) % cells)];
        const px = p[0] + (ii - (((ii % cells) + cells) % cells));
        const py = p[1] + (jj - (((jj % cells) + cells) % cells));
        const d = Math.hypot(px - wu, py - wv);
        if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) f2 = d;
      }
      const edge = 1 - Math.min(1, (f2 - f1) * 3.2); // bright along cell borders
      const blotch = fbm(perm, u * 0.8, v * 0.8, cells * 0.8, 4) * 0.5 + 0.5;
      const fine = fbm(perm, u * 4, v * 4, cells * 4, 2) * 0.5 + 0.5;
      const i = (y * size + x) * 4;
      data[i] = Math.max(0, Math.min(255, (edge * 0.75 + blotch * 0.35) * 255));
      data[i + 1] = blotch * 255;
      data[i + 2] = fine * 255;
      data[i + 3] = 255;
    }
  }
  const tex = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.magFilter = THREE.LinearFilter;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.generateMipmaps = true;
  tex.anisotropy = 4;
  tex.needsUpdate = true;
  return tex;
}

// Soft round sprite for spray particles.
export function makeSprayTexture(size = 64) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const grd = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grd.addColorStop(0, 'rgba(255,255,255,1)');
  grd.addColorStop(0.35, 'rgba(255,255,255,0.55)');
  grd.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, size, size);
  const tex = new THREE.CanvasTexture(c);
  return tex;
}
