#!/usr/bin/env python3
"""Render the app-icon chick (mint hoodie bust) with Blender Cycles.

pip install bpy==4.5.14        # Blender as a Python module (Python 3.11)
python3 scripts/app_icon/render_chick.py /tmp/piyak-icon-master.png
python3 scripts/app_icon/make_icons.py /tmp/piyak-icon-master.png

The geometry is the project's own model: the meshes exported from PiyakScene.swift
for Android (android/app/src/main/assets/scene). Nothing is downloaded. The output is a
2400x2400 RGBA PNG on a transparent background; make_icons.py adds the background.
Pass --preview for a quick 640 px, 16-sample check.
"""
import json
import math
import struct
import sys
from pathlib import Path

import bpy  # must come first: bmesh and mathutils are provided by the bpy module
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SCENE_DIR = ROOT / 'android/app/src/main/assets/scene'
SCENE = json.loads((SCENE_DIR / 'scene.json').read_text())
RIGS = {r['name']: r for r in SCENE['rigs']}
ITEMS = ['bodyFront.hoodie_mint']
TURN_DEG = 8                    # chick yaw; the camera sits 16 degrees to its right
CAMERA = dict(target=(0.0, 1.64, 0.0), azimuth_deg=16, elevation_deg=9, lens=42.7, distance=3.083)
# SceneKit (Y up, chick faces +Z) -> Blender (Z up, front -Y)
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
LIGHTS = [  # soft key upper-left, lavender fill, two rims to separate the silhouette
    dict(name='key', pos=(-3.0, 5.5, 5.5), energy=560, size=5.5, hex=0xFFF5DC),
    dict(name='fill', pos=(5.2, 1.8, 4.5), energy=185, size=5.5, hex=0xE4E0FF),
    dict(name='rim', pos=(2.8, 3.8, -4.8), energy=1000, size=2.2, hex=0xFFFFFF),
    dict(name='rim2', pos=(-3.2, 2.8, -4.2), energy=600, size=2.2, hex=0xEDE6FF),
    dict(name='under', pos=(0.0, -2.2, 4.3), energy=95, size=4.0, hex=0xFFEAD0),
]


def load_meshes():
    buf = (SCENE_DIR / 'meshes.bin').read_bytes()
    off, out = 0, []
    while off < len(buf):
        vc, ic = struct.unpack_from('<II', buf, off); off += 8
        v = np.frombuffer(buf, dtype='<f4', count=vc * 6, offset=off).reshape(vc, 6); off += vc * 24
        idx = np.frombuffer(buf, dtype='<u2', count=ic, offset=off); off += ic * 2
        out.append((v.copy(), idx.copy()))
    return out


MESHES = load_meshes()


def mat(m):
    return Matrix(np.array(m, dtype=float).reshape(4, 4).T.tolist())  # column-major storage


def linear(rgb):
    c = np.asarray(rgb[:3], dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hexrgb(h):
    return [((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255]


def scn(p):
    x, y, z = p
    return Vector((x, -z, y))


_meshes = {}


def mesh_data(index):
    if index in _meshes:
        return _meshes[index]
    me = bpy.data.meshes.new(f'm{index}')
    if SCENE['meshBounds'][index]['kind'] == 'SCNSphere':
        # Same primitive as SceneKit, finer tessellation for a close-up.
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=5, radius=SCENE['meshBounds'][index]['sourceMax'][0])
        bm.to_mesh(me); bm.free()
        for poly in me.polygons:
            poly.use_smooth = True
    else:
        v, idx = MESHES[index]
        p, n = v[:, :3], v[:, 3:6]
        tris = idx.reshape(-1, 3).astype(np.int64)
        # A few exported patches wind against their normals (SceneKit draws both sides).
        fn = np.cross(p[tris[:, 1]] - p[tris[:, 0]], p[tris[:, 2]] - p[tris[:, 0]])
        flip = np.einsum('ij,ij->i', fn, n[tris].mean(1)) < 0
        tris[flip] = tris[flip][:, ::-1]
        me.from_pydata(p.tolist(), [], tris.tolist())
        me.update()
        for poly in me.polygons:
            poly.use_smooth = True
        me.normals_split_custom_set_from_vertices((n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)).tolist())
    me.materials.append(None)
    _meshes[index] = me
    return me


_materials = {}


def material(color):
    """Material response picked from the part colour (the export only carries colours)."""
    key = tuple(np.round(color[:3], 4))
    if key in _materials:
        return _materials[key]
    r, g, b = color[:3]
    m = bpy.data.materials.new(f'mat{len(_materials)}')
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*linear(color), 1)
    bsdf.inputs['Roughness'].default_value = 0.6
    bsdf.inputs['Specular IOR Level'].default_value = 0.5
    if max(r, g, b) < 0.4:                                  # eyes
        bsdf.inputs['Roughness'].default_value = 0.18
        bsdf.inputs['Specular IOR Level'].default_value = 0.7
        bsdf.inputs['Coat Weight'].default_value = 0.4
        bsdf.inputs['Coat Roughness'].default_value = 0.25
    elif min(r, g, b) > 0.97:                               # eye highlights
        bsdf.inputs['Roughness'].default_value = 0.3
        bsdf.inputs['Emission Color'].default_value = (*linear(color), 1)
        bsdf.inputs['Emission Strength'].default_value = 0.6
    elif r > 0.95 and 0.8 < g < 0.87 and b < 0.35:          # chick yellow (0xFFD64F)
        bsdf.inputs['Roughness'].default_value = 0.5
        bsdf.inputs['Subsurface Weight'].default_value = 0.12
        bsdf.inputs['Subsurface Radius'].default_value = (1.0, 0.55, 0.25)
        bsdf.inputs['Subsurface Scale'].default_value = 0.06
    _materials[key] = m
    return m


def rig_world(name, root):
    if name in ('', 'piyak'):
        return root
    rig = RIGS[name]
    return rig_world(rig['parent'], root) @ mat(rig['matrix'])


def look_at(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()


def build(res, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '16'
    sc.view_settings.view_transform = 'Standard'   # keep brand colours (no filmic desaturation)
    world = bpy.data.worlds.new('world'); sc.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (*linear(hexrgb(0xE6DDFF)), 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.40

    t = CAMERA['target']
    az, el, d = math.radians(CAMERA['azimuth_deg']), math.radians(CAMERA['elevation_deg']), CAMERA['distance']
    cam_data = bpy.data.cameras.new('camera'); cam_data.lens = CAMERA['lens']
    cam = bpy.data.objects.new('camera', cam_data); sc.collection.objects.link(cam)
    cam.location = scn((t[0] + d * math.sin(az) * math.cos(el), t[1] + d * math.sin(el), t[2] + d * math.cos(az) * math.cos(el)))
    look_at(cam, scn(t)); sc.camera = cam

    for spec in LIGHTS:
        light = bpy.data.lights.new(spec['name'], 'AREA')
        light.shape = 'DISK'; light.size = spec['size']; light.energy = spec['energy']
        light.color = linear(hexrgb(spec['hex'])).tolist()
        obj = bpy.data.objects.new(spec['name'], light); sc.collection.objects.link(obj)
        obj.location = scn(spec['pos']); look_at(obj, scn(t))

    root = Matrix.Rotation(math.radians(TURN_DEG), 4, 'Y')
    parts = list(SCENE['base'])
    removed = set()
    for item in ITEMS:
        parts += SCENE['items'][item]['add']
        removed |= set(SCENE['items'][item].get('remove', []))
    for i, part in enumerate(parts):
        if part['key'] in removed:
            continue
        obj = bpy.data.objects.new(f"{part['label']}_{i}", mesh_data(part['mesh']))
        sc.collection.objects.link(obj)
        obj.matrix_world = C @ rig_world(part['rig'], root) @ mat(part['matrix'])
        obj.material_slots[0].link = 'OBJECT'
        obj.material_slots[0].material = material(part['color'])
    return sc


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    preview = '--preview' in sys.argv
    out = args[0] if args else '/tmp/piyak-icon-master.png'
    sc = build(640 if preview else 2400, 16 if preview else 64)
    sc.render.filepath = str(Path(out).resolve())
    bpy.ops.render.render(write_still=True)
    print('Rendered', out)


if __name__ == '__main__':
    main()
