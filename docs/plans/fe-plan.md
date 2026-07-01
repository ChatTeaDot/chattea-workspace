# Chattea FE Plan

## Summary
- Expo React Native 채팅앱.
- 담당:
  - native UX
  - auth 화면/상태
  - optimistic chat UI
  - reconnect/refetch behavior
  - upload client state
- Backend GraphQL schema를 계약으로 사용.

## Stack
- `expo`, `react-native`, `typescript`, `expo-router`
- `@expo/ui`, `@legendapp/list`, `react-native-reanimated`, `react-native-keyboard-controller`
- `effect`, `graphql`, `graphql-request`, `graphql-ws`, `@tanstack/react-query`
- `react-native-unistyles`, `zeego`
- `@react-native-kakao/core`, `@react-native-kakao/user`
- `@sentry/react-native`, `@datadog/mobile-react-native`
- Config:
  - `eslint.config.mjs`
  - `prettier.config.mjs`
  - import order: `eslint-plugin-simple-import-sort`

## Release
- EAS Build for iOS/Android production builds.
- EAS Submit for App Store Connect / Google Play upload.
- EAS Update for OTA updates.
- GitHub Actions runs `typecheck`, `lint`, `test` before EAS release jobs.

## Auth
- 전화번호 로그인/가입.
- 카카오 로그인.
- 카카오 로그인 후 `requiresPhone`이면 전화번호 입력/인증 후 진입.
- App session은 BE가 발급하고 FE가 저장/첨부.

## Phone Verification UX
- 대상: 한국 번호만.
- 입력은 `01012345678`, BE 계약값은 E.164 `+821012345678`.
- 화면:
  - phone input screen: 한국 번호 형식만 표시/검증.
  - code screen: 6자리 입력, 60초 resend timer.
  - signup profile screen: 신규 번호 인증 후 nickname/terms 입력.
- GraphQL 흐름:
  - `requestPhoneCode(phone: String!)`
  - `verifyPhoneCode(phone: String!, code: String!)`
  - 기존 번호: `{ status: "LOGIN", session, user }` 수신 후 앱 진입.
  - 신규 번호: `{ status: "SIGNUP_REQUIRED", signupToken }` 수신 후 프로필/약관 화면 이동.
  - `completePhoneSignup(signupToken: String!, nickname: String!, termsAccepted: Boolean!)` 성공 후 앱 진입.
- Kakao flow도 `requiresPhone`이면 같은 phone/code/signup completion 화면 재사용.
- 실패 메시지는 구체 code leak 없이 표시.

## Chat
- `@legendapp/list`.
- GraphQL Subscription realtime.
- optimistic message.
- streaming assistant word fade-in.
- attachment upload.
- reconnect 후 refetch/dedupe.
- optimistic temp id -> server id 교체 가능해야 함.

## Native UI
- iOS: `@expo/ui/swift-ui`
- Android: `@expo/ui/jetpack-compose`
- auth controls, forms, settings, menus, alerts 적극 사용.
- chat bubble/list internals는 RN/Reanimated 유지.

## Tests
- `typecheck`, `lint`, `format:check`, `test`.
- phone login/signup flow.
- Kakao login + phone completion flow.
- chat subscription dedupe.
- streaming fade-in.
- attachment state.
- iOS/Android native UI manual run.
