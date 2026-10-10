// Spray, mist and whitewater particles.
import * as THREE from 'three';

export class Spray {
  constructor(max, tex, sunColor) {
    this.max = max;
    this.pos = new Float32Array(max * 3);
    this.vel = new Float32Array(max * 3);
    this.life = new Float32Array(max);  // remaining
    this.span = new Float32Array(max);  // total
    this.size = new Float32Array(max);
    this.kind = new Float32Array(max);  // 0 droplet spray, 1 mist, 2 foam chunk
    this.alpha = new Float32Array(max);
    this.cursor = 0;
    const g = new THREE.BufferGeometry();
    this.posAttr = new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage);
    this.sizeAttr = new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage);
    this.alphaAttr = new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('position', this.posAttr);
    g.setAttribute('aSize', this.sizeAttr);
    g.setAttribute('aAlpha', this.alphaAttr);
    g.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 1e5);
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        uTex: { value: tex },
        uScale: { value: 600 },
        uSunDir: { value: new THREE.Vector3(0, 0, -1) },
        uSunColor: { value: sunColor },
      },
      transparent: true,
      depthWrite: false,
      vertexShader: /* glsl */ `
        attribute float aSize;
        attribute float aAlpha;
        uniform float uScale;
        uniform vec3 uSunDir;
        varying float vAlpha;
        varying float vBack;
        void main() {
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_Position = projectionMatrix * mv;
          gl_PointSize = aSize * uScale / max(0.5, -mv.z);
          vAlpha = aAlpha;
          vec3 wp = (modelMatrix * vec4(position, 1.0)).xyz;
          vec3 V = normalize(cameraPosition - wp);
          vBack = pow(max(dot(V, -normalize(uSunDir)), 0.0), 3.0);
        }
      `,
      fragmentShader: /* glsl */ `
        uniform sampler2D uTex;
        uniform vec3 uSunColor;
        varying float vAlpha;
        varying float vBack;
        void main() {
          float a = texture2D(uTex, gl_PointCoord).a * vAlpha;
          if (a < 0.01) discard;
          vec3 c = vec3(0.82, 0.88, 0.92) * 0.75 + uSunColor * (0.18 + vBack * 0.9);
          gl_FragColor = vec4(c, a);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }
      `,
    });
    this.points = new THREE.Points(g, this.material);
    this.points.frustumCulled = false;
    this.points.renderOrder = 2;
  }

  emit(x, y, z, vx, vy, vz, life, size, kind = 0) {
    const i = this.cursor;
    this.cursor = (this.cursor + 1) % this.max;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
    this.life[i] = life; this.span[i] = life;
    this.size[i] = size; this.kind[i] = kind;
  }

  update(dt, wind) {
    const { pos, vel, life, span, size, kind, alpha } = this;
    for (let i = 0; i < this.max; i++) {
      if (life[i] <= 0) { alpha[i] = 0; continue; }
      life[i] -= dt;
      const k = kind[i];
      const drag = k === 1 ? 1.6 : k === 2 ? 2.5 : 0.6;
      const grav = k === 1 ? 0.6 : k === 2 ? 4 : 9.8;
      vel[i * 3] += (wind.x - vel[i * 3]) * Math.min(1, drag * dt * (k === 1 ? 1 : 0.3));
      vel[i * 3 + 2] += (wind.z - vel[i * 3 + 2]) * Math.min(1, drag * dt * (k === 1 ? 1 : 0.3));
      vel[i * 3 + 1] -= grav * dt;
      vel[i * 3 + 1] *= 1 - Math.min(1, drag * 0.2 * dt);
      pos[i * 3] += vel[i * 3] * dt;
      pos[i * 3 + 1] += vel[i * 3 + 1] * dt;
      pos[i * 3 + 2] += vel[i * 3 + 2] * dt;
      const t = 1 - life[i] / span[i];
      if (k === 1) { size[i] *= 1 + dt * 0.6; alpha[i] = Math.sin(Math.PI * Math.min(1, t)) * 0.16; }
      else if (k === 2) { size[i] *= 1 + dt * 0.35; alpha[i] = (1 - t) * 0.55; }
      else alpha[i] = (1 - t * t) * 0.7;
      if (pos[i * 3 + 1] < -0.6 && k !== 1) life[i] = 0;
    }
    this.posAttr.needsUpdate = true;
    this.sizeAttr.needsUpdate = true;
    this.alphaAttr.needsUpdate = true;
  }

  clear() { this.life.fill(0); this.alpha.fill(0); this.alphaAttr.needsUpdate = true; }
}
