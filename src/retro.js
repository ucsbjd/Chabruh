// 16-bit look: the scene renders into a small, SNES-sized frame, then gets
// tone mapped and snapped to a limited 80s Miami palette with ordered
// dithering, and scaled up with hard pixel edges.
import * as THREE from 'three';

// Vice palette: night purples, hot pinks, sunset oranges, pool teals.
const HEX = [
  0x0d0221, 0x1b0b3b, 0x2d1b69, 0x46207a, 0x6a2c91, 0x9b3aa8, 0xd03fa5, 0xff3ea5,
  0xff71ce, 0xffb3e3, 0xff5f6d, 0xff8e53, 0xffb547, 0xffe08a, 0xfff6d5, 0xffffff,
  0x061a33, 0x0a3157, 0x0b4f6c, 0x087f8c, 0x0aa5a6, 0x1fd1c1, 0x63f2de, 0xb8fff4,
  0x2a5fb0, 0x55a6ff, 0x3a2f4f, 0x6b5c86, 0xa99cc4, 0x7a3b2e, 0xc2704f, 0xf0b088,
];

const vert = /* glsl */`
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

const frag = /* glsl */`
precision highp float;
uniform sampler2D tScene;
uniform vec2 uRes;
uniform float uExposure;
uniform float uDither;
uniform vec3 uPal[${HEX.length}];
varying vec2 vUv;

vec3 aces(vec3 x) {
  // Narkowicz ACES fit
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}
float bayer4(vec2 p) {
  vec2 q = mod(floor(p), 4.0);
  float i = q.x + q.y * 4.0;
  // 4x4 Bayer matrix, row major
  float m[16];
  m[0]=0.;m[1]=8.;m[2]=2.;m[3]=10.;m[4]=12.;m[5]=4.;m[6]=14.;m[7]=6.;
  m[8]=3.;m[9]=11.;m[10]=1.;m[11]=9.;m[12]=15.;m[13]=7.;m[14]=13.;m[15]=5.;
  for (int k = 0; k < 16; k++) if (float(k) == i) return (m[k] + 0.5) / 16.0;
  return 0.5;
}
void main() {
  vec3 c = texture2D(tScene, vUv).rgb * uExposure;
  c = aces(c);
  c = pow(c, vec3(1.0 / 2.2));
  // a touch more saturation, like a poster print
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  c = clamp(mix(vec3(l), c, 1.25), 0.0, 1.0);
  // nearest two palette colours, weighted toward how the eye sees them
  vec3 w = vec3(0.30, 0.59, 0.20);
  float d1 = 1e9, d2 = 1e9; vec3 c1 = vec3(0.0), c2 = vec3(0.0);
  for (int i = 0; i < ${HEX.length}; i++) {
    vec3 e = (uPal[i] - c) * w;
    float d = dot(e, e);
    if (d < d1) { d2 = d1; c2 = c1; d1 = d; c1 = uPal[i]; }
    else if (d < d2) { d2 = d; c2 = uPal[i]; }
  }
  float r = sqrt(d1) / max(1e-5, sqrt(d1) + sqrt(d2));
  vec3 o = bayer4(gl_FragCoord.xy) * uDither < r ? c2 : c1;
  gl_FragColor = vec4(o, 1.0);
}`;

export class Retro {
  constructor(renderer) {
    this.renderer = renderer;
    this.lines = 216; // vertical resolution, a bit under the SNES's 224
    this.rt = new THREE.WebGLRenderTarget(4, 4, {
      type: THREE.HalfFloatType, minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, depthBuffer: true,
    });
    this.small = new THREE.WebGLRenderTarget(4, 4, { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, depthBuffer: false });
    this.mat = new THREE.ShaderMaterial({
      vertexShader: vert, fragmentShader: frag, depthTest: false, depthWrite: false,
      uniforms: {
        tScene: { value: this.rt.texture }, uRes: { value: new THREE.Vector2() },
        uExposure: { value: 1 }, uDither: { value: 0.7 },
        uPal: { value: HEX.map((h) => new THREE.Vector3(((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255)) },
      },
    });
    this.copy = new THREE.ShaderMaterial({
      vertexShader: vert, depthTest: false, depthWrite: false,
      fragmentShader: 'uniform sampler2D t; varying vec2 vUv; void main(){ gl_FragColor = texture2D(t, vUv); }',
      uniforms: { t: { value: this.small.texture } },
    });
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.mat);
    this.quad.frustumCulled = false;
    this.postScene = new THREE.Scene();
    this.postScene.add(this.quad);
    this.postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  }

  setSize(w, h) {
    const H = this.lines, W = Math.round(H * w / h);
    this.rt.setSize(W, H);
    this.small.setSize(W, H);
    this.mat.uniforms.uRes.value.set(W, H);
    this.size = { w: W, h: H };
  }

  render(scene, camera, exposure) {
    const r = this.renderer;
    this.mat.uniforms.uExposure.value = exposure;
    const tm = r.toneMapping;
    r.toneMapping = THREE.NoToneMapping;
    r.setRenderTarget(this.rt);
    r.render(scene, camera);
    // palette pass at the small size, then a hard-edged upscale
    this.quad.material = this.mat;
    r.setRenderTarget(this.small);
    r.render(this.postScene, this.postCam);
    this.quad.material = this.copy;
    r.setRenderTarget(null);
    const cs = r.outputColorSpace;
    r.outputColorSpace = THREE.LinearSRGBColorSpace; // already display-ready
    r.render(this.postScene, this.postCam);
    r.outputColorSpace = cs;
    r.toneMapping = tm;
  }
}
