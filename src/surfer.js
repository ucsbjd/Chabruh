// Surfer + board: a simple articulated figure posed procedurally from the
// ride state (compression, lean, banking, arm positions).
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const V = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const UP = V(0, 1, 0);

function makeBoardGeometry() {
  // outline in (x = length, z = width), nose at +x
  const L = 1.92, W = 0.52;
  const shape = new THREE.Shape();
  const half = [];
  const N = 28;
  for (let i = 0; i <= N; i++) {
    const t = i / N; // 0 tail -> 1 nose
    const x = -L / 2 + t * L;
    // widest a bit forward of centre, pulled-in nose, squash tail
    let w = Math.sin(Math.PI * Math.pow(t, 0.85)) ** 0.75 * (W / 2);
    if (t < 0.06) w = Math.max(w, 0.13 * (t / 0.06));
    half.push([x, w]);
  }
  shape.moveTo(half[0][0], 0);
  for (const [x, w] of half) shape.lineTo(x, w);
  for (let i = half.length - 1; i >= 0; i--) shape.lineTo(half[i][0], -half[i][1]);
  shape.lineTo(half[0][0], 0);
  const g = new THREE.ExtrudeGeometry(shape, { depth: 0.035, bevelEnabled: true, bevelThickness: 0.018, bevelSize: 0.02, bevelSegments: 3, curveSegments: 4 });
  // shape is in XY; rotate so width is Z and thickness is Y
  g.rotateX(-Math.PI / 2);
  g.translate(0, -0.02, 0);
  // rocker
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i);
    const t = x / (L / 2);
    p.setY(i, p.getY(i) + (t > 0 ? 0.12 * t ** 2.4 : 0.05 * (-t) ** 2.2));
  }
  g.computeVertexNormals();
  return g;
}

class Limb {
  constructor(parent, radius, mat) {
    this.mesh = new THREE.Mesh(new THREE.CapsuleGeometry(radius, 1, 4, 8), mat);
    this.radius = radius;
    parent.add(this.mesh);
  }
  set(a, b) {
    const d = V().subVectors(b, a);
    const len = d.length();
    this.mesh.position.copy(a).addScaledVector(d, 0.5);
    this.mesh.quaternion.setFromUnitVectors(UP, d.normalize());
    this.mesh.scale.set(1, Math.max(0.01, len - this.radius * 0.6), 1);
  }
}

// Two-bone IK: returns the middle joint for root->target with lengths l1,l2, bending toward pole.
function ik(root, target, l1, l2, pole) {
  const d = V().subVectors(target, root);
  let dist = d.length();
  dist = Math.min(dist, (l1 + l2) * 0.999);
  const dir = d.clone().normalize();
  const a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
  const h = Math.sqrt(Math.max(0, l1 * l1 - a * a));
  const side = pole.clone().sub(dir.clone().multiplyScalar(pole.dot(dir))).normalize();
  return root.clone().addScaledVector(dir, a).addScaledVector(side, h);
}

export class Surfer {
  constructor() {
    this.root = new THREE.Group();     // placed on the wave surface
    this.board = new THREE.Group();
    this.root.add(this.board);
    const boardMat = new THREE.MeshStandardMaterial({ color: 0xf3efe6, roughness: 0.35, metalness: 0.0 });
    const board = new THREE.Mesh(makeBoardGeometry(), boardMat);
    this.board.add(board);
    const stringer = new THREE.Mesh(new THREE.BoxGeometry(1.86, 0.004, 0.008), new THREE.MeshStandardMaterial({ color: 0x8a6a45, roughness: 0.6 }));
    stringer.position.y = 0.035;
    this.board.add(stringer);
    // fins
    const finMat = new THREE.MeshStandardMaterial({ color: 0x223038, roughness: 0.4 });
    for (const [x, z] of [[-0.86, 0], [-0.74, 0.17], [-0.74, -0.17]]) {
      const fin = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.11, 0.008), finMat);
      fin.position.set(x, -0.07, z);
      this.board.add(fin);
    }

    this.body = new THREE.Group(); // in board space
    this.board.add(this.body);
    const suit = new THREE.MeshStandardMaterial({ color: 0x15181c, roughness: 0.55, metalness: 0.05 });
    const suit2 = new THREE.MeshStandardMaterial({ color: 0x1d4a5a, roughness: 0.5 });
    const skin = new THREE.MeshStandardMaterial({ color: 0xb07a55, roughness: 0.6 });
    const hair = new THREE.MeshStandardMaterial({ color: 0x3a2a1c, roughness: 0.8 });
    this.thighL = new Limb(this.body, 0.075, suit);
    this.thighR = new Limb(this.body, 0.075, suit);
    this.shinL = new Limb(this.body, 0.06, suit);
    this.shinR = new Limb(this.body, 0.06, suit);
    this.torso = new Limb(this.body, 0.15, suit2);
    this.upperL = new Limb(this.body, 0.05, suit);
    this.upperR = new Limb(this.body, 0.05, suit);
    this.foreL = new Limb(this.body, 0.042, suit);
    this.foreR = new Limb(this.body, 0.042, suit);
    this.head = new THREE.Mesh(new THREE.SphereGeometry(0.11, 14, 10), skin);
    this.hair = new THREE.Mesh(new THREE.SphereGeometry(0.115, 14, 10, 0, Math.PI * 2, 0, Math.PI * 0.55), hair);
    this.body.add(this.head, this.hair);
    this.handL = new THREE.Mesh(new THREE.SphereGeometry(0.045, 8, 6), skin);
    this.handR = new THREE.Mesh(new THREE.SphereGeometry(0.045, 8, 6), skin);
    this.body.add(this.handL, this.handR);
    this.footL = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.05, 0.26), skin);
    this.footR = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.05, 0.26), skin);
    this.body.add(this.footL, this.footR);

    this.root.traverse((o) => { if (o.isMesh) o.castShadow = false; });
    this.goofy = false;
    this.pose = {
      mode: 'stand', // stand | sit | paddle
      crouch: 0.4, leanX: 0, leanZ: 0, twist: 0.4, armSpread: 0.5,
      dragHand: 0, paddle: 0, popup: 1, time: 0,
    };
  }

  // Facing direction in board space (+z or -z). Regular foot = left foot forward.
  get facing() { return this.goofy ? -1 : 1; }

  apply() {
    const p = this.pose;
    const f = this.facing;
    const fwd = V(0, 0, f);
    const stand = p.popup;
    const t = p.time;

    // --- standing targets ---
    const crouch = p.crouch;
    const backFoot = V(-0.55, 0.06, 0.0);
    const frontFoot = V(0.1, 0.06, 0.0);
    const pelvisS = V(-0.22 + p.leanX * 0.16, 0.98 - crouch * 0.34, f * (-0.02 + p.leanZ * 0.14));
    const spineDir = V(p.leanX * 0.35 + 0.08, 1, 0).add(fwd.clone().multiplyScalar(0.25 + crouch * 0.6 + p.leanZ * 0.25)).normalize();

    // --- lying / paddling targets ---
    const pelvisP = V(-0.35, 0.2, 0);
    const spineP = V(1, 0.18, 0).normalize();
    // --- sitting ---
    const pelvisSit = V(-0.25, 0.14, 0);
    const spineSit = V(0.05, 1, 0).normalize();

    let pelvis, spine;
    if (p.mode === 'sit') { pelvis = pelvisSit; spine = spineSit; }
    else {
      pelvis = pelvisP.clone().lerp(pelvisS, stand);
      spine = spineP.clone().lerp(spineDir, stand).normalize();
    }
    // Riders stay closer to upright than the board on a steep face: lean the
    // upper body from the board normal toward gravity, pivoting at the feet.
    const pivot = V(-0.22, 0.06, 0);
    const qLean = new THREE.Quaternion();
    if (p.mode === 'stand' && this.upLocal) {
      const target = this.upLocal.clone();
      if (target.y < 0.2) target.y = 0.2;
      target.normalize();
      qLean.setFromUnitVectors(UP, target);
      qLean.slerp(new THREE.Quaternion(), 1 - 0.6 * stand);
      pelvis = pelvis.clone().sub(pivot).applyQuaternion(qLean).add(pivot);
      spine = spine.clone().applyQuaternion(qLean);
    }
    const torsoLen = 0.52;
    const chest = pelvis.clone().addScaledVector(spine, torsoLen);
    const neck = pelvis.clone().addScaledVector(spine, torsoLen + 0.12);
    this.torso.set(pelvis.clone().addScaledVector(spine, 0.08), chest);
    this.head.position.copy(neck).addScaledVector(spine, 0.08);
    this.hair.position.copy(this.head.position).addScaledVector(spine, 0.01);
    this.hair.quaternion.setFromUnitVectors(UP, spine);

    // hips & shoulders, rotated by twist (chest opens toward the nose)
    const hipAxis = V(1, 0, 0);
    const shAxis = V(Math.cos(p.twist * stand), 0, -f * Math.sin(p.twist * stand));
    if (p.mode === 'paddle' && stand < 0.5) shAxis.set(0, 0, 1);
    const hipBack = pelvis.clone().addScaledVector(hipAxis, -0.1);
    const hipFront = pelvis.clone().addScaledVector(hipAxis, 0.1);
    if (stand < 0.5 && p.mode !== 'sit') { hipBack.set(pelvis.x - 0.05, pelvis.y, -0.09); hipFront.set(pelvis.x - 0.05, pelvis.y, 0.09); }
    const shBack = chest.clone().addScaledVector(shAxis, -0.19);
    const shFront = chest.clone().addScaledVector(shAxis, 0.19);

    // legs
    // regular: left foot front. In board space front foot is toward +x.
    let fFoot, bFoot, kneePole;
    if (p.mode === 'sit') {
      fFoot = V(0.0, -0.45, 0.32); bFoot = V(-0.3, -0.45, -0.32);
      kneePole = V(1, 0.3, 0);
      hipBack.set(pelvis.x, pelvis.y, -0.1); hipFront.set(pelvis.x, pelvis.y, 0.1);
      fFoot = V(0.05, -0.5, 0.18); bFoot = V(0.05, -0.5, -0.18);
    } else if (stand < 0.5) {
      // lying: legs trailing behind
      fFoot = V(-1.15, 0.12 + Math.sin(t * 3) * 0.03, 0.1);
      bFoot = V(-1.15, 0.12 + Math.cos(t * 3) * 0.03, -0.1);
      kneePole = V(0, -1, 0);
    }
    if (p.mode === 'sit' || stand < 0.5) {
      const kF = ik(hipFront, fFoot, 0.46, 0.46, kneePole || V(1, 0, 0));
      const kB = ik(hipBack, bFoot, 0.46, 0.46, kneePole || V(1, 0, 0));
      this.thighL.set(hipFront, kF); this.shinL.set(kF, fFoot);
      this.thighR.set(hipBack, kB); this.shinR.set(kB, bFoot);
      this.footL.position.copy(fFoot); this.footR.position.copy(bFoot);
    } else {
      const pole = V(0.15, 0, f).normalize();
      const kF = ik(hipFront, frontFoot, 0.46, 0.46, pole);
      const kB = ik(hipBack, backFoot, 0.46, 0.46, V(-0.2, 0, f).normalize());
      this.thighL.set(hipFront, kF); this.shinL.set(kF, frontFoot);
      this.thighR.set(hipBack, kB); this.shinR.set(kB, backFoot);
      this.footL.position.copy(frontFoot); this.footR.position.copy(backFoot);
    }
    this.footL.rotation.set(0, 0.25, 0);
    this.footR.rotation.set(0, 0.45, 0);

    // arms
    let hF, hB;
    if (p.mode === 'sit') {
      hF = V(0.15, 0.12, 0.25); hB = V(0.15, 0.12, -0.25);
    } else if (stand < 0.5) {
      // paddling strokes
      const a = t * 5.2;
      hF = V(0.35 + Math.cos(a) * 0.45, 0.05 + Math.min(0, Math.sin(a)) * 0.35 + Math.max(0, Math.sin(a)) * 0.15, 0.32);
      hB = V(0.35 + Math.cos(a + Math.PI) * 0.45, 0.05 + Math.min(0, Math.sin(a + Math.PI)) * 0.35 + Math.max(0, Math.sin(a + Math.PI)) * 0.15, -0.32);
    } else {
      const spread = p.armSpread;
      hF = V(0.55 + spread * 0.25, 0.95 - crouch * 0.3 + spread * 0.15, f * (0.22 + p.leanZ * 0.2));
      hB = V(-0.75 - spread * 0.2, 0.75 - crouch * 0.25 + spread * 0.2, f * (0.2 - p.leanZ * 0.1));
      if (p.dragHand > 0) {
        // trailing hand reaches toward the wave face
        hB.lerp(V(-0.55, 0.15, -f * 0.25 + f * 0.55), p.dragHand);
      }
    }
    if (p.mode === 'stand') {
      hF = hF.clone().sub(pivot).applyQuaternion(qLean).add(pivot);
      hB = hB.clone().sub(pivot).applyQuaternion(qLean).add(pivot);
    }
    const elbowPole = V(0, -1, 0);
    const eF = ik(shFront, hF, 0.3, 0.28, elbowPole.clone().add(V(0, 0, f * 0.3)));
    const eB = ik(shBack, hB, 0.3, 0.28, elbowPole.clone().add(V(0, 0, f * 0.3)));
    this.upperL.set(shFront, eF); this.foreL.set(eF, hF);
    this.upperR.set(shBack, eB); this.foreR.set(eB, hB);
    this.handL.position.copy(hF); this.handR.position.copy(hB);

    if (this.model) {
      const footF = p.mode === 'sit' || stand < 0.5 ? fFoot : frontFoot;
      const footB = p.mode === 'sit' || stand < 0.5 ? bFoot : backFoot;
      // model's left side: across the board when standing, across the body otherwise
      const left = p.mode === 'stand' && stand >= 0.5 ? V(f > 0 ? 1 : -1, 0, 0) : V(0, 0, -1);
      if (p.mode === 'stand' && stand >= 0.5) left.applyQuaternion(qLean);
      this.driveModel({ pelvis, spine, neck, left, footF, footB, hF, hB, shAxis, mode: p.mode, stand, f });
    }
  }

  // ---- skinned human model ----
  load(url, fallback) {
    new GLTFLoader().load(url, (gltf) => {
      const model = gltf.scene;
      const bones = {};
      model.traverse((o) => {
        if (o.isBone) bones[o.name.replace(/^mixamorig:?/, '')] = o;
        if (o.isSkinnedMesh) o.frustumCulled = false;
      });
      if (!bones.Hips) return;
      const suit = new THREE.MeshStandardMaterial({ color: 0xffffff, vertexColors: true, roughness: 0.42, metalness: 0.0 });
      const joints = new THREE.MeshStandardMaterial({ color: 0xbfc4c8, vertexColors: true, roughness: 0.5 });
      model.traverse((o) => {
        if (!o.isSkinnedMesh) return;
        // colour by bone: head, hands and feet are skin, the rest is wetsuit
        const g = o.geometry, idx = g.attributes.skinIndex, wt = g.attributes.skinWeight;
        const names = o.skeleton.bones.map((b) => b.name);
        const colors = new Float32Array(idx.count * 3);
        const skinC = new THREE.Color(0xc99470), suitC = new THREE.Color(0x14181b), panel = new THREE.Color(0x1f4f5e);
        for (let i = 0; i < idx.count; i++) {
          let skinW = 0, panelW = 0;
          for (let k = 0; k < 4; k++) {
            const n = names[idx.getComponent(i, k)] || '', w = wt.getComponent(i, k);
            if (/Head|Eye|Hand|Thumb|Index|Middle|Ring|Pinky|Foot|Toe/.test(n)) skinW += w;
            else if (/Spine1|Spine2/.test(n)) panelW += w * 0.35;
          }
          const c = suitC.clone().lerp(panel, Math.min(1, panelW)).lerp(skinC, Math.min(1, skinW * 1.6));
          colors[i * 3] = c.r; colors[i * 3 + 1] = c.g; colors[i * 3 + 2] = c.b;
        }
        g.setAttribute('color', new THREE.BufferAttribute(colors, 3));
        o.material = /Joints/i.test(o.name) ? joints : suit;
      });
      // hair
      const hair = new THREE.Mesh(new THREE.SphereGeometry(1, 18, 12, 0, Math.PI * 2, 0, Math.PI * 0.47), new THREE.MeshStandardMaterial({ color: 0x2a1c10, roughness: 0.85 }));
      bones.Head.add(hair);
      hair.scale.set(9.4, 9.0, 10.6); // bone space is in centimetres
      hair.position.set(0, 10.2, 0.4);
      hair.rotation.x = -0.35;

      this.body.add(model);
      model.updateMatrixWorld(true);
      this.bones = bones;
      this.rest = {};
      for (const [n, b] of Object.entries(bones)) this.rest[n] = b.quaternion.clone();
      const d = (a, b) => this.toBody(bones[a]).distanceTo(this.toBody(bones[b]));
      this.dims = { thigh: d('LeftUpLeg', 'LeftLeg'), shin: d('LeftLeg', 'LeftFoot'), upper: d('LeftArm', 'LeftForeArm'), fore: d('LeftForeArm', 'LeftHand') };
      this.model = model;
      // the simple figure is only a stand-in until the model loads
      for (const m of [this.thighL, this.thighR, this.shinL, this.shinR, this.torso, this.upperL, this.upperR, this.foreL, this.foreR]) m.mesh.visible = false;
      for (const m of [this.head, this.hair, this.handL, this.handR, this.footL, this.footR]) m.visible = false;
      this.apply();
    }, undefined, (e) => {
      if (fallback) this.load(fallback);
      else console.warn('surfer model failed to load; using the simple figure', e);
    });
  }

  toBody(obj, out = V()) {
    obj.getWorldPosition(out);
    return this.body.worldToLocal(out);
  }

  // rotation of obj relative to the body group (no mirroring involved)
  bodyQuat(obj, out = new THREE.Quaternion()) {
    out.identity();
    for (let o = obj; o && o !== this.body; o = o.parent) out.premultiply(o.quaternion);
    return out;
  }

  setBodyQuat(bone, q) {
    const pq = this.bodyQuat(bone.parent).invert();
    bone.quaternion.copy(pq.multiply(q));
    bone.updateMatrixWorld(true);
  }

  // rotate bone so that its child points at target (body space)
  aim(bone, child, target) {
    const a = this.toBody(bone), b = this.toBody(child);
    const cur = b.sub(a).normalize(), want = target.clone().sub(a).normalize();
    if (cur.lengthSq() < 1e-8 || want.lengthSq() < 1e-8) return;
    const q = new THREE.Quaternion().setFromUnitVectors(cur, want).multiply(this.bodyQuat(bone));
    this.setBodyQuat(bone, q);
  }

  // rotate bone so that one of its local axes lines up with dir (body space)
  alignAxis(bone, axis, dir) {
    const bq = this.bodyQuat(bone);
    const cur = axis.clone().applyQuaternion(bq).normalize();
    const q = new THREE.Quaternion().setFromUnitVectors(cur, dir.clone().normalize()).multiply(bq);
    this.setBodyQuat(bone, q);
  }

  driveModel(j) {
    const B = this.bones;
    for (const [n, q] of Object.entries(this.rest)) B[n].quaternion.copy(q);
    // hips: up along the spine, left across the body
    const up = j.spine.clone().normalize();
    const left = j.left.clone().sub(up.clone().multiplyScalar(j.left.dot(up))).normalize();
    const fwd = V().crossVectors(left, up);
    const m = new THREE.Matrix4().makeBasis(left, up, fwd);
    this.setBodyQuat(B.Hips, new THREE.Quaternion().setFromRotationMatrix(m));
    const hp = this.body.localToWorld(j.pelvis.clone());
    B.Hips.position.copy(B.Hips.parent.worldToLocal(hp));
    B.Hips.updateMatrixWorld(true);

    // spine curls toward the neck target; shoulders open toward the nose
    this.aim(B.Spine, B.Spine2, j.neck.clone().lerp(j.pelvis, 0.35));
    this.aim(B.Spine2, B.Neck, j.neck);
    const sh = j.shAxis.clone();
    if (sh.dot(left) < 0) sh.negate();
    sh.sub(up.clone().multiplyScalar(sh.dot(up)));
    if (sh.lengthSq() > 1e-6) this.alignAxis(B.Spine2, V(1, 0, 0), sh);
    // head looks down the line (toward the nose) when standing
    if (j.mode === 'stand') this.alignAxis(B.Head, V(0, 0, 1), V(1, -0.25, 0).lerp(fwd, 0.3));

    // legs: each model leg takes the foot on its own side
    const pole = fwd.clone().add(V(0, j.mode === 'sit' ? 0.4 : 0, 0)).normalize();
    const lf = j.footF.clone().sub(j.pelvis).dot(left) >= j.footB.clone().sub(j.pelvis).dot(left);
    const feet = { Left: lf ? j.footF : j.footB, Right: lf ? j.footB : j.footF };
    const { thigh, shin, upper, fore } = this.dims;
    for (const side of ['Left', 'Right']) {
      const hip = this.toBody(B[side + 'UpLeg']);
      const foot = feet[side].clone().add(V(0, 0.07, 0));
      const knee = ik(hip, foot, thigh, shin, pole);
      this.aim(B[side + 'UpLeg'], B[side + 'Leg'], knee);
      this.aim(B[side + 'Leg'], B[side + 'Foot'], foot);
      if (j.mode === 'stand') {
        // feet flat across the board, toes toward the facing side
        const toe = foot.clone().add(V(0.05, -0.06, j.f * 0.16));
        this.aim(B[side + 'Foot'], B[side + 'ToeBase'], toe);
      }
    }
    // arms
    const lh = j.hF.clone().sub(j.pelvis).dot(left) >= j.hB.clone().sub(j.pelvis).dot(left);
    const hands = { Left: lh ? j.hF : j.hB, Right: lh ? j.hB : j.hF };
    const elbowPole = j.mode === 'stand' ? V(0, -1, 0).addScaledVector(fwd, -0.3).normalize() : fwd.clone().negate();
    for (const side of ['Left', 'Right']) {
      const shp = this.toBody(B[side + 'Arm']);
      const elbow = ik(shp, hands[side], upper, fore, elbowPole);
      this.aim(B[side + 'Arm'], B[side + 'ForeArm'], elbow);
      this.aim(B[side + 'ForeArm'], B[side + 'Hand'], hands[side]);
    }
  }

  // Place the board in the world: position, forward (nose) and up vectors.
  place(pos, forward, up, roll = 0) {
    const fwd = forward.clone().normalize();
    const u = up.clone().sub(fwd.clone().multiplyScalar(up.dot(fwd))).normalize();
    const right = V().crossVectors(fwd, u);
    const m = new THREE.Matrix4().makeBasis(fwd, u, right);
    this.root.position.copy(pos);
    this.root.quaternion.setFromRotationMatrix(m);
    if (roll) this.root.quaternion.multiply(new THREE.Quaternion().setFromAxisAngle(V(1, 0, 0), roll));
    // world up in board space (the parent may be mirrored, which keeps y)
    this.upLocal = UP.clone().applyQuaternion(this.root.quaternion.clone().invert());
  }
}
