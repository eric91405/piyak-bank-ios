# Android room model pipeline

The Android room contains the original project's 81 SceneKit models. It does not
replace them with icons, sprites, external assets, a WebView or a network service.
`ExportScene.swift` reads the original source and tessellates SceneKit's parametric
geometry from its explicit dimensions on the CPU. Model I/O's bridge was found to
silently substitute unit boxes and spheres, so it is deliberately not used. Meshes
are deduplicated; clothing, sleeves, hats and hair use additions/removals from the
same character, preserving fitted surfaces. The original item-preview cameras and behavior book/watering can are
exported too. The exporter reads the shared iOS model source without modifying it.

SceneKit's shape primitive exposes no CPU vertices through Model I/O. Its original
star/heart path is therefore triangulated with concave-safe ear clipping, retaining
the original contour and extrusion depth. A narrow inset bevel ring approximates
SceneKit's bevel shading; it is not a replacement drawing or a simplified icon.
Every exported mesh is compared against the original geometry's bounding box
(0.02% relative tolerance, or 0.00001 for tiny geometry). Those original bounds are
bundled in the manifest and independently checked against the binary by the Python
validator. Fixed floor dimensions and the radius-one character sphere are additional
regression sentinels. Visual GPU QA remains necessary to verify shading and poses.

The shared swept-tube model was corrected during catalog review. Choosing a new
world reference at each curve point had flipped the right cactus arm's final ring
by 180 degrees, producing an hourglass shape in both the original iOS thumbnail
and Android render. Cross-section axes now carry their orientation along the
curve; closed curves distribute residual twist across the loop. Small matching
spheres close the cactus branch tips. The asset checker requires both cactus arms'
corresponding ring normals to stay aligned, catching the former `-1` dot product
even though that mesh had valid indices and bounding boxes. The regenerated final
bundle contains 363 shared meshes and 246,752 triangles.

Generate on a Mac, one process at a time with simulators closed:

```sh
nice -n 15 xcrun swiftc -j 1 PiyakBank/Views/PiyakScene.swift \
  PiyakBank/Shared/PiyakActivityPlan.swift PiyakBank/Views/PiyakBehavior.swift \
  android/scripts/ExportScene.swift -o /tmp/piyak-android-scene-export
nice -n 15 /tmp/piyak-android-scene-export "$PWD"
python3 android/scripts/check_scene_assets.py
```

When the shared scene source changes, also run `scripts/GenerateAssets.swift` to
refresh the iOS/watchOS thumbnails, mascots, icons and source fingerprint. Copy the
81 refreshed iOS `thumb_*.imageset/image.png` files to Android's
`app/src/main/assets/thumbs/`, and refresh the app and Wear `piyak_icon.png` copies
from the generated iOS app icon. Shared portrait renderer changes must also bump
`WatchPortrait.rendererVersion` so Apple Watch does not retain old artwork.

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

## Completed emulator rendering validation

On 2026-09-21, `SceneRenderingTest` passed on the minimum supported Android API 26
emulator using `Android Emulator OpenGL ES Translator (Apple M4)`. This is emulator
evidence, not a physical Android GPU certification. The test creates an EGL
pbuffer and uses production `SceneAssets` and `RoomRenderer`; it does not capture
an app screen, interact with UI controls or modify bank data.

The final run rendered all 81 catalog previews at 320×320, nine complete room
combinations at 512×384, and nine combined outfits at 384×384. The nine room
combinations cover every catalog item once in its slot. Close-up outfit cameras
make hats, eyewear, neckwear and clothing intersections visible. The test also
destroyed and recreated the EGL context while retaining the scene; the restored
static render had identical pixels to the original.

Checks cover finite vertex data, unit normals, valid triangle indices, GL errors,
successful frames, foreground visibility, contrast, border clipping and duplicate
catalog images. Three intentionally flat, single-material rugs use a lower color
bin threshold: the cloud and star correctly produced only nine quantized bins,
while retaining 55 and 73 levels of contrast and unclipped silhouettes. All other
checks remain active. The final report had zero findings.

All nine category contact sheets, both combination sheets, and the cactus close-up
were visually reviewed after regeneration. The cactus branches were continuous
and capped. The reviewed static views showed no clipped hats, detached clothing
seams, exploding triangles or new unintended garment intersections. Curved hat
bands, glasses, necklaces and rug details retained their intended forms.

Run the instrumentation class
`com.minseo.piyakbank.scene.SceneRenderingTest` on a single emulator with builds
finished beforehand. It writes generated artifacts to the target app's private
`files/scene-gpu-qa/` directory:

- `report.json`: API/renderer identity, per-render metrics, findings and context recovery.
- `catalog-all-81.png` and `catalog-<slot>.png`: overview and detailed category sheets.
- `rooms-nine-combinations.png` and `outfits-nine-combinations.png`: fitted combinations.
- `catalog/`, `rooms/`, `outfits/`, `context-before.png`, `context-after.png`: individual renders.

Pull those generated files with `adb exec-out run-as <target-package>`; the isolated
UI test build uses `com.minseo.piyakbank.uitest`, while the ordinary debug build uses
`com.minseo.piyakbank`. Review the PNGs alongside the JSON report. Pixel metrics
cannot establish design quality alone. Physical Adreno/Mali GPU behavior, vendor
power management, and long-running animation/contact behavior still require
device testing; the emulator results do not replace that work.
