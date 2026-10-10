// Atmospheric sky (Preetham model) and a cube map of it for water reflections.
import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';

export const TIMES = {
  golden: { elevation: 5, azimuth: -160, turbidity: 9, rayleigh: 3, mie: 0.007, mieG: 0.88, exposure: 0.5, sun: [1.0, 0.72, 0.48], sunI: 2.4 },
  morning: { elevation: 22, azimuth: -150, turbidity: 3.5, rayleigh: 1.4, mie: 0.004, mieG: 0.8, exposure: 0.36, sun: [1.0, 0.9, 0.78], sunI: 2.6 },
  dusk: { elevation: 1.8, azimuth: -165, turbidity: 9, rayleigh: 3.2, mie: 0.008, mieG: 0.9, exposure: 0.55, sun: [1.0, 0.5, 0.3], sunI: 1.8 },
};

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
    for (const s of [this.sky, this.envSky]) {
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
