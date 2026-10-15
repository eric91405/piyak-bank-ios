# 첫 사용 가이드 App Store 제출 — 2026-10-15

사용자가 시뮬레이터에서 가이드를 직접 확인한 뒤 App Store 업데이트를 요청했다. 초기 구현·화면 검증은 [첫 사용 가이드 검증 기록](onboarding-20261015.md)을 따른다.

## 버전과 배포 패키지

- Apple 공개 조회와 App Store Connect에서 기존 공개 버전 **1.0.1**을 확인했다. 공개 조회의 해당 버전 출시 시각은 2026-10-13 03:05 KST다.
- 기능 소스는 `870c443`, 제출 소스는 세 타깃의 버전을 올린 `5fe1b36`이다. Xcode 프로젝트 API로 앱·Watch·위젯의 Debug·Release를 모두 **1.0.2 (7)**로 맞췄다.
- Xcode 27.0 (27A266a), 컴파일 작업 1개, 실행 중인 시뮬레이터 없이 Release Archive를 생성했다. 실제 세 번들의 Info.plist에서 버전·빌드와 최소 OS(iOS 17.0 / watchOS 10.0)를 확인했다.
- 기존 절차대로 unsigned Archive 사본에 원본 entitlement를 보존하고 App Store 배포 서명으로 내보냈다. `scripts/verify_distribution_ipa.py`가 실제 IPA 세 타깃의 엄격한 서명 검증·프로파일·팀·App Group·디버그 권한 비활성화·개인정보 매니페스트를 확인했다.
- 검증 IPA SHA-256: `02515ad2f4b45fe63c0c4fd646b0a18843c637ed231de6588c9c6ad5fb6f6c08`.
- 기능 커밋의 [GitHub 검사](https://github.com/eric91405/piyak-bank-ios/actions/runs/38677898154)는 Swift 회귀 124개·실제 구버전 스키마 이전·세 타깃 Release 빌드를 통과했다. 이번 배포 준비에서도 리소스 검사·`git diff --check`·Archive·실제 배포 IPA 검증을 통과했다.

## Apple 업로드와 심사 제출

- **2026-10-15 14:14:46 KST**에 Xcode의 `Upload succeeded`·`EXPORT SUCCEEDED`를 확인했다. TestFlight에서 **1.0.2 (7)**의 처리 중 → 제출 준비 완료 상태를 확인했다.
- App Store Connect 세션은 사용자가 로그인했고, 갱신된 Apple Developer Program 계약도 사용자가 직접 동의했다.
- 1.0.2 초안에 한국어 업데이트 설명과 영문 심사 Notes를 저장한 뒤 다시 불러와 일치를 확인했다. 안내 4장 → 시급 설정, 설정에서 다시 보기, iPhone 연결이 필요한 Watch 제어, 가상 포인트 정책, 정지 장면·접근성 동작과 검증 한계를 설명했다.
- 기존 스크린샷·상품 설명·심사 연락처를 유지했다. 개인정보·지원 공개 URL은 HTTP 200을 확인했다. 무료·대한민국 단독 배포 범위를 변경하지 않았으며 **승인 후 자동 출시·모든 사용자에게 즉시 업데이트·기존 평가 유지** 선택을 확인했다.
- 빌드 **7 / 버전 1.0.2**를 연결하고 **2026-10-15 14:18 KST** 심사를 제출했다. 제출 상세에서 **1.0.2 (7)·제출된 항목 1개·심사 대기 중**을 확인했다.
- 제출 ID: `aa2bc1ee-6ada-484d-b77d-3e84f3155b29`. [Apple 제출 상세](https://appstoreconnect.apple.com/apps/6816129028/distribution/reviewsubmissions/details/aa2bc1ee-6ada-484d-b77d-3e84f3155b29).

Apple 심사 승인과 1.0.2의 공개 출시는 아직 확인하지 않았다. 이번 제출을 실물 iPhone–Watch 전체 회귀나 수동 VoiceOver 낭독 검증의 완료로 해석하지 않는다. Android 배포는 수행하지 않았다.

## 산출물

공개 저장소 밖의 `/Users/minseo/develop/output/piyak-onboarding-release-20261015/`에 Archive·IPA·검증 결과·업로드 로그·업데이트 설명·심사 Notes·소스 지문을 보관한다. 제출 대상 Archive는 `PiyakBank-1.0.2-entitlements.xcarchive`, 검증 IPA는 `export/PiyakBank.ipa`, 제출 증빙은 `submitted-build7.jpg`다. 비공개 심사 연락처·인증서·프로파일은 GitHub에 포함하지 않는다.
