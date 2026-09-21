# 개인정보·지원 페이지 게시

앱과 App Store 제출 자료가 사용하는 공개 주소입니다.

- 홈: <https://eric91405.github.io/piyak-bank-ios/>
- 개인정보 처리방침: <https://eric91405.github.io/piyak-bank-ios/privacy/>
- 지원: <https://eric91405.github.io/piyak-bank-ios/support/>

## 게시 소스

GitHub Pages의 **Deploy from a branch** 방식으로 `codex/app-store-launch` 브랜치의 `/docs`를 사용합니다. 이 브랜치를 `main`에 병합하지 않아도 문서를 게시할 수 있습니다. GitHub의 Jekyll 빌드가 `index.md`, `PRIVACY.md`, `SUPPORT.md`의 front matter와 `_config.yml`을 사용합니다. 별도의 로컬 빌드나 커스텀 Actions workflow는 필요하지 않습니다.

`APP_STORE.md`, `RELEASE_VALIDATION.md`, 이 문서, `quality/`, `screenshots/`는 공개 사이트에서 제외합니다. 제외 여부는 `_config.yml`에서 관리합니다. GitHub 저장소 자체는 공개이므로 사이트 제외가 저장소 파일의 공개 범위를 바꾸지는 않습니다.

## 최초 설정

1. 공개할 문서 변경을 검토하고 위 브랜치에 푸시합니다.
2. 저장소의 **Settings → Pages → Build and deployment**에서 **Deploy from a branch**를 선택합니다.
3. 브랜치는 `codex/app-store-launch`, 폴더는 `/docs`로 저장합니다.
4. GitHub의 Pages 빌드·배포가 성공한 뒤 위 세 주소가 열리는지 확인합니다. 개인정보 페이지 제목·운영자·문의 주소, 지원 페이지의 개인정보 링크도 확인합니다.

저장소 관리 권한이 있는 CLI에서는 아직 Pages 사이트가 없을 때 다음 요청으로 같은 설정을 만들 수 있습니다.

```sh
gh api --method POST repos/eric91405/piyak-bank-ios/pages \
  -f build_type=legacy \
  -f 'source[branch]=codex/app-store-launch' \
  -f 'source[path]=/docs'
```

이미 사이트가 있으면 먼저 `gh api repos/eric91405/piyak-bank-ios/pages`로 현재 설정을 확인합니다. 소스를 변경해야 할 때는 같은 필드를 `--method PUT`으로 보냅니다. Pages 설정은 Git 파일이 아니므로 `_config.yml`을 추가하거나 푸시하는 것만으로 최초 게시가 활성화되지는 않습니다.

## 변경과 확인

게시 소스 브랜치의 `/docs` 변경을 푸시하면 GitHub에서 사이트를 다시 빌드합니다. 배포 성공 여부와 실제 공개 페이지를 모두 확인한 뒤 앱의 지원 링크가 준비됐다고 기록합니다.

```sh
gh api repos/eric91405/piyak-bank-ios/pages
gh api repos/eric91405/piyak-bank-ios/pages/builds/latest
```

추후 출시 후보를 `main`에 병합하고 게시 기준도 옮길 때는 Pages 설정의 소스 브랜치를 명시적으로 `main`으로 변경합니다. 문서의 permalink와 프로젝트 baseurl을 유지하면 공개 주소는 바뀌지 않습니다. 게시 소스 브랜치는 설정을 옮기기 전에 삭제하지 않습니다.

참고: [GitHub Pages 게시 소스 설정](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site), [Pages REST API](https://docs.github.com/en/rest/pages/pages).
