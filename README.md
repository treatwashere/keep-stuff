# Keep Stuff

Keep Stuff is a GitHub Action for protecting repository content from deletion.

## One-file setup with the Keep Stuff GitHub App

The easiest setup is designed around a single `.addkeep` file.

**[![Add Keep Stuff to GitHub](https://img.shields.io/badge/Add%20Keep%20Stuff%20to%20GitHub-Install%20App-2ea44f?logo=github)](https://github.com/apps/keep-stuff/installations/new)**

Click the button above to install the **Keep Stuff GitHub App** on a repository.

1. Install the **Keep Stuff GitHub App** on the repository.
2. Create a file named `.addkeep` in the repository root.
3. Put this exact line inside it:

```text
import treatwashere/keep-stuff@main
```

4. Push the file.

The Keep Stuff App watches repository push events, detects the `.addkeep` import, and can add the required GitHub Actions workflow automatically.

> **App status:** The Keep Stuff GitHub App implementation is ready in `app/`. The App still needs to be registered with GitHub and deployed to a public HTTPS endpoint before the install button can be used by others.

## Supported protection markers

- `.keepfolder` — protects folders listed inside the marker.
- `.keepbranch` — protects branches listed inside the marker.
- `.keeprepo` — protects all tracked repository files.
- `.keepallstuff` — protects all tracked files and remembered branches.

The old `.keepfile` and `.keeptree` markers are no longer supported.

## Standard GitHub Actions setup

Until the Keep Stuff App is registered and installed, the action can be used directly from a workflow:

```yaml
name: Keep Stuff

on:
  push:
  create:
  delete:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  keep:
    if: github.ref != 'refs/heads/keep-stuff-state'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: treatwashere/keep-stuff@main
```

Keep Stuff restores protected files after deletion and can recreate protected branches from their remembered commit.

## Empty folders

Git does not track empty directories by themselves, so a tracked file is still required for an empty folder to exist in Git.
