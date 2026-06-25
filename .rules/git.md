# Git Rules

## Branch

Use:

- `feat/<short-kebab-summary>`
- `fix/<short-kebab-summary>`
- `refactor/<short-kebab-summary>`
- `chore/<short-kebab-summary>`
- `docs/<short-kebab-summary>`
- `test/<short-kebab-summary>`

Rules:

- lowercase kebab-case
- no identity prefixes
- short, descriptive names

Examples:

- `feat/chat-room-search`
- `fix/login-token-refresh`

## Commit

Use Conventional Commits:

- `feat(scope): summary`
- `fix(scope): summary`
- `refactor(scope): summary`
- `chore(scope): summary`
- `docs(scope): summary`
- `test(scope): summary`

Rules:

- lowercase type
- scope required
- English summary
- summary under 72 chars

Examples:

- `feat(chat): add room search`
- `fix(auth): refresh expired token`

## Pull Request

- PR title follows the same format as commit messages.
- CI should reject invalid branch names and PR titles.
