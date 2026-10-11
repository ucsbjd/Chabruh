// Atmospheric sky (Preetham model) and a cube map of it for water reflections.
import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';

export const TIMES = {
  vice: { vice: true, elevation: 4, azimuth: -160, exposure: 1.0, sun: [1.0, 0.55, 0.55], sunI: 2.2 },
  golden: { elevation: 5, azimuth: -160, turbidity: 9, rayleigh: 3, mie: 0.007, mieG: 0.88, exposure: 0.5, sun: [1.0, 0.72, 0.48], sunI: 2.4 },
  morning: { elevation: 22, azimuth: -150, turbidity: 3.5, rayleigh: 1.4, mie: 0.004, mieG: 0.8, exposure: 0.36, sun: [1.0, 0.9, 0.78], sunI: 2.6 },
  dusk: { elevation: 1.8, azimuth: -165, turbidity: 9, rayleigh: 3.2, mie: 0.008, mieG: 0.9, exposure: 0.55, sun: [1.0, 0.5, 0.3], sunI: 1.8 },
};

// Miami sunset: violet to hot pink to orange, a big striped sun, streaky clouds.
const viceVert = /* glsl */`
varying vec3 vDir;
void main() {
  vDir = position;
  vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  gl_Position = p.xyww;
}`;
const viceFrag = /* glsl */`
uniform vec3 uSun;
varying vec3 vDir;
vec3 lin(vec3 c) { return pow(c, vec3(2.2)) * 1.7; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void main() {
  vec3 d = normalize(vDir);
  float h = d.y;
  vec3 c;
  if (h < 0.0) c = mix(lin(vec3(0.95, 0.42, 0.40)), lin(vec3(0.16, 0.06, 0.28)), smoothstep(0.0, -0.25, h));
  else {
    c = mix(lin(vec3(1.0, 0.62, 0.32)), lin(vec3(1.0, 0.32, 0.52)), smoothstep(0.0, 0.05, h));
    c = mix(c, lin(vec3(0.72, 0.17, 0.56)), smoothstep(0.04, 0.13, h));
    c = mix(c, lin(vec3(0.30, 0.10, 0.48)), smoothstep(0.12, 0.28, h));
    c = mix(c, lin(vec3(0.07, 0.03, 0.17)), smoothstep(0.3, 0.8, h));
  }
  // the sun: a big disc, yellow at the top, pink at the bottom, cut by
  // horizontal bands that get wider toward the horizon
  vec3 s = normalize(uSun);
  vec3 right = normalize(cross(s, vec3(0.0, 1.0, 0.0)));
  vec3 up = cross(right, s);
  float sd = dot(d, s);
  vec2 q = vec2(dot(d, right), dot(d, up)) / 0.13;
  float r = length(q);
  if (sd > 0.0 && r < 1.0) {
    vec3 sc = mix(lin(vec3(1.0, 0.25, 0.55)), lin(vec3(1.0, 0.93, 0.45)), smoothstep(-0.8, 0.7, q.y)) * 1.6;
    float band = q.y < 0.15 ? step(0.62 + q.y * 0.9, fract(q.y * 6.0 + 0.3)) : 0.0;
    c = mix(c, sc, (1.0 - band) * step(0.0, h));
  }
  // glow around it
  c += lin(vec3(1.0, 0.45, 0.4)) * 0.5 * pow(max(0.0, sd), 40.0);
  // long streaky clouds low in the sky
  if (h > 0.01) {
    float az = atan(d.x, d.z);
    float n = noise(vec2(az * 9.0, h * 60.0)) * 0.6 + noise(vec2(az * 23.0, h * 140.0)) * 0.4;
    float band = smoothstep(0.03, 0.07, h) * (1.0 - smoothstep(0.1, 0.22, h));
    float cl = smoothstep(0.62, 0.8, n) * band;
    c = mix(c, lin(vec3(0.55, 0.16, 0.48)) + lin(vec3(1.0, 0.55, 0.45)) * 0.6 * pow(max(0.0, sd), 6.0), cl * 0.85);
  }
  gl_FragColor = vec4(c, 1.0);
}`;

function makeViceSky(radius) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(radius, 48, 24), new THREE.ShaderMaterial({
    vertexShader: viceVert, fragmentShader: viceFrag, side: THREE.BackSide, depthWrite: false,
    uniforms: { uSun: { value: new THREE.Vector3(0, 0.1, -1) } },
  }));
  m.frustumCulled = false;
  return m;
}

export class SkySystem {
  constructor(renderer, scene) {
    this.renderer = renderer;
    this.sky = new Sky();
    this.sky.scale.setScalar(9000);
    this.sky.material.depthWrite = false;
    scene.add(this.sky);

    this.envScene = new THREE.Scene();
    this.envSky = new Sky();
    this.envSky.scale.setScalar(900);
    this.envScene.add(this.envSky);
    this.vice = makeViceSky(8000);
    this.envVice = makeViceSky(800);
    scene.add(this.vice);
    this.envScene.add(this.envVice);
    this.cubeRT = new THREE.WebGLCubeRenderTarget(256, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter });
    this.cubeCam = new THREE.CubeCamera(0.5, 2000, this.cubeRT);
    this.envScene.add(this.cubeCam);

    this.sunDir = new THREE.Vector3();
    this.sunColor = new THREE.Vector3(1, 0.8, 0.6);
  }

  get env() { return this.cubeRT.texture; }

  set(name) {
    const p = TIMES[name] || TIMES.golden;
    this.preset = p;
    const phi = THREE.MathUtils.degToRad(90 - p.elevation);
    const theta = THREE.MathUtils.degToRad(p.azimuth);
    this.sunDir.setFromSphericalCoords(1, phi, theta);
    for (const v of [this.vice, this.envVice]) { v.visible = !!p.vice; v.material.uniforms.uSun.value.copy(this.sunDir); }
    this.sky.visible = this.envSky.visible = !p.vice;
    for (const s of [this.sky, this.envSky]) {
      if (p.vice) break;
      const u = s.material.uniforms;
      u.turbidity.value = p.turbidity;
      u.rayleigh.value = p.rayleigh;
      u.mieCoefficient.value = p.mie;
      u.mieDirectionalG.value = p.mieG;
      u.sunPosition.value.copy(this.sunDir);
    }
    this.sunColor.set(p.sun[0] * p.sunI, p.sun[1] * p.sunI, p.sun[2] * p.sunI);
    this.renderer.toneMappingExposure = p.exposure;
    // render the environment cube (sky only)
    const prevTM = this.renderer.toneMapping;
    this.renderer.toneMapping = THREE.NoToneMapping;
    this.cubeCam.update(this.renderer, this.envScene);
    this.renderer.toneMapping = prevTM;
  }
}
