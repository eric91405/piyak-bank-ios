# Android room model pipeline

The Android room contains the original project's 81 SceneKit models. It does not
replace them with icons, sprites, external assets, a WebView or a network service.
`ExportScene.swift` reads the original source and tessellates SceneKit's parametric
geometry from its explicit dimensions on the CPU. Model I/O's bridge was found to
silently substitute unit boxes and spheres, so it is deliberately not used. Meshes
are deduplicated; clothing, sleeves,
hats and hair use additions/removals from the same character, preserving fitted
surfaces. The original item-preview cameras and behavior book/watering can are
exported too. No iOS source files are changed.

SceneKit's shape primitive exposes no CPU vertices through Model I/O. Its original
star/heart path is therefore triangulated with concave-safe ear clipping, retaining
the original contour and extrusion depth. A narrow inset bevel ring approximates
SceneKit's bevel shading; it is not a replacement drawing or a simplified icon.
Every exported mesh is compared against the original geometry's bounding box
(0.02% relative tolerance, or 0.00001 for tiny geometry). Those original bounds are
bundled in the manifest and independently checked against the binary by the Python
validator. Fixed floor dimensions and the radius-one character sphere are additional
regression sentinels. Visual GPU QA remains necessary to verify shading and poses.

Generate on a Mac, one process at a time with simulators closed:

```sh
nice -n 15 xcrun swiftc -j 1 PiyakBank/Views/PiyakScene.swift \
  PiyakBank/Shared/PiyakActivityPlan.swift PiyakBank/Views/PiyakBehavior.swift \
  android/scripts/ExportScene.swift -o /tmp/piyak-android-scene-export
nice -n 15 /tmp/piyak-android-scene-export "$PWD"
python3 android/scripts/check_scene_assets.py
```

`scene.json` stores the source fingerprint, rig rest poses, all nine background
rooms, equipment deltas, preview framing and effect meshes. `meshes.bin` stores
little-endian float32 positions/normals and uint16 triangle indices. Every record
starts with a uint32 vertex count and a uint32 index count. Every vertex is six
float32 values, position XYZ then normal XYZ. There is no runtime asset download.

`PiyakRoomView` batches static model transforms on one low-priority CPU worker,
uploads vertex/index buffers to OpenGL ES 2 and animates eight character rigs.
Travel stays in the front aisle. Equipped plants, books, sofa, piano and puppy
change the choreography; repeated taps cannot queue overlapping interactions.
The Android renderer uses its own mobile clay lighting, rather than SceneKit's
physically based/shadow renderer, so exact pixel identity is not expected.

Host integration must call `onHostResume()` / `onHostPause()` with the host
lifecycle, pass user motion preference through `configure`, and expose accessible
buttons for play, rotate, zoom and reset. Rendering uses dirty mode, at most 23.81
animation frame requests per second, only while attached, visible and resumed.
Battery saver, thermal pressure at MODERATE or higher, and Android's disabled
animator scale stop the automatic animation. Still views redraw only on changes.
Lost EGL contexts restore the retained composition. Missing assets or unsupported
OpenGL show an explanatory fallback and leave the rest of the app usable.

The CPU asset validator is necessary but cannot prove GPU visual correctness.
Release QA must still inspect fitted equipment, all nine rooms, walking/contact
points, pause/resume and context loss on supported physical Android GPU vendors.
