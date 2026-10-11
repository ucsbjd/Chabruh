// Shared water shading for the breaking wave and the open ocean.
import * as THREE from 'three';

// Background swell + wind chop (Gerstner). Directions are mostly toward shore (+z).
export const GERSTNER = [
  // dirX, dirZ, amplitude, wavelength, steepness
  [0.08, 1.0, 0.22, 46, 0.5],
  [-0.25, 1.0, 0.13, 27, 0.5],
  [0.35, 1.0, 0.08, 15, 0.6],
  [-0.5, 0.85, 0.045, 8.5, 0.6],
  [0.7, 0.7, 0.025, 4.6, 0.6],
];

export function gerstnerHeight(x, z, t, scale = 1) {
  let y = 0;
  for (const [dx, dz, A, L, Q] of GERSTNER) {
    const len = Math.hypot(dx, dz);
    const k = (2 * Math.PI) / L;
    const w = Math.sqrt(9.8 * k);
    y += A * scale * Math.sin(k * ((dx / len) * x + (dz / len) * z) - w * t);
  }
  return y;
}

const gerstnerGLSL = /* glsl */ `
uniform float uSwell;
vec3 gerstner(vec2 p, float t, inout vec3 nrm) {
  vec3 d = vec3(0.0);
  vec3 n = vec3(0.0, 1.0, 0.0);
  ${GERSTNER.map(([dx, dz, A, L, Q]) => {
    const len = Math.hypot(dx, dz);
    const k = (2 * Math.PI) / L;
    const w = Math.sqrt(9.8 * k);
    return `{
      vec2 D = vec2(${(dx / len).toFixed(5)}, ${(dz / len).toFixed(5)});
      float A = ${A.toFixed(4)} * uSwell;
      float f = ${k.toFixed(5)} * dot(D, p) - ${w.toFixed(5)} * t;
      float c = cos(f), s = sin(f);
      d.xz += ${Q.toFixed(3)} * A * D * c;
      d.y += A * s;
      n.xz -= D * ${k.toFixed(5)} * A * c;
      n.y -= ${Q.toFixed(3)} * ${k.toFixed(5)} * A * s;
    }`;
  }).join('\n')}
  nrm = normalize(n);
  return d;
}
`;

const shadeGLSL = /* glsl */ `
uniform samplerCube uEnv;
uniform sampler2D uNormalMap;
uniform sampler2D uFoamMap;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform float uTime;
uniform float uFlow;
uniform vec3 uDeep;
uniform vec3 uBody;
uniform vec3 uSss;

vec3 skyLookup(vec3 r) {
  r.y = max(r.y, 0.0);
  return textureCube(uEnv, normalize(r)).rgb;
}

// N: geometric normal, T: along-crest tangent, uv: surface coords in metres,
// flow: how far the surface texture has advected (metres)
vec3 shadeWater(vec3 wp, vec3 N, vec3 T, vec2 uv, float flow, float trans, float foam, float detail) {
  vec3 V = normalize(cameraPosition - wp);
  vec3 B = normalize(cross(N, T));
  T = normalize(cross(B, N));

  // scrolling layers of detail normals; the third is stretched up the face
  vec2 uvA = vec2(uv.x * 0.09, (uv.y - flow) * 0.09) + vec2(uTime * 0.012, 0.0);
  vec2 uvB = vec2(uv.x * 0.031 + 0.37, (uv.y - flow * 0.8) * 0.031) - vec2(uTime * 0.007, uTime * 0.004);
  vec2 uvC = vec2(uv.x * 0.22 + 0.11, (uv.y - flow) * 0.045);
  vec3 nA = texture2D(uNormalMap, uvA).xyz * 2.0 - 1.0;
  vec3 nB = texture2D(uNormalMap, uvB).xyz * 2.0 - 1.0;
  vec3 nC = texture2D(uNormalMap, uvC).xyz * 2.0 - 1.0;
  vec2 dn = (nA.xy * 0.6 + nB.xy * 0.8 + nC.xy * 0.5) * detail;
  vec3 n = normalize(N + T * dn.x + B * dn.y);

  float ndv = max(dot(n, V), 0.0);
  float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
  vec3 R = reflect(-V, n);
  vec3 refl = skyLookup(R);
  // reflections that point into the water pick up the deep colour instead
  refl = mix(refl, uDeep * 2.0, smoothstep(0.0, -0.25, R.y));

  vec3 L = normalize(uSunDir);
  float ndl = max(dot(n, L), 0.0);

  // ambient light from the sky, darker on surfaces facing down (inside the tube)
  float facing = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
  vec3 skyAmb = (skyLookup(vec3(0.0, 1.0, 0.0)) * 0.6 + skyLookup(normalize(vec3(-L.x, 0.25, -L.z))) * 0.4);
  vec3 amb = skyAmb * (0.25 + 0.75 * facing * facing);

  vec3 deep = uDeep;
  vec3 body = uBody;
  float th = clamp(trans, 0.0, 1.0);
  vec3 col = mix(deep, body, th) * (0.25 + 1.4 * amb + ndl * uSunColor * 0.15);

  // light through thin water: the backlit lip glows green-turquoise
  float back = pow(max(dot(V, -L), 0.0), 3.0);
  float wrapL = pow(clamp(dot(-n, L) * 0.5 + 0.5, 0.0, 1.0), 2.0);
  vec3 sssCol = uSss;
  float thin = th * th;
  col += sssCol * uSunColor * (thin * (0.04 + back * 1.1 + wrapL * 0.35) + th * back * 0.12);
  col += sssCol * amb * th * 0.18;

  col = mix(col, refl, fres);

  // sun glint
  float rl = max(dot(R, L), 0.0);
  float spec = pow(rl, 700.0) * 22.0 + pow(rl, 80.0) * 0.5;
  col += uSunColor * spec * (1.0 - foam);

  // foam
  if (foam > 0.001) {
    vec2 fuv = vec2(uv.x * 0.12, (uv.y - flow * 0.9) * 0.16);
    vec4 f1 = texture2D(uFoamMap, fuv);
    vec4 f2 = texture2D(uFoamMap, fuv * 2.3 + vec2(0.31, uTime * 0.03));
    float pattern = mix(f1.r * 0.45 + f2.r * 0.25 + f1.g * 0.3, f1.g * 0.7 + f2.b * 0.3, smoothstep(0.6, 1.0, foam));
    float cover = smoothstep(1.0 - foam * 1.05, 1.0 - foam * 1.05 + 0.3, pattern + foam * 0.3);
    cover = max(cover, smoothstep(0.8, 1.0, foam) * (0.75 + 0.25 * f2.b));
    // aerated whitewater: brighter where lumps face the sky, faintly translucent at the edges
    float shade = 0.66 + 0.75 * (f1.g - 0.5) + 0.5 * dn.y + 0.2 * (f2.b - 0.5);
    vec3 foamLit = vec3(0.84, 0.89, 0.92) * (0.35 + 0.95 * amb) * shade + uSunColor * (0.2 * ndl + 0.3 * back * th);
    foamLit = mix(foamLit, col + sssCol * 0.25, (1.0 - cover) * 0.3);
    col = mix(col, foamLit, clamp(cover, 0.0, 1.0));
  }
  return col;
}

vec3 applyFog(vec3 col, vec3 wp) {
  vec3 d = wp - cameraPosition;
  float dist = length(d);
  vec3 dir = d / dist;
  vec3 fogC = skyLookup(normalize(vec3(dir.x, 0.015, dir.z)));
  float f = 1.0 - exp(-dist * 0.0011);
  return mix(col, fogC, f * f * 0.9 + f * 0.1);
}
`;

// Water tints: natural green-blue, or the saturated pool turquoise of a Miami poster.
const WATER = {
  real: { deep: [0.003, 0.04, 0.045], body: [0.016, 0.15, 0.14], sss: [0.07, 0.55, 0.42] },
  vice: { deep: [0.004, 0.02, 0.07], body: [0.01, 0.2, 0.26], sss: [0.05, 0.75, 0.7] },
};
function waterColors(name) {
  const w = WATER[name];
  return { uDeep: { value: new THREE.Vector3(...w.deep) }, uBody: { value: new THREE.Vector3(...w.body) }, uSss: { value: new THREE.Vector3(...w.sss) } };
}
export function setWaterColors(uniforms, name) {
  const w = WATER[name] || WATER.real;
  uniforms.uDeep.value.set(...w.deep); uniforms.uBody.value.set(...w.body); uniforms.uSss.value.set(...w.sss);
}

export function makeWaterUniforms({ env, normalMap, foamMap, sunDir, sunColor }) {
  return {
    uEnv: { value: env },
    uNormalMap: { value: normalMap },
    uFoamMap: { value: foamMap },
    uSunDir: { value: sunDir },
    uSunColor: { value: sunColor },
    uTime: { value: 0 },
    uFlow: { value: 0 },
    uSwell: { value: 1 },
    ...waterColors('real'),
  };
}

// Breaking-wave material. Geometry positions are relative to the peel point.
export function makeWaveMaterial(shared) {
  return new THREE.ShaderMaterial({
    uniforms: {
      ...shared,
      uPeelX: { value: 0 },
      uWaveZ: { value: 0 },
    },
    side: THREE.DoubleSide,
    vertexShader: /* glsl */ `
      ${gerstnerGLSL}
      uniform sampler2D uFoamMap;
      uniform float uPeelX;
      uniform float uWaveZ;
      uniform float uTime;
      attribute vec4 aData; // trans, foam, flatWeight, arc
      varying vec3 vWP;
      varying vec3 vN;
      varying vec3 vT;
      varying vec4 vData;
      void main() {
        vec3 p = position + vec3(uPeelX, 0.0, uWaveZ);
        vec4 wp = modelMatrix * vec4(p, 1.0);
        vec3 gn;
        vec3 g = gerstner(wp.xz, uTime, gn);
        wp.xyz += g * aData.z;
        vec3 n = normalize(mat3(modelMatrix) * normal);
        // churning, lumpy surface where the water has broken
        float fo = aData.y * aData.y;
        if (fo > 0.01) {
          float l1 = texture2D(uFoamMap, wp.xz * vec2(0.035, 0.05) + vec2(0.0, -uTime * 0.05)).g;
          float l2 = texture2D(uFoamMap, wp.xz * vec2(0.09, 0.11) + vec2(uTime * 0.03, uTime * 0.07)).g;
          wp.xyz += n * ((l1 - 0.45) * 1.3 + (l2 - 0.5) * 0.6) * fo;
        }
        vN = normalize(mix(n, gn, aData.z * 0.8));
        vT = normalize(mat3(modelMatrix) * vec3(1.0, 0.0, 0.0));
        vWP = wp.xyz;
        vData = aData;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */ `
      ${shadeGLSL}
      uniform float uPeelX;
      varying vec3 vWP;
      varying vec3 vN;
      varying vec3 vT;
      varying vec4 vData;
      void main() {
        vec3 N = normalize(vN);
        if (!gl_FrontFacing) N = -N;
        // texture coords: along crest in world metres, across = arc length
        vec2 uv = vec2(vWP.x, vData.w);
        float flow = uTime * uFlow;
        float detail = mix(0.85, 0.35, clamp(vData.y, 0.0, 1.0));
        vec3 col = shadeWater(vWP, N, vT, uv, flow, vData.x, vData.y, detail);
        col = applyFog(col, vWP);
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
}

// Open ocean: radial grid that follows the camera.
export function makeOceanMaterial(shared) {
  return new THREE.ShaderMaterial({
    uniforms: {
      ...shared,
      uCenter: { value: new THREE.Vector2() },
      uHole: { value: new THREE.Vector4(0, 0, 0, 0) }, // xmin, xmax, zmin, zmax (world); disabled if xmax<=xmin
      uFoamTrail: { value: new THREE.Vector4(0, 0, 0, 0) },
    },
    vertexShader: /* glsl */ `
      ${gerstnerGLSL}
      uniform vec2 uCenter;
      uniform vec4 uHole;
      uniform float uTime;
      varying vec3 vWP;
      varying vec3 vN;
      varying float vCrest;
      void main() {
        vec3 p = position;
        p.xz += uCenter;
        vec3 gn;
        float fade = 1.0 - smoothstep(600.0, 2500.0, length(position.xz));
        vec3 g = gerstner(p.xz, uTime, gn) * fade;
        p += g;
        // tuck the ocean under the breaking-wave mesh
        if (uHole.y > uHole.x) {
          float inX = min(p.x - uHole.x, uHole.y - p.x);
          float inZ = min(p.z - uHole.z, uHole.w - p.z);
          float inside = min(inX, inZ);
          p.y -= smoothstep(0.0, 6.0, inside) * 6.0;
        }
        vWP = p;
        vN = normalize(mix(vec3(0.0, 1.0, 0.0), gn, fade));
        vCrest = g.y;
        gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
      }
    `,
    fragmentShader: /* glsl */ `
      ${shadeGLSL}
      varying vec3 vWP;
      varying vec3 vN;
      varying float vCrest;
      void main() {
        vec3 N = normalize(vN);
        float dist = length(vWP - cameraPosition);
        float detail = mix(0.6, 0.12, smoothstep(30.0, 600.0, dist));
        float trans = 0.05 + smoothstep(0.1, 0.35, vCrest) * 0.25;
        float foam = smoothstep(0.3, 0.42, vCrest) * 0.25;
        vec3 col = shadeWater(vWP, N, vec3(1.0, 0.0, 0.0), vWP.xz * vec2(1.0, -1.0), 0.0, trans, foam, detail);
        col = applyFog(col, vWP);
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
}

export function makeOceanGeometry() {
  const rings = 110, segs = 180;
  const pos = [];
  const idx = [];
  pos.push(0, 0, 0);
  for (let r = 1; r <= rings; r++) {
    const t = r / rings;
    const rad = 1.0 + 4000 * Math.pow(t, 3.2);
    for (let s = 0; s < segs; s++) {
      const a = (s / segs) * Math.PI * 2;
      pos.push(Math.cos(a) * rad, 0, Math.sin(a) * rad);
    }
  }
  for (let s = 0; s < segs; s++) idx.push(0, 1 + ((s + 1) % segs), 1 + s);
  for (let r = 1; r < rings; r++) {
    const a0 = 1 + (r - 1) * segs, a1 = 1 + r * segs;
    for (let s = 0; s < segs; s++) {
      const s1 = (s + 1) % segs;
      idx.push(a0 + s, a0 + s1, a1 + s);
      idx.push(a0 + s1, a1 + s1, a1 + s);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  return g;
}
