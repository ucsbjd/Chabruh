"""Headless Blender: builds the surfer (an MPFB human, rigged, with shorts, hair, tattoo and a rainbow shortboard),
poses him, and renders raw passes for every pose. See docs/foundry.md.

  blender -b --python tools/foundry/render_character.py -- <out_dir> <decal_dir> [pose_count]

Units are meters, the board's underside centre is the origin (the sprite anchor), the surfer rides toward -X
(the image's left), faces +Y (away from the camera) and is seen from behind and slightly from the side.

Passes per pose (all at 2x the final size, the packer downsamples):
  m0, m1, m2: flat emission, one-hot per region, three regions per pass (REGION_GROUPS)
  light:      white diffuse under the key sun only
Regions: 0 skin, 1 shorts, 2 board, 3 hair, 4 tattoo ink, 5 trim (aqua), 6 stripe A (pink), 7 stripe B (yellow).
"""
import json
import os
import math
import random
import sys

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

# Must match game/scripts/surfer_sprites.gd (FRAME_SIZE, ANCHOR, FRAME_METERS; the toon frame is taller) and check_frames.py.
FRAME_W, FRAME_H = 468, 420  # taller than the Kling frames so a rolled board is not cut off; same anchor from the top-left
PX_PER_M = 360 / 1.85  # the same scale as the Kling frames, so both draw at one size
ANCHOR_X, ANCHOR_Y = 203.2, 355.3
SS = 2
CAMERA_YAW = math.radians(18.0)
SUN_DIRECTION = Vector((-0.55, -0.45, 0.70)).normalized()
PERSON_HEIGHT = 1.80
REGION_GROUPS = [(0, 1, 2), (3, 4, 5), (6, 7, -1)]

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0])
DECALS = os.path.abspath(argv[1])
POSE_LIMIT = int(argv[2]) if len(argv) > 2 else 99
if len(argv) > 3:  # a debug camera yaw in degrees (90 is a side view), to inspect the rig from another side
    CAMERA_YAW = math.radians(float(argv[3]))

# Board-local layout. The deck top is DECK_Z above the origin; ankles sit ANKLE_H over the sole.
DECK_Z = 0.08
FOOT_X = {"L": -0.40, "R": 0.36}  # left foot forward, toward the nose at -X

# name, board roll, board pitch, board lift, hips down, hip yaw, bend forward, lean toward travel, twist, look,
# left hand offset from the shoulder, right hand offset, (all degrees and meters, world axes: +Y is the wave)
POSES = [
    dict(name="trim", roll=0, pitch=2, lift=0, down=0.12, yaw=26, bend=14, lean=0, twist=-8, look=50,
         hl=(-0.40, 0.18, -0.38), hr=(0.46, 0.05, -0.34)),
    # Poses 2 to 4 follow the reference clip: a low drive with the torso almost horizontal and one arm trailing,
    # a top turn at the lip with the board on its rail and the body thrown back, a cutback with the head turned back.
    dict(name="bottom_turn", roll=-14, pitch=2, lift=0, down=0.26, yaw=20, bend=62, lean=8, twist=-14, look=40,
         hl=(-0.12, 0.30, -0.42), hr=(0.58, 0.02, -0.10)),
    dict(name="top_turn", roll=-52, pitch=10, lift=0.02, down=0.22, yaw=18, bend=-6, lean=26, twist=40, look=70,
         hl=(-0.34, 0.16, 0.12), hr=(0.40, -0.08, 0.50)),
    dict(name="cutback", roll=16, pitch=-2, lift=0, down=0.24, yaw=36, bend=44, lean=-8, twist=-60, look=-60,
         hl=(-0.20, 0.34, -0.34), hr=(0.52, -0.12, -0.02)),
    dict(name="barrel", roll=-10, pitch=2, lift=0, down=0.30, yaw=30, bend=52, lean=8, twist=-24, look=55,
         hl=(-0.26, 0.40, -0.46), hr=(0.20, -0.02, -0.18)),
    dict(name="air", roll=-26, pitch=22, lift=0.12, down=0.26, yaw=24, bend=12, lean=4, twist=12, look=45,
         hl=(-0.50, 0.12, 0.36), hr=(0.50, 0.12, 0.42)),
]
POSES = POSES[:POSE_LIMIT]


# ---------------------------------------------------------------- materials
MASK_MATS = []  # (material, [three value nodes])


def region_material(name, region=None, decal=None, decal_region=None, decal_box=None):
    """Emission material that paints a one-hot region code; `decal` (an image) switches some of it to another region."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    new = nt.nodes.new
    link = nt.links.new
    out, em = new("ShaderNodeOutputMaterial"), new("ShaderNodeEmission")
    link(em.outputs["Emission"], out.inputs["Surface"])
    idx = new("ShaderNodeValue")
    idx.outputs[0].default_value = region
    idx_socket = idx.outputs[0]
    if decal:
        cx, cz, w, h = decal_box
        coord, sep, comb, mapping = new("ShaderNodeTexCoord"), new("ShaderNodeSeparateXYZ"), new("ShaderNodeCombineXYZ"), new("ShaderNodeMapping")
        link(coord.outputs["Object"], sep.inputs[0])
        link(sep.outputs["X"], comb.inputs["X"])
        link(sep.outputs["Z"], comb.inputs["Y"])
        mapping.inputs["Location"].default_value = (0.5 - cx / w, 0.5 - cz / h, 0)
        mapping.inputs["Scale"].default_value = (1 / w, 1 / h, 1)
        link(comb.outputs[0], mapping.inputs["Vector"])
        tex = new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(decal)
        tex.image.colorspace_settings.name = "Non-Color"
        tex.interpolation = "Closest"
        tex.extension = "CLIP"
        link(mapping.outputs[0], tex.inputs["Vector"])
        back = new("ShaderNodeMath")
        back.operation = "GREATER_THAN"
        link(sep.outputs["Y"], back.inputs[0])
        back.inputs[1].default_value = 0.0  # rest pose: the back of the body is +Y here (the front faces -Y)
        mask = new("ShaderNodeMath")
        mask.operation = "MULTIPLY"
        sepc = new("ShaderNodeSeparateColor")
        link(tex.outputs["Color"], sepc.inputs[0])
        link(sepc.outputs["Red"], mask.inputs[0])
        link(back.outputs[0], mask.inputs[1])
        mix = new("ShaderNodeMix")
        mix.data_type = "FLOAT"
        link(mask.outputs[0], mix.inputs["Factor"])
        mix.inputs[2].default_value = region
        mix.inputs[3].default_value = decal_region
        idx_socket = mix.outputs[0]
    consts, comps = [], []
    for k in range(3):
        c = new("ShaderNodeValue")
        consts.append(c)
        sub = new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        link(idx_socket, sub.inputs[0])
        link(c.outputs[0], sub.inputs[1])
        ab = new("ShaderNodeMath")
        ab.operation = "ABSOLUTE"
        link(sub.outputs[0], ab.inputs[0])
        lt = new("ShaderNodeMath")
        lt.operation = "LESS_THAN"
        link(ab.outputs[0], lt.inputs[0])
        lt.inputs[1].default_value = 0.5
        comps.append(lt)
    comb = new("ShaderNodeCombineColor")
    for k, ch in enumerate(("Red", "Green", "Blue")):
        link(comps[k].outputs[0], comb.inputs[ch])
    link(comb.outputs[0], em.inputs["Color"])
    MASK_MATS.append((mat, consts))
    return mat


def set_mask_pass(group):
    for _, consts in MASK_MATS:
        for k, c in enumerate(consts):
            c.outputs[0].default_value = group[k] if group[k] >= 0 else -10


# ---------------------------------------------------------------- body
def add_armature_skin(obj, rig, groups_from=None):
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    obj.parent = rig


def build_human():
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService
    macro = TargetService.get_default_macro_info_dict()
    macro.update(gender=1.0, age=0.5, muscle=0.62, weight=0.30, proportions=0.5)
    height = 0.5
    for _ in range(5):  # step the height macro toward PERSON_HEIGHT
        macro["height"] = height
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        base = HumanService.create_human(mask_helpers=False, detailed_helpers=True, extra_vertex_groups=True,
                                         macro_detail_dict=dict(macro), scale=0.1)
        h = base.dimensions.z
        height = min(1.0, max(0.0, height + (PERSON_HEIGHT - h) / 1.65))
        if abs(h - PERSON_HEIGHT) < 0.02:
            break
    print("foundry: human height", round(base.dimensions.z, 3), "macro", round(macro["height"], 3))
    # Bake the macro shape keys, then drop the helper geometry (everything outside the body group).
    if base.data.shape_keys:
        bpy.context.view_layer.objects.active = base
        base.select_set(True)
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    rig = HumanService.add_builtin_rig(base, "default", import_weights=True)
    gi = base.vertex_groups["body"].index
    bm = bmesh.new()
    bm.from_mesh(base.data)
    dl = bm.verts.layers.deform.active
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v[dl].get(gi, 0.0) < 0.5], context="VERTS")
    bm.to_mesh(base.data)
    bm.free()
    return base, rig


def head_box(base):
    gi = base.vertex_groups["head"].index
    pts = [v.co.copy() for v in base.data.vertices if any(g.group == gi and g.weight > 0.6 for g in v.groups)]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return (lo + hi) / 2, (hi - lo) / 2


def build_shorts(base, rig, mats):
    """A shell copied from the body between waist and mid-thigh, inflated a little, with trim regions on it."""
    pts = [v.co for v in base.data.vertices]
    hip_z = max(rig.pose.bones["upperleg01.L"].head.z, 0.0)
    legs = rig.pose.bones["lowerleg01.L"].head.z
    top = hip_z + 0.07
    hem = hip_z - 0.68 * (hip_z - legs)
    copy = base.copy()
    copy.data = base.data.copy()
    bpy.context.collection.objects.link(copy)
    bm = bmesh.new()
    bm.from_mesh(copy.data)
    bm.faces.ensure_lookup_table()
    keep = {f.index for f in bm.faces if all(hem <= v.co.z <= top and abs(v.co.x) < 0.3 for v in f.verts)}  # not the hands
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.007
    xw = max(abs(v.co.x) for v in bm.verts if v.co.z > top - 0.12)
    palm = bpy.data.images.load(f"{DECALS}/palm.png")
    pw, ph = palm.size
    px = list(palm.pixels)
    copy.data.materials.clear()
    for m in (mats["shorts"], mats["trim"]):
        copy.data.materials.append(m)
    palm_box = (0.115, hip_z - 0.10, 0.17, 0.17)  # x centre (the left thigh, front), z centre, width, height
    for f in bm.faces:
        c = f.calc_center_median()
        trim = c.z > top - 0.06
        trim |= abs(c.x) > xw * 0.9 and abs(f.normal.x) > 0.55
        if c.y < 0 and c.x > 0 and f.normal.y < -0.3:
            u = int(((c.x - palm_box[0]) / palm_box[2] + 0.5) * pw)
            v = int(((c.z - palm_box[1]) / palm_box[3] + 0.5) * ph)
            if 0 <= u < pw and 0 <= v < ph and px[(v * pw + u) * 4] > 0.5:
                trim = True
        f.material_index = 1 if trim else 0
    bm.to_mesh(copy.data)
    bm.free()
    copy.name = "shorts"
    return copy


def make_cones(bm, placements):
    for p, d, length, base in placements:
        d = Vector(d).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
        mat = Matrix.Translation(Vector(p) + d * length / 2) @ rot
        bmesh.ops.create_cone(bm, cap_ends=False, cap_tris=False, segments=5, radius1=base, radius2=0.0, depth=length, matrix=mat)


def build_hair(base, rig, mats):
    """A spiky sun-bleached mullet (short spikes on top, long ones down the nape) and a mustache."""
    center, half = head_box(base)
    r = max(half.x, half.y) * 0.98
    rnd = random.Random(7)
    bm = bmesh.new()
    placements = []
    for _ in range(90):  # the top and the sides
        a, b = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.15, 1.15)
        d = Vector((math.cos(a) * math.cos(b), math.sin(a) * math.cos(b) * 0.9, math.sin(b)))
        if d.y < -0.35:  # keep the face clear (the face is -Y in the body's own space)
            continue
        p = center + Vector((d.x * r, d.y * r, d.z * half.z * 0.98))
        placements.append((p, d * 1.0 + Vector((0, 0.25, 0.5)), rnd.uniform(0.07, 0.11), 0.030))
    for _ in range(70):  # the mullet: long strands hanging from the back of the skull
        a, b = rnd.uniform(math.radians(20), math.radians(160)), rnd.uniform(-0.55, 0.25)
        d = Vector((math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), math.sin(b)))
        p = center + Vector((d.x * r, d.y * r, d.z * half.z))
        placements.append((p, Vector((d.x * 0.4, 0.5, -1.0)), rnd.uniform(0.14, 0.24) * (1.15 if b < 0 else 0.9), 0.034))
    make_cones(bm, placements)
    cap = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0,
                                    matrix=Matrix.Translation(center + Vector((0, r * 0.1, r * 0.06))) @ Matrix.Diagonal((r * 1.06, r * 1.0, half.z * 1.05, 1)))
    # Strip the part of the cap that would cover the face.
    face_verts = [v for v in cap["verts"] if v.co.y < center.y - r * 0.45 or v.co.z < center.z - half.z * 0.5]
    bmesh.ops.delete(bm, geom=face_verts, context="VERTS")
    hair = bpy.data.objects.new("hair", bpy.data.meshes.new("hair"))
    bm.to_mesh(hair.data)
    bm.free()
    must = bmesh.new()
    bmesh.ops.create_uvsphere(must, u_segments=12, v_segments=8, radius=1.0,
                              matrix=Matrix.Translation(center + Vector((0, -r * 1.0, -half.z * 0.42))) @ Matrix.Diagonal((r * 0.42, r * 0.10, r * 0.10, 1)))
    mus = bpy.data.objects.new("mustache", bpy.data.meshes.new("mustache"))
    must.to_mesh(mus.data)
    must.free()
    out = []
    for o in (hair, mus):
        bpy.context.collection.objects.link(o)
        o.data.materials.append(mats["hair"])
        head = o.vertex_groups.new(name="head")
        head.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        add_armature_skin(o, rig)
        for poly in o.data.polygons:
            poly.use_smooth = False
        out.append(o)
    return out


def build_board(mats):
    """A rainbow shortboard lofted from sections, 1.9 m long, the nose toward -X, in five bands along its length."""
    N, M = 40, 16
    bm = bmesh.new()
    L = 0.95
    rings = []
    for i in range(N + 1):
        t = -1 + 2 * i / N  # -1 nose .. +1 tail
        p = 2.4 if t < 0 else 3.2
        w = 0.215 * max(1 - abs(t) ** p, 0.0) ** 0.55 + 0.004
        h = 0.045 * max(1 - t * t, 0.0) ** 0.5 + 0.004
        lift = 0.11 * max(-t, 0) ** 3 + 0.03 * max(t, 0) ** 3  # nose and tail rocker
        ring = []
        for k in range(M):
            a = 2 * math.pi * k / M
            z = h * math.sin(a) * (0.55 if math.sin(a) < 0 else 1.0)  # flatter underside
            ring.append(bm.verts.new((t * L, w * math.cos(a), h * 0.55 + z + lift)))
        rings.append(ring)
    for i in range(N):
        band = min(int((i + 0.5) / N * 5), 4)
        for k in range(M):
            f = bm.faces.new((rings[i][k], rings[i][(k + 1) % M], rings[i + 1][(k + 1) % M], rings[i + 1][k]))
            f.material_index = band
            f.smooth = True
    bm.normal_update()
    board = bpy.data.objects.new("board", bpy.data.meshes.new("board"))
    bm.to_mesh(board.data)
    bm.free()
    bpy.context.collection.objects.link(board)
    for key in ("stripe_a", "shorts", "stripe_b", "trim", "board"):  # pink, coral, yellow, aqua, cream
        board.data.materials.append(mats[key])
    return board


# ---------------------------------------------------------------- rig helpers
def world(rig, name):
    return rig.matrix_world @ rig.pose.bones[name].matrix


def set_world(rig, name, M):
    rig.pose.bones[name].matrix = rig.matrix_world.inverted() @ M


def update():
    bpy.context.view_layer.update()


def rotate_bone(rig, name, R3, pivot=None):
    M = world(rig, name)
    c = M.translation if pivot is None else pivot
    set_world(rig, name, Matrix.Translation(c) @ R3.to_4x4() @ Matrix.Translation(-c) @ M)
    update()


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
    update()


def add_ik(rig, bone, target, pole, chain, locks):
    c = rig.pose.bones[bone].constraints.new("IK")
    c.target, c.pole_target, c.chain_count, c.use_tail = target, pole, chain, True
    for name in locks:
        pb = rig.pose.bones[name]
        pb.lock_ik_x = pb.lock_ik_y = pb.lock_ik_z = True
    return c


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.05
    bpy.context.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e


# ---------------------------------------------------------------- scene
def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.filter_width = 0.8
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = FRAME_W * SS, FRAME_H * SS
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.display_settings.display_device = "sRGB"
    scene.world = bpy.data.worlds.new("black")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = FRAME_W / PX_PER_M
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.shift_x = (FRAME_W / 2 - ANCHOR_X) / FRAME_W
    cam_data.shift_y = (ANCHOR_Y - FRAME_H / 2) / FRAME_W
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = Vector((math.sin(CAMERA_YAW), -math.cos(CAMERA_YAW), 0.0)) * 12.0
    cam.rotation_euler = (math.pi / 2, 0, CAMERA_YAW)
    scene.camera = cam
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.0
    sun_data.angle = 0.0
    sun = bpy.data.objects.new("sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = Vector((0, 0, -1)).rotation_difference(-SUN_DIRECTION).to_euler()
    return scene, cam


def main():
    base, rig = build_human()
    bpy.context.view_layer.objects.active = rig
    rig.rotation_euler.z = math.pi  # MPFB faces -Y; the surfer must face +Y, away from the camera
    update()
    mats = {
        "skin": region_material("skin", 0, decal=f"{DECALS}/tattoo.png", decal_region=4,
                                decal_box=(0.0, rig.data.bones["spine03"].head_local.z + 0.03, 0.56, 0.60)),
        "shorts": region_material("shorts", 1), "board": region_material("board", 2), "hair": region_material("hair", 3),
        "trim": region_material("trim", 5), "stripe_a": region_material("stripe_a", 6), "stripe_b": region_material("stripe_b", 7),
    }
    base.data.materials.clear()
    base.data.materials.append(mats["skin"])
    shorts = build_shorts(base, rig, mats)
    hair = build_hair(base, rig, mats)
    # (the copy already carries the body's Armature modifier and parent; adding another would deform it twice)
    # Relax the stretching and pinching a bent hip puts in the shell, so the shorts hang instead of bunching.
    relax = shorts.modifiers.new("Relax", "CORRECTIVE_SMOOTH")
    relax.factor, relax.iterations, relax.smooth_type = 0.6, 8, "SIMPLE"
    board = build_board(mats)
    scene, cam = setup_scene()

    # The feet are held by IK targets parented to the board, so the stance follows the board.
    ankle_h = rig.pose.bones["foot.L"].head.z - 0.0
    targets, poles = {}, {}
    for s in "LR":
        targets["foot" + s] = empty(f"foot_{s}", board, (FOOT_X[s], 0.0, DECK_Z + ankle_h))
        poles["foot" + s] = empty(f"knee_{s}", board, (FOOT_X[s] - 0.10, 0.9, 0.55))
        targets["hand" + s] = empty(f"hand_{s}")
        poles["hand" + s] = empty(f"elbow_{s}")
        add_ik(rig, f"lowerleg02.{s}", targets["foot" + s], poles["foot" + s], 4, [f"upperleg01.{s}", f"lowerleg02.{s}"])
        add_ik(rig, f"lowerarm02.{s}", targets["hand" + s], poles["hand" + s], 4, [f"upperarm01.{s}", f"lowerarm02.{s}"])
    # Which bone axis of the foot points up when standing, so the sole can be laid on the deck.
    foot_rest = world(rig, "foot.L")
    up_axis = max(((i, s) for i in (0, 2) for s in (1, -1)), key=lambda a: a[1] * foot_rest.col[a[0]].z)

    meta = {"frames": [], "poses": [p["name"] for p in POSES]}
    white = bpy.data.materials.new("light_override")
    white.use_nodes = True
    white.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1)
    white.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    layer = bpy.context.view_layer
    first = True
    for n, pose in enumerate(POSES):
        reset_pose(rig)
        board.rotation_euler = (math.radians(pose["roll"]), math.radians(pose["pitch"]), 0)
        board.location = (0, 0, pose["lift"])
        update()
        hips = (world(rig, "upperleg01.L").translation + world(rig, "upperleg01.R").translation) / 2
        rotate_bone(rig, "root", rot("Z", pose["yaw"]), pivot=hips)
        M = world(rig, "root")
        set_world(rig, "root", Matrix.Translation((0, 0, -pose["down"] + pose["lift"])) @ M)
        update()
        parts = ["spine05", "spine04", "spine03", "spine02", "spine01"]
        for name in parts:
            R = rot("X", -pose["bend"] / 5) @ rot("Y", -pose["lean"] / 5) @ rot("Z", pose["twist"] / 5)
            rotate_bone(rig, name, R)
        for name, share in (("neck01", 0.2), ("neck02", 0.2), ("neck03", 0.2), ("head", 0.4)):
            rotate_bone(rig, name, rot("Z", pose["look"] * share - pose["twist"] * share))
        for s, key in (("L", "hl"), ("R", "hr")):
            shoulder = world(rig, f"upperarm01.{s}").translation
            targets["hand" + s].location = shoulder + Vector(pose[key])
            sign = -1 if s == "L" else 1
            poles["hand" + s].location = shoulder + Vector((sign * 0.25, -0.55, -0.15))
        update()
        if first:  # find the pole angle that bends each knee and elbow toward its pole target
            for s in "LR":
                for key, joint in (("foot", "lowerleg01"), ("hand", "lowerarm01")):
                    cons = rig.pose.bones[("lowerleg02." if key == "foot" else "lowerarm02.") + s].constraints[0]
                    best = min(range(-180, 181, 30), key=lambda a: (setattr(cons, "pole_angle", math.radians(a)), update(),
                                                                    (world(rig, f"{joint}.{s}").translation - poles[key + s].matrix_world.translation).length)[-1])
                    cons.pole_angle = math.radians(best)
                    print("foundry: pole angle", key, s, best)
            update()
            first = False
        # Lay each sole flat on the deck: bone Y toward the toes, the up axis along the board's normal.
        for s in "LR":
            name = f"foot.{s}"
            fwd = board.matrix_world.to_3x3() @ Matrix.Rotation(math.radians(24), 3, "Z") @ Vector((0, 1, -0.12))
            nrm = board.matrix_world.to_3x3() @ Vector((0, 0, 1))
            f = fwd.normalized()
            u = (nrm - f * nrm.dot(f)).normalized() * up_axis[1]
            third = f.cross(u) if up_axis[0] == 2 else u.cross(f)
            cols = [None, f, None]
            cols[up_axis[0]] = u
            cols[0 if up_axis[0] == 2 else 2] = third
            M = Matrix((cols[0], cols[1], cols[2])).transposed().to_4x4()
            M.translation = world(rig, name).translation
            set_world(rig, name, M)
        update()
        err = max((world(rig, f"lowerleg02.{s}") @ Vector((0, rig.pose.bones[f'lowerleg02.{s}'].length, 0)) - targets["foot" + s].matrix_world.translation).length for s in "LR")
        print(f"foundry: pose {pose['name']} foot error {err:.3f} m")
        # Raw passes.
        for g, group in enumerate(REGION_GROUPS):
            set_mask_pass(group)
            layer.material_override = None
            scene.render.filepath = f"{OUT}/f{n:02d}_m{g}.png"
            bpy.ops.render.render(write_still=True)
        layer.material_override = white
        scene.render.filepath = f"{OUT}/f{n:02d}_light.png"
        bpy.ops.render.render(write_still=True)
        layer.material_override = None
        c = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
        meta["frames"].append({"pivot": [c.x * FRAME_W, (1 - c.y) * FRAME_H]})
        print(f"foundry: frame {n + 1}/{len(POSES)}", flush=True)
    with open(f"{OUT}/meta.json", "w") as fh:
        json.dump(meta, fh)


main()
