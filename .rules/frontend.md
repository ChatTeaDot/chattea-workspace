# Frontend Rules

```txt
src/app/              # Expo Router
src/features/<name>/  # Domain feature code
src/shared/           # Shared code
src/providers/        # Provider code
src/theme/            # Theme code
src/assets/           # images, fonts
```

- Feature code stays in `src/features/<name>/`.
- API calls stay in `src/features/<name>/api.ts`.
- Hooks stay in `src/features/<name>/hooks.ts`.
- Types stay in `src/features/<name>/types.ts`.
- Shared UI stays in `src/shared/components/`.
- File name: `kebab-case`.
- Platform file: `file-name.ios.tsx`, `file-name.android.tsx`.
- Use `@/` imports only across sibling folders: `@/<sibling>/<path>`.
- Use arrow function expressions for all functions, including hooks and components: `const func = () => {}`.
- Re-export modules through `index.ts`.
- Use `react-native-unistyles` for styling only.
