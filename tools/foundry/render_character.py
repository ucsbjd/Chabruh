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
SIT_HIP = 0.12  # sitting astride the board, the hip joints are this far above the deck
PRONE_HIP = 0.13  # lying on the board to paddle, the hip joints are this far above the deck
SPINE_BEND_WEIGHTS = (0.35, 0.30, 0.20, 0.10, 0.05)  # spine05 (lowest) to spine01
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
SET_NAME = argv[4] if len(argv) > 4 else "surfer"
BLEND_PATH = os.path.abspath(argv[5]) if len(argv) > 5 and argv[5] else None  # save the rigged scene here for posing by hand, then stop
if os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), "poses", SET_NAME + ".json")):  # solved from reference footage
    POSES = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "poses", SET_NAME + ".json")))
GLB_PATH = os.path.abspath(argv[6]) if len(argv) > 6 and argv[6] else None  # export the real-time model instead of rendering
if GLB_PATH:  # level board (its roll and pitch come from the game's physics); the body keeps its lean, hinge and arms
    _bt = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "poses", "bottom_turn.json")))[2]
    _named = {p["name"]: p for p in POSES}
    # The game drives the arms, the legs' bend and the balance itself (Surfer3D); these give the spine, hips, head and
    # hands their shape. Step 12 adds the rest of the library (docs/balance.md, "Gold standard"; storyboardimages/
    # jbay_refs and move_refs): the vertical snap sits back over the tail with the chest open and the head turned down
    # the face it is about to drop; the barrel is compact with the knees together; the floater stands taller, weight
    # centred; the air pulls the knees up under him; the tumble curls up with the arms round the head; and in the lull
    # he sits astride the board facing the nose, legs in the water, looking out over his right shoulder at the swell.
    POSES = [dict(_named["trim"], name="trim", roll=0, pitch=0),
             dict(_named["trim"], name="crouch", roll=0, pitch=0, down=0.30, bend=30, hinge=16, knee_r_in=0.25, look=44),
             dict(_bt, name="bottom_turn", roll=0, pitch=0),
             dict(_named["top_turn"], name="top_turn", roll=0, pitch=0),
             dict(_named["top_turn"], name="snap", roll=0, pitch=0, lift=0, down=0.26, yaw=12, bend=6, lean=16, twist=30,
                  look=80, neck_back=10, fingers=0.2),
             dict(_named["barrel"], name="barrel", roll=0, pitch=0, down=0.36, bend=40, hinge=12, knee_r_in=0.6),
             dict(_named["trim"], name="floater", roll=0, pitch=0, down=0.18, bend=18, twist=-2, look=36),
             dict(_named["air"], name="air", roll=0, pitch=0, lift=0, down=0.36, bend=24, hinge=6, knee_r_in=0.35),
             dict(_named["trim"], name="tumble", roll=0, pitch=0, down=0.50, yaw=10, bend=70, hinge=34, lean=0, twist=0,
                  look=0, neck_back=-40, knee_r_in=0.7, hands_at="head", hl=(-0.10, 0.10, 0.06), hr=(0.10, 0.10, 0.06),
                  el=(-0.30, 0.45, -0.10), er=(0.30, 0.45, -0.10), fingers=1.4),
             dict(_named["trim"], name="sit", roll=0, pitch=0, sit=True, yaw=90, bend=4, hinge=-6, lean=0, twist=0,
                  look=-55, neck_back=0, hands_at="board", hl=(-0.28, -0.19, DECK_Z + 0.04), hr=(-0.28, 0.19, DECK_Z + 0.04),
                  el=(0.15, -0.45, 0.0), er=(0.15, 0.45, 0.0),
                  fl=(-0.40, -0.28, -0.32), fr=(-0.40, 0.28, -0.32), kl=(-1.0, -0.3, 0.4), kr=(-1.0, 0.3, 0.4))]
    # Paddling out: lying on the board facing the nose (prone: tipped forward that many degrees about the hips, which
    # sit hip_x along the board), chest arched up, head up looking ahead, legs together along the deck to the tail.
    # Two phases of the stroke, one arm reaching forward into the water while the other pushes back past the hip; the
    # game swings between them.
    _prone = dict(_named["trim"], roll=0, pitch=0, prone=-84, hip_x=0.30, yaw=90, down=0, lift=0, bend=-14, hinge=0,
                  lean=0, twist=0, look=0, neck_back=38, hands_at="board", fingers=0.4,
                  el=(0.0, -0.45, 0.35), er=(0.0, 0.45, 0.35),
                  fl=(1.27, -0.09, DECK_Z + 0.06), fr=(1.27, 0.09, DECK_Z + 0.06), kl=(0.75, -0.15, 1.0), kr=(0.75, 0.15, 1.0))
    POSES += [dict(_prone, name="paddle_a", hl=(-0.80, -0.42, -0.22), hr=(0.15, 0.40, -0.12)),
              dict(_prone, name="paddle_b", hl=(0.15, -0.40, -0.12), hr=(-0.80, 0.42, -0.22))]
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
    for f in bm.faces:
        c = f.calc_center_median()
        trim = c.z > top - 0.06
        trim |= abs(c.x) > xw * 0.9 and abs(f.normal.x) > 0.55
        # (the real-time model is decimated, which would break up a print made of faces: it draws PALM_BOX as a decal)
        if c.y < 0 and c.x > 0 and f.normal.y < -0.3 and not GLB_PATH:
            palm_box = palm_box_at(hip_z)
            u = int(((c.x - palm_box[0]) / palm_box[2] + 0.5) * pw)
            v = int(((c.z - palm_box[1]) / palm_box[3] + 0.5) * ph)
            if 0 <= u < pw and 0 <= v < ph and px[(v * pw + u) * 4] > 0.5:
                trim = True
        f.material_index = 1 if trim else 0
    bm.to_mesh(copy.data)
    bm.free()
    copy.name = "shorts"
    return copy


def palm_box_at(hip_z):
    """Where the palm print sits on the shorts: x centre (the left thigh, front), z centre, width, height. The real-time
    model's print is bigger and lower down the leg, as on the look sheet (a decal can be; faces were too coarse)."""
    return (0.115, hip_z - 0.10, 0.17, 0.17) if not GLB_PATH else (0.11, hip_z - 0.17, 0.2, 0.24)


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


# A relaxed hand: each finger joint bends by these degrees (knuckle, middle, tip), the thumb by THUMB_CURL. A pose's
# "fingers" scales them (an open reaching hand at the lip, a fist round the head in the tumble). FINGER_AXIS is the
# bones' own axis that bends them toward the palm.
FINGER_CURL = (22.0, 34.0, 22.0)
THUMB_CURL = (6.0, 12.0, 10.0)
FINGER_AXIS = Vector((1.0, 0.0, 0.0))


def curl_fingers(rig, amount):
    from mathutils import Quaternion
    for s in "LR":
        for f in range(1, 6):
            for k, deg in enumerate(THUMB_CURL if f == 1 else FINGER_CURL):
                pb = rig.pose.bones.get(f"finger{f}-{k + 1}.{s}")
                if pb is not None:
                    pb.rotation_mode = "QUATERNION"
                    pb.rotation_quaternion = Quaternion(FINGER_AXIS, math.radians(deg * amount))


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


# ---------------------------------------------------------------- real-time model export
BODY_RATIO = 0.2   # the body's share of faces kept for the real-time model...
FACE_RATIO = 0.45  # ...and the face's, so his profile (brow, nose, chin) holds up
def bake_pose(rig, name):
    """Stores the evaluated pose (IK included) as a one-frame action of plain bone transforms."""
    mats = {pb.name: pb.matrix.copy() for pb in rig.pose.bones}
    bases = {}
    for pb in rig.pose.bones:
        par = pb.parent
        bases[pb.name] = pb.bone.convert_local_to_pose(
            mats[pb.name], pb.bone.matrix_local,
            parent_matrix=mats[par.name] if par else Matrix(), parent_matrix_local=par.bone.matrix_local if par else Matrix(), invert=True)
    rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for pb in rig.pose.bones:
        loc, quat, _ = bases[pb.name].decompose()
        pb.rotation_mode = "QUATERNION"
        pb.location, pb.rotation_quaternion = loc, quat
        pb.keyframe_insert("location", frame=1, group=pb.name)
        pb.keyframe_insert("rotation_quaternion", frame=1, group=pb.name)
    rig.animation_data.action = None


def decimate(obj, rig, ratio, keep=None, keep_ratio=1.0):
    """Collapses the mesh to `ratio` of its faces, the vertex group `keep` (if any) only to `keep_ratio` of its own.
    (Each part is decimated as its own selection: a vertex group on the Decimate modifier makes its zero-weight vertices
    uncollapsible, so the rest of the mesh is eaten to make up the count.)"""
    for m in list(obj.modifiers):
        if m.type in ("ARMATURE", "CORRECTIVE_SMOOTH"):
            obj.modifiers.remove(m)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if keep:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="VERT")
        obj.vertex_groups.active_index = obj.vertex_groups[keep].index
        for part_ratio, rest in ((keep_ratio, False), (ratio, True)):
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.object.vertex_group_select()
            if rest:
                bpy.ops.mesh.select_all(action="INVERT")
            bpy.ops.mesh.decimate(ratio=part_ratio)
        bpy.ops.object.mode_set(mode="OBJECT")
    else:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
    arm = obj.modifiers.new("Armature", "ARMATURE")
    arm.object = rig


def capsule(bm, a, b, radius):
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-4:
        return
    rotm = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    # (no end caps: the spheres close the ends, and a flat cap inside them would hand its axis to the skin nearby)
    bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=radius, radius2=radius, depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rotm)
    for p in (a, b):
        bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=radius, matrix=Matrix.Translation(p))


def group_mask(obj, name, match):
    """A vertex group holding, for each vertex, its total weight in the bone groups whose names `match`."""
    ids = {g.index for g in obj.vertex_groups if match(g.name)}
    group = obj.vertex_groups.new(name=name)
    for v in obj.data.vertices:
        w = min(sum(g.weight for g in v.groups if g.group in ids), 1.0)
        if w > 0.0:
            group.add([v.index], w, "REPLACE")
    return name


FACE_BONES = ("head", "jaw", "eye", "levator", "oris", "orbicularis", "oculi", "risorius", "temporalis", "special", "tongue")


def is_face(name):
    return name.startswith(FACE_BONES)


def is_hand_or_foot(name):
    return name.startswith(("wrist", "finger", "metacarpal", "foot", "toe"))


def keep_normals_outward(obj, least=0.25):
    """No corner normal may point into the surface (a front face lit as if it faced away: the funky patches on his
    back): any that leans more than `least` against its face's own normal is pulled out to it."""
    mesh = obj.data
    normals = [Vector(c.vector) for c in mesh.corner_normals]
    fixed = 0
    for poly in mesh.polygons:
        fn = Vector(poly.normal)
        for li in poly.loop_indices:
            d = normals[li].dot(fn)
            if d < least:
                normals[li] = (normals[li] + fn * (least - d + 0.05)).normalized()
                fixed += 1
    mesh.normals_split_custom_set(normals)
    print("foundry: corner normals pulled outward", fixed, "of", len(normals))


def smooth_normals_from_proxy(obj, rig):
    """Big flat light bands need smooth, simple normals: copy them from a capsule stand-in for the body. The face,
    hands and feet keep their own (the stand-in has no nose, fingers or toes)."""
    own = group_mask(obj, "own_normals", lambda n: is_face(n) or is_hand_or_foot(n))
    bn = rig.data.bones
    bm = bmesh.new()
    seg = [("spine05", "spine01", 0.16), ("neck01", "head", 0.06)]
    for s in "LR":
        seg += [(f"upperleg02.{s}", f"lowerleg01.{s}", 0.095), (f"lowerleg01.{s}", f"foot.{s}", 0.062),
                (f"upperarm02.{s}", f"lowerarm01.{s}", 0.052), (f"lowerarm01.{s}", f"wrist.{s}", 0.044)]
    for a, b, rad in seg:
        capsule(bm, bn[a].head_local, bn[b].head_local, rad)
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.12, matrix=Matrix.Translation(bn["head"].head_local + Vector((0, 0, 0.06))))
    proxy = bpy.data.objects.new("proxy", bpy.data.meshes.new("proxy"))
    bm.to_mesh(proxy.data)
    bm.free()
    bpy.context.collection.objects.link(proxy)
    proxy.parent = rig
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for m in list(obj.modifiers):
        if m.type == "ARMATURE":
            obj.modifiers.remove(m)
    mod = obj.modifiers.new("Normals", "DATA_TRANSFER")
    mod.object = proxy
    mod.use_loop_data = True
    mod.data_types_loops = {"CUSTOM_NORMAL"}
    mod.loop_mapping = "POLYINTERP_NEAREST"
    mod.vertex_group, mod.invert_vertex_group = own, True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    keep_normals_outward(obj)
    arm = obj.modifiers.new("Armature", "ARMATURE")
    arm.object = rig
    bpy.data.objects.remove(proxy, do_unlink=True)


def set_regions(obj, region_of_face, decal_of_corner=None):
    """Red: the region number / 10. Green and blue: where the corner falls in a decal (DECAL_SPAN of the colour range
    is the decal's square, so the print can run off a face's edge), or 0 for none."""
    attr = obj.data.color_attributes.new("Region", "FLOAT_COLOR", "CORNER")
    obj.data.color_attributes.active_color = attr
    for poly in obj.data.polygons:
        rid = region_of_face(poly)
        for li in poly.loop_indices:
            uv = decal_of_corner(poly, obj.data.loops[li].vertex_index) if decal_of_corner else None
            g, b = (0.0, 0.0) if uv is None else (0.5 + (uv[0] - 0.5) * DECAL_SPAN, 0.5 + (uv[1] - 0.5) * DECAL_SPAN)
            attr.data[li].color = (rid / 10.0, g, b, 1.0)


DECAL_SPAN = 0.5  # must match DECAL_SPAN in game/shaders/surfer3d.gdshader


def palm_decal(shorts, hip_z):
    """The palm print on the front of the left thigh, projected straight on from the front (the body's own space)."""
    cx, cz, w, h = palm_box_at(hip_z)
    verts = shorts.data.vertices

    def corner(poly, vi):
        c = poly.center
        if not (c.y < 0 and c.x > 0 and poly.normal.y < -0.3):
            return None
        co = verts[vi].co
        return ((co.x - cx) / w + 0.5, (co.z - cz) / h + 0.5)
    return corner


def add_pocket(shorts, hip_z):
    """The back pocket's flap (stripe A) and its button (ink) on his right buttock (-X in the body's own space, the back
    is +Y), laid on the shorts and skinned like the shorts under them."""
    from mathutils.bvhtree import BVHTree
    from mathutils.kdtree import KDTree
    # (the rest shape, in the shorts' own space: the rig is still in the last pose baked)
    tree = BVHTree.FromPolygons([v.co for v in shorts.data.vertices], [list(p.vertices) for p in shorts.data.polygons])
    kd = KDTree(len(shorts.data.vertices))
    for v in shorts.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()

    def on_shorts(x, z, out):
        hit = tree.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)))
        if hit[0] is None:
            return None
        return hit[0] + hit[1] * out
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    region = bm.faces.layers.int.new("region")
    x0, x1, z0, z1 = POCKET_BOX
    nx, nz = 5, 3

    def skin(v):
        _, index, _ = kd.find(v.co)
        for g in shorts.data.vertices[index].groups:
            v[dl][g.group] = g.weight
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            p = on_shorts(x0 + (x1 - x0) * i / nx, hip_z + z0 + (z1 - z0) * j / nz, 0.005)
            if p is None:
                return
            row.append(bm.verts.new(p))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]))  # facing +Y, out of his back
            f.normal_update()
            if f.normal.y < 0:
                f.normal_flip()
            f[region] = 6
    centre = on_shorts((x0 + x1) / 2, hip_z + z0 + (z1 - z0) * 0.3, 0.008)
    if centre is not None:
        ring = [bm.verts.new(centre + Vector((math.cos(a) * POCKET_BUTTON, 0.0, math.sin(a) * POCKET_BUTTON)))
                for a in (k * math.tau / 6 for k in range(6))]
        f = bm.faces.new(ring)
        f[region] = 4
        f.normal_update()
        if f.normal.y < 0:
            f.normal_flip()
    for v in bm.verts:
        skin(v)
    bm.normal_update()
    regions = [f[region] for f in bm.faces]
    # (append to the shorts mesh: the vertex groups line up because they are the shorts' own indices)
    pocket = bpy.data.meshes.new("pocket")
    bm.to_mesh(pocket)
    bm.free()
    tmp = bpy.data.objects.new("pocket", pocket)
    bpy.context.collection.objects.link(tmp)
    for g in shorts.vertex_groups:
        tmp.vertex_groups.new(name=g.name)
    # bmesh deform layers index groups by number, which the new object shares in the same order
    tmp.data.materials.append(shorts.data.materials[0])
    for k, poly in enumerate(tmp.data.polygons):
        poly.material_index = 0
        poly.use_smooth = False
    return tmp, regions


POCKET_BOX = (-0.155, -0.045, -0.035, 0.015)  # x from, x to, z from, z to (from the hip joints' height)
POCKET_BUTTON = 0.007


def export_glb(rig, base, shorts, hair, board):
    """One skinned mesh (body, shorts, hair), one board, the baked poses as actions: game/assets/models/surfer.glb."""
    # The actions already hold the IK's result. Mute the constraints, or the exporter's sampling solves the IK again
    # toward wherever the last pose left the targets, bending every pose's legs and arms toward that one.
    for pb in rig.pose.bones:
        for c in pb.constraints:
            c.mute = True
    hip_z = rig.data.bones["upperleg01.L"].head_local.z
    # The face keeps more of its detail than the rest (FACE_RATIO), so his profile (brow, nose, chin) holds up.
    face = group_mask(base, "face_keep", is_face)
    decimate(base, rig, BODY_RATIO, keep=face, keep_ratio=FACE_RATIO)
    decimate(shorts, rig, 0.3)
    try:
        smooth_normals_from_proxy(base, rig)
    except Exception as e:  # the look still works with the body's own normals
        print("foundry: proxy normals skipped:", e)
    toon = bpy.data.materials.new("toon")
    set_regions(base, lambda p: 0)
    set_regions(shorts, lambda p: (1, 5)[min(p.material_index, 1)], palm_decal(shorts, hip_z))
    pocket = add_pocket(shorts, hip_z)
    extra = []
    if pocket:
        obj, regions = pocket
        set_regions(obj, lambda p: regions[p.index])
        add_armature_skin(obj, rig)
        extra.append(obj)
    for o in hair:
        set_regions(o, lambda p: 3)
    set_regions(board, lambda p: (6, 1, 7, 5, 2)[min(p.material_index, 4)])
    for o in (base, shorts, board, *hair, *extra):
        o.data.materials.clear()
        o.data.materials.append(toon)
    bpy.ops.object.select_all(action="DESELECT")
    for o in (shorts, *hair, *extra):
        o.select_set(True)
    base.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    base.name = "SurferBody"
    board.name = "Board"
    bpy.ops.object.select_all(action="DESELECT")
    for o in (rig, base, board):
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_vertex_color="ACTIVE", export_skins=True,
                              export_yup=True, export_apply=False, export_cameras=False, export_lights=False)
    print("foundry: exported", GLB_PATH, round(os.path.getsize(GLB_PATH) / 1e6, 2), "MB, triangles", sum(len(p.vertices) - 2 for p in base.data.polygons))


def main():
    base, rig = build_human()
    bpy.context.view_layer.objects.active = rig
    rig.rotation_euler.z = math.pi  # MPFB faces -Y; the surfer must face +Y, away from the camera
    update()
    mats = {
        "skin": region_material("skin", 0),
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
    rest_feet = {key: (targets[key].location.copy(), poles[key].location.copy()) for key in ("footL", "footR")}
    for n, pose in enumerate(POSES):
        reset_pose(rig)
        for key, (loc, pole) in rest_feet.items():
            targets[key].location, poles[key].location = loc, pole
        if pose.get("sit") or "prone" in pose:  # astride the board or lying on it: the feet go where the pose says
            if pose.get("sit"):  # (astride, the hips come down onto the deck)
                hips0 = (world(rig, "upperleg01.L").translation + world(rig, "upperleg01.R").translation) / 2
                pose = dict(pose, down=hips0.z - (DECK_Z + SIT_HIP))
            for s in "LR":
                targets["foot" + s].location = Vector(pose["f" + s.lower()])
                poles["foot" + s].location = Vector(pose["k" + s.lower()])
        raw = pose.get("raw")  # a pose saved from Blender by save_pose.py: apply it as it is
        if raw:
            board.location, board.rotation_euler = raw["board"]["location"], raw["board"]["rotation"]
            for ename, loc in raw["empties"].items():
                bpy.data.objects[ename].location = loc
            for bname, v in raw["bones"].items():
                pb = rig.pose.bones[bname]
                pb.rotation_mode = "QUATERNION"
                pb.location, pb.rotation_quaternion = v[:3], v[3:7]
            update()
        board.rotation_euler = board.rotation_euler if raw else (math.radians(pose["roll"]), math.radians(pose["pitch"]), 0)
        board.location = board.location if raw else (0, 0, pose["lift"])
        update()
        hips = (world(rig, "upperleg01.L").translation + world(rig, "upperleg01.R").translation) / 2
        if not raw:
            rotate_bone(rig, "root", rot("Z", pose["yaw"]), pivot=hips)
            M = world(rig, "root")
            set_world(rig, "root", Matrix.Translation((0, 0, -pose["down"] + pose["lift"])) @ M)
            update()
            # Hinge over at the hips (the pelvis tips toward the wave, the feet stay pinned), as a deep bottom turn does.
            hips = (world(rig, "upperleg01.L").translation + world(rig, "upperleg01.R").translation) / 2
            rotate_bone(rig, "root", rot("X", -pose.get("hinge", 0.0)), pivot=hips)
            if "prone" in pose:  # tip him forward onto his chest, then lay his hips on the deck
                rotate_bone(rig, "root", rot("Y", pose["prone"]), pivot=hips)
                hips = (world(rig, "upperleg01.L").translation + world(rig, "upperleg01.R").translation) / 2
                set_world(rig, "root", Matrix.Translation(Vector((pose["hip_x"], 0.0, DECK_Z + PRONE_HIP)) - hips) @ world(rig, "root"))
                update()
        parts = ["spine05", "spine04", "spine03", "spine02", "spine01"]
        # Forward flexion is weighted toward the lower back, so the upper back (and the tattoo) stays turned to the camera.
        if not raw:
            for name, wb in zip(parts, SPINE_BEND_WEIGHTS):
                R = rot("X", -pose["bend"] * wb) @ rot("Y", -pose["lean"] / 5) @ rot("Z", pose["twist"] / 5)
                rotate_bone(rig, name, R)
            # The back knee tucks in toward the front leg by knee_r_in (0 to 1).
            if not pose.get("sit") and "prone" not in pose:
                poles["footR"].location.x = FOOT_X["R"] - 0.10 - 1.5 * pose.get("knee_r_in", 0.0)
            for name, share in (("neck01", 0.2), ("neck02", 0.2), ("neck03", 0.2), ("head", 0.4)):
                rotate_bone(rig, name, rot("X", pose.get("neck_back", 0.0) * share) @ rot("Z", pose["look"] * share - pose["twist"] * share))
            for s, key in (("L", "hl"), ("R", "hr")):
                shoulder = world(rig, f"upperarm01.{s}").translation
                at = {"head": world(rig, "head").translation, "board": Vector((0, 0, 0))}.get(pose.get("hands_at"), shoulder)
                targets["hand" + s].location = at + Vector(pose[key])
                sign = -1 if s == "L" else 1
                poles["hand" + s].location = shoulder + Vector(pose.get("e" + key[1], (sign * 0.25, -0.55, -0.15)))
            curl_fingers(rig, pose.get("fingers", 1.0))
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
            if BLEND_PATH:
                bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
                print("foundry: saved", BLEND_PATH)
                return
        # Lay each sole flat on the deck: bone Y toward the toes, the up axis along the board's normal.
        for s in ("LR" if not (raw and "foot.L" in raw["bones"]) and not pose.get("sit") and "prone" not in pose else ""):
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
        if GLB_PATH:
            bake_pose(rig, pose["name"])
            continue
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
    if GLB_PATH:
        export_glb(rig, base, shorts, hair, board)
        return
    with open(f"{OUT}/meta.json", "w") as fh:
        json.dump(meta, fh)


main()
