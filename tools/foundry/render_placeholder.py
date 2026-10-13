"""Headless Blender: builds a placeholder surfer and board, poses a short trim cycle and renders two raw passes
per frame at 2x the final size (the packer downsamples them, which gives clean anti-aliased region weights).

  mask: flat emission colours, skin = red, shorts = green, board = blue, hair = white (alpha is coverage)
  light: a white diffuse override lit only by the key sun, so the value is the light on the form

Run:  blender -b --python tools/foundry/render_placeholder.py -- <out_dir> [frames]
Units are meters. The board's underside centre is the origin, which is the sprite anchor. The surfer rides toward
the image's left (-X), faces +Y (away from the camera) and is seen from behind and slightly from the side.
"""
import math
import sys

import bpy
from mathutils import Vector

# Must match game/scripts/surfer_sprites.gd (FRAME_SIZE, ANCHOR, FRAME_METERS).
FRAME_W, FRAME_H = 468, 360
ANCHOR_X, ANCHOR_Y = 203.2, 355.3
FRAME_METERS = 1.85
SS = 2  # render supersampling; the packer divides by this

CAMERA_YAW = math.radians(18.0)  # camera swings a little toward the board's tail side
# Direction from the surfer toward the key sun: from the left (ahead), a bit behind the camera, fairly high.
SUN_DIRECTION = Vector((-0.55, -0.45, 0.70)).normalized()

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "work/placeholder"
FRAMES = int(argv[1]) if len(argv) > 1 else 8


def emission(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1.0)
    em.inputs["Strength"].default_value = 1.0
    mat.node_tree.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


MATS = {
    "skin": emission("skin", (1, 0, 0)),
    "shorts": emission("shorts", (0, 1, 0)),
    "board": emission("board", (0, 0, 1)),
    "hair": emission("hair", (1, 1, 1)),
}


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def ellipsoid(center, scale, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=14, location=center)
    obj = bpy.context.object
    obj.scale = scale
    obj.data.materials.append(MATS[mat])
    bpy.ops.object.shade_smooth()
    return obj


def limb(a, b, radius, mat, taper=0.82):
    """A tapered capsule-ish cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=radius, radius2=radius * taper, depth=length,
                                    location=(a + b) / 2)
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    obj.data.materials.append(MATS[mat])
    bpy.ops.object.shade_smooth()
    # Round the ends so joints do not show gaps.
    for end in (a, b):
        ellipsoid(end, (radius * taper,) * 3, mat)
    return obj


def build_board():
    # Underside at z = 0 at the centre, so the lowest pixel sits on the anchor row.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=(0, 0, 0.035))
    obj = bpy.context.object
    obj.scale = (0.95, 0.20, 0.035)
    obj.data.materials.append(MATS["board"])
    bpy.ops.object.shade_smooth()


def build_surfer(t):
    """t in 0..1 around the cycle: a gentle pump, knees bending and straightening."""
    pump = 0.5 - 0.5 * math.cos(2 * math.pi * t)  # 0 up, 1 crouched
    bob = 0.07 * pump
    sway = 0.04 * math.sin(2 * math.pi * t)

    front_foot = (-0.42, 0.02, 0.07)  # left foot forward, toward -X
    rear_foot = (0.38, 0.02, 0.07)
    hip = Vector((-0.02 + sway * 0.5, 0.02, 0.80 - bob * 1.6))
    front_knee = Vector((-0.50, -0.16 - 0.04 * pump, 0.44 - bob * 0.8))
    rear_knee = Vector((0.40, -0.14 - 0.04 * pump, 0.43 - bob * 0.8))
    shoulder_c = hip + Vector((-0.04 + sway, 0.06, 0.55 - bob * 0.4))
    sl, sr = shoulder_c + Vector((-0.20, 0, 0)), shoulder_c + Vector((0.20, 0, 0))
    # Arms wide for balance, the rear one a little higher on the pump.
    hand_l = sl + Vector((-0.36, 0.12, -0.22 + 0.10 * pump))
    hand_r = sr + Vector((0.40, 0.08, -0.12 - 0.08 * pump))
    elbow_l = (sl + hand_l) / 2 + Vector((0, -0.07, -0.05))
    elbow_r = (sr + hand_r) / 2 + Vector((0, -0.07, -0.05))
    head = shoulder_c + Vector((-0.02, 0.03, 0.22))

    # Legs: shorts over the top of each thigh, skin below.
    for foot, knee in ((front_foot, front_knee), (rear_foot, rear_knee)):
        hip_side = hip + Vector((-0.10 if foot is front_foot else 0.10, 0, 0))
        mid = hip_side.lerp(knee, 0.62)
        limb(hip_side, mid, 0.105, "shorts", taper=0.95)
        limb(mid, knee, 0.082, "skin")
        limb(knee, foot, 0.068, "skin", taper=0.7)
    ellipsoid(hip, (0.20, 0.12, 0.14), "shorts")
    # Torso, shoulders, neck, arms, head, hair at the back of the head (toward the camera, -Y).
    ellipsoid(hip.lerp(shoulder_c, 0.52) + Vector((0, 0, 0.0)), (0.19, 0.11, 0.30), "skin")
    ellipsoid(shoulder_c, (0.24, 0.10, 0.09), "skin")
    limb(shoulder_c, head, 0.05, "skin")
    limb(sl, elbow_l, 0.052, "skin", taper=0.85)
    limb(elbow_l, hand_l, 0.045, "skin", taper=0.7)
    limb(sr, elbow_r, 0.052, "skin", taper=0.85)
    limb(elbow_r, hand_r, 0.045, "skin", taper=0.7)
    ellipsoid(head + Vector((0, 0.02, 0)), (0.095, 0.105, 0.115), "skin")
    ellipsoid(head + Vector((0.0, -0.025, 0.02)), (0.108, 0.098, 0.118), "hair")


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0  # direct light only: the ramp must be a clean function of the form
    scene.cycles.filter_width = 0.8
    scene.render.film_transparent = True
    scene.render.resolution_x = FRAME_W * SS
    scene.render.resolution_y = FRAME_H * SS
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.display_settings.display_device = "sRGB"
    world = bpy.data.worlds.new("black") if not scene.world else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = FRAME_W / (FRAME_H / FRAME_METERS)  # meters across the frame width
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.shift_x = (FRAME_W / 2 - ANCHOR_X) / FRAME_W
    cam_data.shift_y = (ANCHOR_Y - FRAME_H / 2) / FRAME_W
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    direction = Vector((math.sin(CAMERA_YAW), -math.cos(CAMERA_YAW), 0.0))
    cam.location = direction * 12.0 + Vector((0, 0, 0))
    cam.rotation_euler = (math.pi / 2, 0, CAMERA_YAW)
    scene.camera = cam

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.0
    sun_data.angle = 0.0
    sun = bpy.data.objects.new("sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = Vector((0, 0, -1)).rotation_difference(-SUN_DIRECTION).to_euler()
    return scene


def keep_figure_only():
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)


def main():
    clear_scene()
    scene = setup_scene()
    white = bpy.data.materials.new("light_override")
    white.use_nodes = True
    white.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1)
    white.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    layer = bpy.context.view_layer
    for i in range(FRAMES):
        keep_figure_only()
        build_board()
        build_surfer(i / FRAMES)
        layer.material_override = None
        scene.render.filepath = f"{OUT}/f{i:02d}_mask.png"
        bpy.ops.render.render(write_still=True)
        layer.material_override = white
        scene.render.filepath = f"{OUT}/f{i:02d}_light.png"
        bpy.ops.render.render(write_still=True)
        print(f"foundry: frame {i + 1}/{FRAMES}", flush=True)
    layer.material_override = None


main()
