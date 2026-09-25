#!/usr/bin/env python3
"""Validate all exported original models without a GPU or Android emulator."""
import hashlib
import json
import math
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "android/app/src/main/assets/scene"
manifest = json.loads((ASSETS / "scene.json").read_text())
assert manifest["version"] == 1
assert manifest["sourceSHA256"] == hashlib.sha256((ROOT / "PiyakBank/Views/PiyakScene.swift").read_bytes()).hexdigest(), "Regenerate scene assets after changing original models"
ids = re.findall(r'\.init\(id: "([A-Za-z]+\.[a-z_]+)"', (ROOT / "PiyakBank/Shared/Economy.swift").read_text())
assert len(ids) == len(set(ids)) == 81
assert set(manifest["items"]) == set(manifest["previews"]) == set(ids)
assert len(manifest["rooms"]) == 9
raw = memoryview((ASSETS / "meshes.bin").read_bytes())
cursor = 0
triangles = 0
assert len(manifest["meshBounds"]) == manifest["meshCount"]
mesh_bounds = []
mesh_vertices = []
for index in range(manifest["meshCount"]):
    count, size = struct.unpack_from("<II", raw, cursor)
    cursor += 8
    assert 0 < count < 65536 and size >= 3 and size % 3 == 0
    floats = struct.unpack_from(f"<{count * 6}f", raw, cursor)
    mesh_vertices.append(floats)
    assert all(map(math.isfinite, floats)), f"Nonfinite mesh {index}"
    low = [min(floats[axis::6]) for axis in range(3)]
    high = [max(floats[axis::6]) for axis in range(3)]
    mesh_bounds.append((low, high))
    source = manifest["meshBounds"][index]
    for axis in range(3):
        tolerance = max(.00001, (source["sourceMax"][axis] - source["sourceMin"][axis]) * .0002)
        assert abs(low[axis] - source["sourceMin"][axis]) <= tolerance, f"{source['kind']} {index} lost original minimum dimension"
        assert abs(high[axis] - source["sourceMax"][axis]) <= tolerance, f"{source['kind']} {index} lost original maximum dimension"
    cursor += count * 24
    indices = struct.unpack_from(f"<{size}H", raw, cursor)
    assert max(indices) < count
    cursor += size * 2
    triangles += size // 3
assert cursor == len(raw) and triangles == manifest["triangleCount"]
# A small independent known-dimension sentinel would have caught the former
# Model I/O unit-primitive regression even if the export's checks were removed.
floor = manifest["rooms"]["bg.cozy_cream"][0]
floor_bounds = mesh_bounds[floor["mesh"]]
for axis, extent in enumerate([4.8, .3, 3.9]):
    assert abs(floor_bounds[1][axis] - floor_bounds[0][axis] - extent) < .0001, "Room floor dimensions changed"
body = next(item for item in manifest["base"] if item["rig"] == "bodyRig")
body_bounds = mesh_bounds[body["mesh"]]
assert abs(body_bounds[1][0] - body_bounds[0][0] - 2) < .0001, "Original radius-one chick sphere became a unit-diameter sphere"
# The right cactus arm used to join +Z-oriented and -Z-oriented cross-section
# rings, twisting through its own centre despite perfectly valid bounds/indices.
# Check actual exported ring correspondence: the intended 90-degree branch bend
# is spread over its three rings, so corresponding normals remain aligned.
cactus_arms = {item["mesh"] for item in manifest["items"]["floorProp.cactus"]["add"]
               if manifest["meshBounds"][item["mesh"]]["kind"] == "SCNGeometry"}
assert len(cactus_arms) == 2, "Expected both original swept cactus branches"
for mesh in cactus_arms:
    vertices = mesh_vertices[mesh]
    assert len(vertices) == 3 * 8 * 6, "Cactus branch cross-section topology changed; review regression coverage"
    for ring in range(2):
        for side in range(8):
            first = (ring * 8 + side) * 6 + 3
            second = ((ring + 1) * 8 + side) * 6 + 3
            alignment = sum(vertices[first + axis] * vertices[second + axis] for axis in range(3))
            assert alignment > .5, f"Cactus branch {mesh} twists between rings {ring} and {ring + 1}: normal alignment {alignment}"
rigs = {rig["name"] for rig in manifest["rigs"]}
assert {"piyak", "bodyRig", "headRig", "eyes", "wing.left", "wing.right", "foot.left", "foot.right"} == rigs

def inspect(instances):
    assert instances
    for instance in instances:
        assert 0 <= instance["mesh"] < manifest["meshCount"]
        assert instance["rig"] in rigs | {""}
        assert len(instance["matrix"]) == 16 and all(map(math.isfinite, instance["matrix"]))
        assert len(instance["color"]) == 4 and all(0 <= v <= 1 for v in instance["color"])

inspect(manifest["base"])
base = {item["key"] for item in manifest["base"]}
for name, delta in manifest["items"].items():
    assert set(delta["remove"]) <= base
    if not name.startswith("bg."):
        inspect(delta["add"])
for instances in manifest["rooms"].values():
    inspect(instances)
for preview in manifest["previews"].values():
    inspect(preview["instances"])
    assert len(preview["camera"]) == len(preview["target"]) == 3 and preview["scale"] > 0
for instances in manifest["effects"].values():
    inspect(instances)
assert {"book", "wateringCan", *(f"drop.{i}" for i in range(6))} == set(manifest["effects"])
print(f"PASS: 81 models, 9 rooms, {manifest['meshCount']} deduplicated meshes, {triangles:,} triangles; original dimensions, floor/body sentinels, cactus frame continuity, binary indices, finite transforms, rig composition, source fingerprint and effects verified.")
