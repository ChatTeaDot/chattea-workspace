# ChatTea 워크스페이스

ChatTea 모노레포 워크스페이스. 소개팅/매칭 모바일 앱(iOS/Android)과 익명 커뮤니티를 위한 프론트엔드·백엔드를 git submodule로 묶어둔다.

## 구성

| 경로 | 레포 | 설명 |
|------|------|------|
| `chattea-fe` | [ChatTeaDot/chattea-fe](https://github.com/ChatTeaDot/chattea-fe) | Expo React Native 앱 + 커뮤니티 WebView용 Vite React 웹 |
| `chattea-be` | [ChatTeaDot/chattea-be](https://github.com/ChatTeaDot/chattea-be) | NestJS GraphQL API + PostgreSQL |
| `docs/` | — | PRD, 제품 문서, FE/BE/인프라 계획 |
| `design/` | — | 디자인 시스템, 화면 스펙, 레퍼런스 |
| `DESIGN.md` | — | 디자인 토큰 소스 |

## 시작하기

```bash
git clone --recurse-submodules https://github.com/ChatTeaDot/chattea-workspace.git
cd chattea-workspace
git submodule update --init --recursive
```

각 서브모듈의 개발/검증 절차는 해당 레포의 README를 따른다.

- [chattea-fe/README.md](https://github.com/ChatTeaDot/chattea-fe/blob/develop/README.md)
- [chattea-be/README.md](https://github.com/ChatTeaDot/chattea-be/blob/develop/README.md)

## 개발 규칙

- 브랜치: `feat|fix|refactor|chore|docs|test/<kebab-summary>`, 베이스는 `develop`
- 커밋·PR 제목: Conventional Commits, 스코프 필수, 72자 이내
- 머지: `develop`으로 squash merge 후 브랜치 삭제
- CI: `.github/workflows/ci.yml`에서 backend / frontend / operations 게이트 실행

## 문서

- 제품 요구사항: `docs/product/PRD.md`
- FE 계획: `docs/plans/fe-plan.md`
- BE 계획: `docs/plans/be-plan.md`
- 인프라 계획: `docs/plans/infra-plan.md`
