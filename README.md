# chattea-workspace

Workspace repo for Chattea.

## Repos
- `chattea-fe`: Expo React Native app.
- `chattea-be`: GraphQL API, auth, realtime, SMS, upload.
- `chattea-terraform-aws`: AWS infrastructure.

## Clone
```sh
git clone --recurse-submodules https://github.com/ChatTeaDot/chattea-workspace.git
```

## Update submodules
```sh
git submodule update --init --recursive
```

## Notes
- Product code stays in each child repo.
- Cross-repo coordination belongs here only when it affects more than one repo.
