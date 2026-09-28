# 앱 아이콘

iOS·watchOS 앱 아이콘은 앱 속 삐약이와 같은 원본 모델로 만듭니다. `PiyakScene.swift`에서 Android용으로 내보낸 메시(`android/app/src/main/assets/scene/`)를 Blender Cycles로 렌더링하고, 배경과 반짝이를 합성합니다. 외부 3D 모델이나 이미지는 쓰지 않습니다.

## 결과물

| 파일 | 용도 |
|---|---|
| `PiyakBank/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png` | 기본 아이콘 · App Store |
| `PiyakBank/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_dark.png` | iOS 18 이상 다크 모드 |
| `PiyakBank/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_tinted.png` | iOS 18 이상 틴티드 (흑백 원본에 시스템이 색을 입힘) |
| `PiyakWatch Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon_1024.png` | watchOS (원형 마스크에 맞춘 구도) |

모두 1024×1024, 알파 채널 없는 RGB PNG입니다. `scripts/check_release_assets.py`가 네 이미지의 규격과 기본·다크·틴티드 슬롯을 모두 검사합니다. 2026-09-28에 개발자가 제공한 `PiyakBank_AppIcon.zip`의 PNG를 그대로 적용했습니다.

## 다시 만들기

일반 빌드는 저장소의 완성된 PNG를 사용하므로 Blender 설치나 재렌더링이 필요하지 않습니다. 원본을 다시 만들 때만 Python 3.11에서 실행합니다. 팬이 없는 노트북에서는 앱 빌드·시뮬레이터와 동시에 실행하지 않습니다.

```sh
pip install bpy==4.5.14 pillow numpy
python3 scripts/app_icon/render_chick.py /tmp/piyak-icon-master.png   # 2400px, CPU 렌더링이라 몇 분 걸림
python3 scripts/app_icon/make_icons.py /tmp/piyak-icon-master.png
python3 scripts/check_release_assets.py
```

`render_chick.py`에 `--preview`를 붙이면 640px로 빠르게 구도만 확인할 수 있습니다.

- 구도·조명은 `render_chick.py` 위쪽 상수(`CAMERA`, `TURN_DEG`, `LIGHTS`)에서, 배경색·반짝이는 `make_icons.py`의 `LIGHT`, `DARK`, `SPARKLES`에서 바꿉니다.
- 캐릭터 모델을 바꿨다면 먼저 [Android 장면 내보내기](../../android/scripts/SCENE.md)로 메시를 갱신한 뒤 다시 렌더링합니다.
- `scripts/GenerateAssets.swift`는 앱 아이콘을 덮어쓰지 않습니다.
- Android·Wear OS 런처 아이콘(`piyak_icon.png`)은 이 과정에 포함되지 않아 이전 아이콘을 그대로 씁니다.
- 아이콘은 빌드에 포함되므로, 바꾼 뒤에는 새 빌드를 올려야 App Store에 반영됩니다.
