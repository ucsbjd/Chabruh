import * as THREE from 'three';
import { Wave, KEY_ROW, ROWS, TROUGH_ROW } from './waveProfile.js';
import { WaveMesh, U_MIN, U_MAX } from './waveMesh.js';
import { SkySystem } from './sky.js';
import { makeWaterNormalMap, makeFoamMap, makeSprayTexture } from './textures.js';
import { makeWaterUniforms, makeWaveMaterial, makeOceanMaterial, makeOceanGeometry, gerstnerHeight } from './water.js';
import { Surfer } from './surfer.js';
import { Rider } from './physics.js';
import { FootInput } from './input.js';
import { OceanAudio } from './audio.js';
import { Spray } from './particles.js';

const hash = location.hash.toLowerCase();
const search = new URLSearchParams(location.search);
const flag = (k) => hash.includes(k) || search.has(k);
const QUICK = flag('quick');
const BOT = flag('bot');
const DEBUG = flag('debug');

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const ease = (t) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
const rand = (a, b) => a + Math.random() * (b - a);

// ---------- renderer & scene ----------
const canvas = document.getElementById('game');
const isTouch = matchMedia('(pointer: coarse)').matches;
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, isTouch ? 1.5 : 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.outputColorSpace = THREE.SRGBColorSpace;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(52, 16 / 9, 0.1, 12000);
const root = new THREE.Group(); // everything in the wave's frame; mirrored for rights
scene.add(root);

const sky = new SkySystem(renderer, scene);
sky.set('golden');

const normalMap = makeWaterNormalMap(256);
const foamMap = makeFoamMap(512);
const shared = makeWaterUniforms({ env: sky.env, normalMap, foamMap, sunDir: sky.sunDir, sunColor: sky.sunColor });
shared.uFlow.value = 4.5;

const waveMat = makeWaveMaterial(shared);
const oceanMat = makeOceanMaterial(shared);
oceanMat.side = THREE.DoubleSide;
const ocean = new THREE.Mesh(makeOceanGeometry(), oceanMat);
ocean.frustumCulled = false;
scene.add(ocean);

const wave = new Wave();
const waveMesh = new WaveMesh(wave, waveMat);
root.add(waveMesh.mesh);
waveMesh.mesh.visible = false;

const surfer = new Surfer();
root.add(surfer.root);

const sunLight = new THREE.DirectionalLight(0xffffff, 2.2);
scene.add(sunLight, sunLight.target);
const hemi = new THREE.HemisphereLight(0xc4d8ea, 0x1d5560, 2.0);
scene.add(hemi);
const fill = new THREE.DirectionalLight(0xffe2c4, 1.4);
scene.add(fill, fill.target);

const spray = new Spray(6000, makeSprayTexture(64), sky.sunColor);
root.add(spray.points);

const rider = new Rider(wave);
const input = new FootInput(canvas);
const audio = new OceanAudio();

function applyTime(name) {
  sky.set(name);
  const c = sky.sunColor;
  const m = Math.max(c.x, c.y, c.z);
  sunLight.color.setRGB(c.x / m, c.y / m, c.z / m);
  sunLight.intensity = 2.4 * (sky.preset.sunI / 2.4);
  spray.material.uniforms.uSunDir.value.copy(sky.sunDir);
}
applyTime('golden');

// ---------- config ----------
const cfg = { wave: 'left', stance: 'regular', time: 'golden' };
try { Object.assign(cfg, JSON.parse(localStorage.getItem('chabruh.cfg') || '{}')); } catch (e) { /* storage unavailable */ }
function saveCfg() { try { localStorage.setItem('chabruh.cfg', JSON.stringify(cfg)); } catch (e) { /* ignore */ } }
function frontside() { return (cfg.stance === 'regular' && cfg.wave === 'right') || (cfg.stance === 'goofy' && cfg.wave === 'left'); }
function applyCfg() {
  // The sim always runs as a wave peeling toward +x. From the beach, a left
  // (surfer's point of view) peels to the right of the screen, so a right is
  // the mirror image.
  const mirror = cfg.wave === 'right';
  root.scale.x = mirror ? -1 : 1;
  input.frontIsRight = !mirror;
  rider.frontside = frontside();
  surfer.goofy = frontside(); // in the sim frame, facing the wave = goofy on a left
  applyTime(cfg.time);
  ui.update();
}

// ---------- UI ----------
const $ = (id) => document.getElementById(id);
const ui = {
  menu: $('menu'), hud: $('hud'), msg: $('msg'), cue: $('cue'), fade: $('fade'), status: $('status'), dbg: $('debug'),
  padL: $('padL'), padR: $('padR'),
  update() {
    for (const el of document.querySelectorAll('[data-opt]')) {
      el.setAttribute('aria-pressed', String(cfg[el.dataset.opt] === el.dataset.val));
    }
    $('approach').textContent = `${frontside() ? 'Frontside' : 'Backside'} ${cfg.wave}`;
    const fr = input.frontIsRight;
    ui.padL.querySelector('span').textContent = fr ? 'back foot' : 'front foot';
    ui.padR.querySelector('span').textContent = fr ? 'front foot' : 'back foot';
  },
};
for (const el of document.querySelectorAll('[data-opt]')) {
  el.addEventListener('click', () => { cfg[el.dataset.opt] = el.dataset.val; saveCfg(); applyCfg(); });
}
$('go').addEventListener('click', () => {
  audio.start();
  try {
    const de = document.documentElement;
    if (isTouch && de.requestFullscreen && !document.fullscreenElement) de.requestFullscreen({ navigationUI: 'hide' }).then(() => screen.orientation?.lock?.('landscape').catch(() => {})).catch(() => {});
  } catch (e) { /* fullscreen not allowed here */ }
  try { navigator.wakeLock?.request('screen').catch(() => {}); } catch (e) { /* ignore */ }
  ui.menu.hidden = true;
  ui.hud.hidden = false;
  game.demo = false; syncBot();
  ui.fade.classList.remove('on'); game.fading = false;
  beginWait(QUICK ? 6 : 16);
});
$('menuBtn').addEventListener('click', () => {
  ui.menu.hidden = false; ui.hud.hidden = true;
  startDemo();
});
// Title screen: an autopilot rider surfs waves behind the menu.
function startDemo() {
  game.demo = true; syncBot();
  ui.fade.classList.remove('on'); game.fading = false;
  beginWait(APPROACH + 1.5);
}

let msgTimer = 0, cueTimer = 0;
function message(text, secs = 3.2) { ui.msg.textContent = text; ui.msg.classList.add('on'); msgTimer = secs; }
function cue(text, secs = 1.6) { ui.cue.textContent = text; ui.cue.classList.remove('on'); void ui.cue.offsetWidth; ui.cue.classList.add('on'); cueTimer = secs; }
function status(text) { ui.status.textContent = text; }
function buzz(p) { try { navigator.vibrate && navigator.vibrate(p); } catch (e) { /* not allowed */ } }

// ---------- game state ----------
const LINEUP_Z = 3.0;  // where the surfer sits, relative to where the crest will be at catch
const START_U = 5.0;
const APPROACH = 13;   // seconds the set is visible before it arrives
const C = 9.5;         // wave travel speed toward shore (m/s)

const game = {
  state: 'menu', t: 0, timer: 0, rideTime: 0, closeAt: 36, endTimer: 0,
  sitYaw: 0, catchT: 0, camBlend: 0, firstWait: true,
};

const camState = { init: false, pos: new THREE.Vector3(), look: new THREE.Vector3() };

function resetLineup() {
  wave.peelX = -START_U;
  wave.z = -C * APPROACH;
  wave.breakAmt = 0; wave.grow = 0; wave.close = null; wave.version++;
  waveMesh.mesh.visible = false;
  rider.reset();
  spray.clear();
  surfer.pose.mode = 'sit'; surfer.pose.popup = 0;
  game.camBlend = 0;
  camState.init = false;
}
resetLineup();

function beginWait(secs) {
  resetLineup();
  game.state = 'wait';
  game.timer = secs;
  status('Waiting for a set');
}

function beginApproach() {
  game.state = 'approach';
  game.timer = APPROACH;
  waveMesh.mesh.visible = true;
  status('Set on the horizon');
}

function beginRide() {
  game.state = 'ride';
  game.rideTime = 0;
  game.closeAt = flag('shortride') ? 10 : rand(32, 40);
  // place the rider where they are on the swell
  rider.start(START_U, 0.6, 7.5, -0.5);
  const s = sOnFaceAtZ(LINEUP_Z - wave.z);
  if (s !== null) rider.s = Math.min(s, rider.sTop * 0.8);
  game.catchT = 0;
  status('');
  if (!game.demo) cue('Stand up');
  buzz(20);
  audio.hit(0.5, true);
}

function endRide(result) {
  game.state = 'end';
  game.endTimer = 0;
  const text = {
    closed: 'Closed out. You got too deep and the lip landed on you.',
    closeout: 'The wave closed out on you.',
    stalled: 'Stalled out. The wave rolled through without you.',
    shoulder: 'Too far out on the shoulder. The wave lost its push.',
    bogged: 'Bogged down. Not enough speed to stay on it.',
    kickout: 'Kicked out.',
    air: 'Clean finish.',
    airback: 'Flew over the back.',
    landing: 'Blew the landing.',
  }[result] || '';
  if (!game.demo) message(text, 4);
  status('');
}

// arc length on the face at relative z (for the catch)
function sOnFaceAtZ(zr) {
  rider.sampleAt(START_U);
  const { z, y, arc } = rider;
  for (let r = 0; r < rider.topRow; r++) {
    if ((zr - z[r]) * (zr - z[r + 1]) <= 0 && z[r] !== z[r + 1]) {
      const f = (zr - z[r]) / (z[r + 1] - z[r]);
      return arc[r] + (arc[r + 1] - arc[r]) * f;
    }
  }
  return null;
}
function surfaceYAtZ(u, zr) {
  rider.sampleAt(u);
  const { z, y } = rider;
  for (let r = 0; r < KEY_ROW[9]; r++) {
    if ((zr - z[r]) * (zr - z[r + 1]) <= 0 && z[r] !== z[r + 1]) {
      const f = (zr - z[r]) / (z[r + 1] - z[r]);
      return y[r] + (y[r + 1] - y[r]) * f;
    }
  }
  return 0;
}

// ---------- bot (for testing the physics) ----------
function botInput() {
    if (game.state !== 'ride' || rider.state !== 'ride') return { left: 0, right: 0 };
    const sT = rider.sTop * 0.55;
    const thDes = clamp(0.25 * (sT - rider.s) - 0.05 * (rider.u - 4), -0.8, 0.8);
    const err = Math.atan2(Math.sin(thDes - rider.th), Math.cos(thDes - rider.th));
    const c = 0.9 * err - 0.18 * rider.om;
    let front = 0, back = 0;
    if (c > 0) back = clamp(c, 0, 0.7); else front = clamp(-c, 0, 1);
    if (rider.u < 2) front = Math.min(1, front + 0.25);
    return input.frontIsRight ? { left: back, right: front } : { left: front, right: back };
}
function syncBot() { input.bot = BOT || game.demo ? botInput : null; }

// ---------- camera ----------
const tmpPos = new THREE.Vector3(), tmpFwd = new THREE.Vector3(), tmpUp = new THREE.Vector3();
const mir = () => root.scale.x;

function lineupSurferPos(out) {
  const t = game.t;
  const x = 0, z = LINEUP_Z;
  let y = gerstnerHeight(x * mir(), z, t, 1);
  if (waveMesh.mesh.visible) y += surfaceYAtZ(START_U, z - wave.z);
  return out.set(x, y, z);
}

function updateCamera(dt) {
  const desiredPos = new THREE.Vector3(), desiredLook = new THREE.Vector3();
  // lineup camera: behind the surfer looking out to sea
  const sp = new THREE.Vector3();
  if (game.state === 'menu' || game.state === 'wait' || game.state === 'approach') {
    lineupSurferPos(sp);
    const near = game.state === 'approach' ? ease(1 - game.timer / APPROACH) : 0;
    const waveTop = wave.hAt(START_U) * 0.75;
    const lp = new THREE.Vector3(sp.x + 0.4, 1.35 + sp.y * 0.6 + near * 1.5, sp.z + 5.2 + near * 6);
    const ll = new THREE.Vector3(sp.x, 1.0 + near * waveTop * 0.5, sp.z - 30);
    // last seconds of the approach: swing toward the ride camera
    const sw = game.state === 'approach' ? ease(1 - game.timer / 3.2) : 0;
    if (sw > 0) {
      const rp = rideCamPos(sp, new THREE.Vector3()), rl = rideCamLook(sp, new THREE.Vector3());
      lp.lerp(rp, sw); ll.lerp(rl, sw);
    }
    desiredPos.copy(lp); desiredLook.copy(ll);
  } else {
    rider.pose(sp, tmpFwd, tmpUp);
    rideCamPos(sp, desiredPos);
    rideCamLook(sp, desiredLook);
    if (game.state === 'end') {
      const e = ease(game.endTimer / 3);
      desiredPos.y += e * 3; desiredPos.z += e * 6; desiredPos.x += e * 4;
    }
  }
  // to world (mirror)
  desiredPos.x *= mir(); desiredLook.x *= mir();
  if (!camState.init) { camState.pos.copy(desiredPos); camState.look.copy(desiredLook); camState.init = true; }
  const kp = game.state === 'ride' || game.state === 'end' ? 3.2 : 2.0;
  camState.pos.lerp(desiredPos, 1 - Math.exp(-kp * dt));
  camState.look.lerp(desiredLook, 1 - Math.exp(-(kp + 1.5) * dt));
  camera.position.copy(camState.pos);
  camera.lookAt(camState.look);
}

function rideCamPos(sp, out) {
  const H = wave.H0;
  const deep = rider.cover || 0;
  return out.set(sp.x + 11 - deep * 3, H * 0.38 + 1.6 + sp.y * 0.3, wave.z + 13.5 - deep * 2);
}
function rideCamLook(sp, out) {
  return out.set(sp.x - 3.0, sp.y * 0.5 + wave.H0 * 0.3, wave.z + 1.0);
}

// ---------- FX ----------
const colZ = new Float32Array(ROWS), colY = new Float32Array(ROWS);
const wind = new THREE.Vector3(0, 0, -3.2);

function emitRail(dt) {
  if (rider.state !== 'ride' && rider.state !== 'float') return;
  const amt = rider.spray;
  if (amt < 0.12) return;
  rider.pose(tmpPos, tmpFwd, tmpUp);
  const right = new THREE.Vector3().crossVectors(tmpFwd, tmpUp);
  const side = rider.roll >= 0 ? -1 : 1; // spray leaves from the outside rail
  const n = Math.floor(amt * amt * 420 * dt + Math.random());
  const P = wave.peelSpeed;
  for (let i = 0; i < n; i++) {
    const tail = tmpPos.clone().addScaledVector(tmpFwd, rand(-0.8, -0.2)).addScaledVector(right, side * 0.25);
    const out = rider.V * rand(0.25, 0.55);
    spray.emit(
      tail.x - wave.peelX + wave.peelX, tail.y, tail.z,
      -tmpFwd.x * rider.V * 0.15 + right.x * side * out + P * 0.0,
      tmpUp.y * rand(1.5, 4.5) + right.y * side * out + rand(0.5, 2.5),
      -tmpFwd.z * rider.V * 0.15 + right.z * side * out + tmpUp.z * rand(0.5, 2),
      rand(0.5, 1.1), rand(0.05, 0.16), 0);
  }
}

function burst(pos, n, speed, kind = 0, size = 0.12) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2;
    const v = speed * rand(0.3, 1);
    spray.emit(pos.x, pos.y, pos.z, Math.cos(a) * v * 0.7, rand(0.6, 1.4) * speed * 0.8, Math.sin(a) * v * 0.7 + 1, rand(0.6, 1.4), size * rand(0.6, 1.5), kind);
  }
}

let lipAcc = 0, whiteAcc = 0;
function emitWave(dt) {
  if (!waveMesh.mesh.visible || wave.breakAmt < 0.3) return;
  const px = wave.peelX;
  // offshore mist off the top of the pitching lip
  lipAcc += dt * 70 * wave.breakAmt;
  while (lipAcc > 1) {
    lipAcc -= 1;
    const u = rand(-10, 9);
    wave.column(u, colZ, colY, null, null, null);
    let top = KEY_ROW[7];
    for (let r = KEY_ROW[6]; r <= KEY_ROW[12]; r++) if (colY[r] > colY[top]) top = r;
    spray.emit(px + u, colY[top] + 0.1, wave.z + colZ[top], rand(-0.5, 0.5), rand(1.2, 3.2), rand(-3.5, -1.5), rand(1.8, 3.2), rand(0.5, 1.3), 1);
  }
  // explosion where the lip lands, and the churning whitewater behind
  whiteAcc += dt * 160 * wave.breakAmt;
  while (whiteAcc > 1) {
    whiteAcc -= 1;
    const u = rand(-14, -3.5);
    const b = wave.bAt(u);
    if (b < 1.35) continue;
    wave.column(u, colZ, colY, null, null, null);
    const r = b < 2.0 ? KEY_ROW[9] : KEY_ROW[4 + Math.floor(Math.random() * 6)];
    const kind = Math.random() < 0.65 ? 2 : 1;
    spray.emit(px + u + rand(-0.3, 0.3), colY[r] + rand(0, 0.3), wave.z + colZ[r] + rand(-0.2, 0.3),
      rand(-1, 1), rand(2, 6) * (b < 2 ? 1 : 0.5), rand(0.5, 3), rand(0.8, 1.6), rand(0.35, 1.0) * (kind === 1 ? 1.6 : 1), kind);
  }
  // closeout section explodes too
  if (wave.close && wave.close.t > 1.5) {
    for (let i = 0; i < dt * 140; i++) {
      const u = wave.close.x0 - wave.peelX + rand(0, 40);
      const b = wave.bAt(u);
      if (b < 1.4) continue;
      wave.column(u, colZ, colY, null, null, null);
      const r = KEY_ROW[9];
      spray.emit(px + u, colY[r] + 0.2, wave.z + colZ[r], rand(-1, 1), rand(3, 7), rand(0.5, 3), rand(0.9, 1.7), rand(0.4, 1.1), 2);
    }
  }
  // spit out of the tube when it is deep
  if (rider.inBarrel && rider.cover > 0.7 && Math.random() < dt * 0.5) {
    rider.pose(tmpPos, tmpFwd, tmpUp);
    for (let i = 0; i < 90; i++) spray.emit(tmpPos.x - rand(1, 5), tmpPos.y + rand(0, 1.5), tmpPos.z + rand(-0.5, 0.5), rand(8, 16), rand(-0.5, 1.5), rand(0, 2), rand(0.6, 1.2), rand(0.3, 0.8), 1);
  }
}

// ---------- surfer animation ----------
function poseSurfer(dt) {
  const p = surfer.pose;
  p.time += dt;
  if (game.state === 'menu' || game.state === 'wait' || (game.state === 'approach' && game.timer > 3.6)) {
    p.mode = 'sit'; p.popup = 0;
    lineupSurferPos(tmpPos);
    const bob = Math.sin(game.t * 0.9) * 0.05;
    // sit facing out to sea (-z), rocking slightly
    const yaw = Math.PI / 2 + Math.sin(game.t * 0.4) * 0.12;
    tmpFwd.set(Math.cos(yaw) * 0 + Math.sin(game.t * 0.4) * 0.12, 0.05 + bob, -1).normalize();
    const nx = (gerstnerHeight(tmpPos.x * mir() - 1, tmpPos.z, game.t) - gerstnerHeight(tmpPos.x * mir() + 1, tmpPos.z, game.t)) * 0.5 * mir();
    const nz = (gerstnerHeight(tmpPos.x * mir(), tmpPos.z - 1, game.t) - gerstnerHeight(tmpPos.x * mir(), tmpPos.z + 1, game.t)) * 0.5;
    tmpUp.set(nx, 1, nz).normalize();
    tmpPos.y -= 0.06;
    surfer.place(tmpPos, tmpFwd, tmpUp);
    surfer.apply();
    return;
  }
  if (game.state === 'approach') {
    // turn and paddle for shore
    p.mode = 'paddle'; p.popup = 0;
    lineupSurferPos(tmpPos);
    const turn = ease((3.6 - game.timer) / 1.0);
    const zrel = LINEUP_Z - wave.z;
    // board pitch follows the swell under it
    const y1 = surfaceYAtZ(START_U, zrel + 0.8), y0 = surfaceYAtZ(START_U, zrel - 0.8);
    const a = Math.PI * turn;
    tmpFwd.set(Math.sin(a) * 0.15, 0, -Math.cos(a)).normalize();
    const slope = (y1 - y0) / 1.6;
    tmpFwd.y = tmpFwd.z * slope;
    tmpFwd.normalize();
    tmpUp.set(0, 1, -slope).normalize();
    tmpPos.y = surfaceYAtZ(START_U, zrel) + gerstnerHeight(0, LINEUP_Z, game.t) * 0.3 - 0.02;
    surfer.place(tmpPos, tmpFwd, tmpUp);
    surfer.apply();
    return;
  }
  // riding
  p.mode = 'stand';
  p.popup = Math.min(1, p.popup + dt / 0.55);
  rider.pose(tmpPos, tmpFwd, tmpUp);
  const pf = rider.pf, pb = rider.pb;
  const turn = Math.abs(rider.om);
  const tgtCrouch = clamp(0.3 + Math.max(pf, pb) * 0.3 + turn * 0.12 + rider.cover * 0.35 + (rider.state === 'air' ? 0.3 : 0), 0, 1);
  p.crouch += (tgtCrouch - p.crouch) * Math.min(1, dt * 8);
  p.leanX += ((pf - pb) - p.leanX) * Math.min(1, dt * 8);
  p.leanZ += (clamp(-rider.roll * 0.6, -0.6, 0.6) * surfer.facing - p.leanZ) * Math.min(1, dt * 6);
  p.armSpread += (clamp(0.35 + turn * 0.25 + (rider.state === 'air' ? 0.6 : 0), 0, 1.2) - p.armSpread) * Math.min(1, dt * 5);
  p.dragHand += ((rider.frontside && rider.cover > 0.4 ? 1 : 0) - p.dragHand) * Math.min(1, dt * 4);
  p.twist = 0.35 + pf * 0.25;
  if (rider.state === 'wipe') {
    // tumble
    const w = game.endTimer;
    tmpPos.y -= Math.min(1.5, w * 1.2);
    tmpPos.z += w * 2.0;
    const q = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0.3, 0.2).normalize(), w * 6);
    tmpFwd.applyQuaternion(q); tmpUp.applyQuaternion(q);
  }
  surfer.place(tmpPos, tmpFwd, tmpUp, rider.roll);
  surfer.apply();
}

// ---------- HUD ----------
function updateHud() {
  const set = (pad, v, down) => {
    pad.style.setProperty('--p', v.toFixed(3));
    pad.classList.toggle('down', down);
  };
  set(ui.padL, input.left, input.leftDown);
  set(ui.padR, input.right, input.rightDown);
  // move pads under the thumbs
  for (const [pad, side] of [[ui.padL, 'left'], [ui.padR, 'right']]) {
    const p = input.pointerFor(side);
    if (p) { pad.style.left = p.x0 + 'px'; pad.style.top = p.y0 + 'px'; pad.classList.add('placed'); }
  }
  if (DEBUG || game.debug) {
    ui.dbg.hidden = false;
    ui.dbg.textContent = `${game.state}/${rider.state}  V ${rider.V.toFixed(1)}  u ${rider.u.toFixed(1)}  s ${rider.s.toFixed(1)}/${(rider.sTop || 0).toFixed(1)}  b ${(rider.b || 0).toFixed(2)}  th ${(rider.th * 57.3).toFixed(0)}  P ${wave.peelSpeed.toFixed(1)}  f ${rider.pf.toFixed(2)} b ${rider.pb.toFixed(2)}  ${(1 / Math.max(1e-3, fpsAvg)).toFixed(0)}fps`;
  }
}
window.addEventListener('keydown', (e) => { if (e.code === 'Backquote') game.debug = !game.debug; });

// ---------- main loop ----------
let last = performance.now(), fpsAvg = 1 / 60;
function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  // keep the horizontal view wide enough in portrait-ish windows
  camera.fov = w / h < 1.3 ? 62 : 50;
  camera.updateProjectionMatrix();
  spray.material.uniforms.uScale.value = h * 0.9;
}
window.addEventListener('resize', resize);
resize();

function step(dt) {
  game.t += dt;
  shared.uTime.value = game.t;
  input.update(dt);

  if (game.state === 'wait') {
    game.timer -= dt;
    if (game.timer <= APPROACH) beginApproach();
  } else if (game.state === 'approach') {
    game.timer -= dt;
    const k = 1 - game.timer / APPROACH;
    wave.z = -C * game.timer;
    wave.grow = 0.3 + 0.7 * ease(k * 1.15);
    wave.version++;
    if (game.timer < 3.6 && game.timer + dt >= 3.6) { status('Paddle'); buzz(10); }
    if (game.timer <= 0) { wave.z = 0; wave.grow = 1; beginRide(); }
  } else if (game.state === 'ride' || game.state === 'end') {
    game.rideTime += dt;
    game.catchT += dt;
    // the lip starts to pitch right after the catch
    if (wave.breakAmt < 1) { wave.breakAmt = Math.min(1, wave.breakAmt + dt / 2.4); wave.version++; }
    // peel speed drifts so sections race or slow down
    const rt = game.rideTime;
    const Pbase = 9.2 + 1.8 * Math.sin(rt * 0.23 + 0.5) + 1.2 * Math.sin(rt * 0.61 + 2.0);
    wave.peelSpeed = lerp(6.5, Pbase, ease(rt / 4));
    wave.peelX += wave.peelSpeed * dt;
    if (!wave.close && rt > game.closeAt && game.state === 'ride') {
      wave.close = { x0: wave.peelX + rider.u + 34, t: 0 };
      cue('It’s closing out ahead');
    }
    if (wave.close) { wave.close.t += dt; wave.version++; }

    const inp = { front: input.front, back: input.back };
    if (game.catchT < 0.5) { inp.front = 0; inp.back = 0; }
    rider.step(dt, inp);
    for (const ev of rider.events) handleEvent(ev);
    if (game.state === 'ride' && rider.result) endRide(rider.result);
    if (game.state === 'end') {
      game.endTimer += dt;
      if (game.endTimer > 3.8 && !game.fading) { game.fading = true; ui.fade.classList.add('on'); }
      if (game.endTimer > 5.0) {
        game.fading = false;
        ui.fade.classList.remove('on');
        beginWait(game.demo ? APPROACH + 1 : QUICK ? 7 : rand(45, 60));
      }
    }
  }
}

function visual(dt) {
  waveMesh.update(dt);
  // ocean follows the camera; hole under the wave mesh
  const cx = Math.round(camera.position.x / 4) * 4, cz = Math.round(camera.position.z / 4) * 4;
  oceanMat.uniforms.uCenter.value.set(cx, cz);
  if (waveMesh.mesh.visible) {
    const a = (wave.peelX + U_MIN + 6) * mir(), b = (wave.peelX + U_MAX - 6) * mir();
    oceanMat.uniforms.uHole.value.set(Math.min(a, b), Math.max(a, b), wave.z - 44, wave.z + 34);
  } else oceanMat.uniforms.uHole.value.set(0, 0, 0, 0);

  poseSurfer(dt);
  emitRail(dt);
  emitWave(dt);
  spray.update(dt, wind);
  updateCamera(dt);

  sunLight.position.copy(camera.position).addScaledVector(sky.sunDir, 50);
  sunLight.target.position.copy(camera.position);
  fill.position.copy(camera.position).add(new THREE.Vector3(0, 4, 0));
  fill.target.position.copy(camState.look);
  sky.sky.position.copy(camera.position);

  // audio
  let roar = 0;
  if (waveMesh.mesh.visible) roar = clamp(wave.breakAmt * (1 - Math.abs(rider.u - 2) / 25), 0, 1) * (game.state === 'ride' ? 1 : 0.6);
  if (game.state === 'approach') roar = clamp(1 - game.timer / APPROACH, 0, 1) * 0.35;
  audio.update(roar, rider.cover || 0, rider.V || 0, rider.spray || 0, game.state === 'ride');

  if (msgTimer > 0) { msgTimer -= dt; if (msgTimer <= 0) ui.msg.classList.remove('on'); }
  if (cueTimer > 0) { cueTimer -= dt; if (cueTimer <= 0) ui.cue.classList.remove('on'); }
  updateHud();
}

function handleEvent(ev) {
  rider.pose(tmpPos, tmpFwd, tmpUp);
  switch (ev.type) {
    case 'snap': burst(tmpPos.clone().addScaledVector(tmpFwd, -0.6), 70 * ev.strength, 6, 0, 0.12); buzz(18); audio.hit(0.5 * ev.strength); break;
    case 'lip': burst(tmpPos, 50 * ev.strength, 5, 0, 0.14); buzz(12); audio.hit(0.4 * ev.strength); break;
    case 'air': cue('Air'); buzz(10); break;
    case 'land': burst(tmpPos, ev.ok ? 60 : 140, ev.ok ? 4 : 6, ev.ok ? 0 : 2, 0.2); buzz(ev.ok ? 25 : [40, 30, 60]); audio.hit(ev.ok ? 0.6 : 1, !ev.ok); break;
    case 'float': cue('Floater'); break;
    case 'barrelStart': break;
    case 'barrelEnd': if (ev.time > 0.8) cue(`Barrel  ${ev.time.toFixed(1)}s`, 2.2); break;
    case 'wipeout': burst(tmpPos, 260, 7, 2, 0.5); burst(tmpPos, 80, 5, 1, 1.0); buzz([60, 40, 120]); audio.hit(1, true); break;
    case 'over': break;
  }
}

function frame(now) {
  let dt = (now - last) / 1000;
  last = now;
  fpsAvg += (dt - fpsAvg) * 0.05;
  dt = Math.min(dt, 1 / 20);
  // fixed sub-steps for stable physics
  const n = Math.ceil(dt / (1 / 120));
  for (let i = 0; i < n; i++) step(dt / n);
  visual(dt);
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}

applyCfg();
startDemo();
requestAnimationFrame(frame);

// test hooks
window.__game = { game, rider, wave, cfg, step, visual, beginWait, input, camera, renderer, scene, applyCfg, message };
if (BOT && (search.has('autostart') || hash.includes('autostart'))) {
  ui.menu.hidden = true; ui.hud.hidden = false; beginWait(2);
}
