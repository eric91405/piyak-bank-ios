# CLAUDE.md

삐약뱅크(PiyakBank) — 근무 시간을 기록하고 병아리의 방을 꾸미는 iOS · watchOS 앱. 무료 출시 준비 중이며 광고·계정·인앱결제가 없다.

## 빌드와 검증

```sh
swift test --jobs 1                       # 계산·저장 회귀 테스트 (SPM 타깃 PiyakCore)
python3 scripts/check_release_assets.py   # 에셋·개인정보 매니페스트 검사
xcodebuild -project PiyakBank.xcodeproj -scheme PiyakBank \
  -configuration Release -jobs 1 -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PiyakBank CODE_SIGNING_ALLOWED=NO build
```

발열을 줄이려면 `nice -n 15`와 `--jobs 1`을 쓰고, 빌드 중에는 시뮬레이터를 종료한다.

모델(`PiyakScene.swift`)을 수정하면 미리보기 이미지를 반드시 재생성해야 한다. 생성기와 원본의 SHA-256 지문을 CI가 대조하므로 그러지 않으면 검사에 실패한다.

```sh
xcrun swiftc PiyakBank/Views/PiyakScene.swift scripts/GenerateAssets.swift -o /tmp/piyak-assets
/tmp/piyak-assets "$PWD"
```

## 구조

타깃 3개(앱 / `PiyakWatch Watch App` / `PiyakWidgetExtension`)가 `PiyakBank/Shared/`를 공유한다. **Xcode 파일 시스템 동기화 그룹**을 쓰므로 폴더에 `.swift`를 넣으면 자동으로 타깃에 포함된다. `project.pbxproj`를 손으로 편집하지 말 것. 워치·위젯에만 넣을 파일은 pbxproj의 `membershipExceptions`에 추가해야 한다.

```
PiyakBank/App/       진입점, 서비스 와이어링, 라우팅
PiyakBank/Shared/    EarningsCalculator, RewardPolicy, Economy(원장), AppConfig, DesignTokens
PiyakBank/Services/  SessionController, WorkSession, WatchSync, NotificationScheduler
PiyakBank/Views/     Home, PiyakScene(SceneKit), Decorate, History, Settings
Tests/PiyakCoreTests/  Swift Testing. Views/SceneKit은 커버 안 됨
scripts/             에셋 생성, 장면·행동 검증, 릴리스 리소스 검사
```

## 깨뜨리면 안 되는 규칙

- **시급과 포인트는 완전히 분리된다.** 수익은 `EarningsCalculator`, 포인트는 `RewardPolicy`. 시급이 포인트에 영향을 주면 안 된다.
- **금액 계산은 밀리초 × 시급의 분자를 유지하다 마지막에 한 번만 나눈다.** 시급을 먼저 3600으로 나누면 반복 소수 오차가 난다. 날짜별 배분에도 누적 잔여값을 넘겨 총액이 보존되어야 한다.
- **포인트 하루 한도(4,800P)의 날짜 기준은 KST 고정**(`RewardPolicy.calendar`). 수익과 달력은 `Calendar.current`. 둘을 섞지 말 것.
- **잔액은 단일 필드가 아니라 `PointTransaction` 원장의 합**이다. `legacy` 종류는 현재 잔액에서 제외한다.
- **저장이 성공해야 상태가 바뀐다.** 근무 종료와 포인트 적립은 `economy.transaction(restoring:)` 한 단위로 처리하고, 실패 시 SwiftData 모델 값까지 복원한다. `autosaveEnabled = false`다.
- **보상 시간은 monotonic clock과 부팅 식별자로 방어한다.** 기기 시각을 앞당겨도 보상이 늘면 안 되고, 수동 기록 추가·수정·삭제로 포인트가 생기거나 사라지면 안 된다.
- **워치 명령은 ID·대상 세션·생성 시각을 검사**하고, iPhone의 저장 확인 응답을 받아야 워치 상태를 바꾼다. 오프라인 명령을 예약하지 않는다.

## 관례

- UI 문자열은 한국어. 현재 `ko` 단일 로컬라이즈이며 문자열이 뷰 안에 직접 박혀 있다.
- 서드파티 의존성 없음. API 키·서버 없음. 기기 밖으로 데이터를 보내지 않는다.
- 색상은 `PB.C` 토큰만 쓴다. 다크 모드 대응이 `adaptive()`에 들어 있다.
- 3D는 전부 코드로 만든 SceneKit 기하 모델이다. 다운로드 자산이나 외부 3D 모델을 추가하지 않는다.
- 최소 지원: iOS 17.0 / watchOS 10.0.

## 주의

- 포인트는 가상이며 환금·송금·인출 기능이 없다. 앱은 은행이나 급여 지급 서비스가 아니다. 이 선을 넘는 문구나 기능을 추가하면 심사 리스크가 생긴다.
- 예상 수익은 세전 단순 추정치다. 세금·수당을 반영한다고 표시하지 않는다.
- SwiftData 스토어는 App Group(`group.com.minseo.piyakbank`)에 있다. 위치를 다시 옮기면 마이그레이션이 필요하다.
- 기존 저장소는 `StoreMigration`의 SQLite backup API로 WAL까지 일관되게 백업한 뒤 최종 파일 이름으로 게시한다. 개별 store/WAL 파일 복사나 실패 후 이전 저장소 재사용은 데이터 유실·분기 위험이 있어 금지한다. 기존 자동 설정이 App Group 안의 `default.store`를 선택했을 수 있으므로 이전 후보 위치를 모두 확인한다.
- 이전 사본은 보존하되 사용자 요청의 전체 초기화에서는 `beforeReset`이 이전 사본과 중단된 staging을 정리한다. 정리 실패 시 활성 저장소를 초기화하지 않는다.
- 알림은 실제 pending 요청을 기준으로 보충한다. 권한 확인·저장 성공 전에 계획을 완료로 캐시하면 재허용/실패 복구가 막힌다.
- 워치 상태와 초상화는 분리 전송하며 `WatchStateCache`가 현재 장착 정보에 맞는 이미지만 표시한다. 렌더링이 바뀌면 `WatchPortrait.rendererVersion`을 올린다.
