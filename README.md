# chattea-workspace

Workspace repo for Chattea. Child repos stay independent.

## Repos
- `chattea-fe`: Expo React Native app.
- `chattea-be`: GraphQL API, auth, realtime, SMS, upload.
- `chattea-terraform-aws`: AWS infrastructure.

## Clone
```sh
git clone https://github.com/ChatTeaDot/chattea-workspace.git
cd chattea-workspace
./scripts/clone-repos.sh
```

## Pull all repos
```sh
./scripts/pull-all.sh
```

## Notes
- Product code stays in each child repo.
- Child repos are not submodules.
- Cross-repo coordination belongs here only when it affects more than one repo.
