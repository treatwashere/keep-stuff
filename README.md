# Keep Stuff

Keep Stuff is a GitHub Action for declaring repository content that should be kept. It can restore protected files after a deletion and recreate protected branches from their last remembered commit.

## Markers

| Marker | What it keeps |
| --- | --- |
| `.keep file` | Specific files listed inside the marker |
| `.keep folder` | Everything under the listed folder paths |
| `.keep tree` | Everything under the listed Git tree paths |
| `.keep branch` | Specific branch names listed inside the marker |
| `.keep repo` | All tracked files in the repository |
| `.keep all stuff` | All tracked files plus branches remembered by Keep Stuff |

The marker files themselves are also protected.

## One-time workflow setup

A marker file by itself cannot start GitHub Actions. GitHub only runs workflow files from `.github/workflows/`, so the repository needs this one-time workflow:

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

After that, the `.keep ...` markers control what gets protected.

## Examples

### Keep selected files

Create a file named `.keep file`:

```text
README.md
src/config.json
public/index.html
```

Paths are relative to the folder containing the marker.

### Keep a folder

Create `.keep folder` and list directories:

```text
assets
src/components
```

Folder protection is recursive.

### Keep a Git tree

Create `.keep tree` and list tree paths:

```text
packages
docs
```

Tree protection is recursive.

### Keep branches

Create `.keep branch`:

```text
main
production
release
```

Keep Stuff stores the latest known commit for protected branches in a dedicated `keep-stuff-state` branch. If a protected branch is deleted, the action recreates it from that saved commit.

### Keep the entire repository

Create an empty file named:

```text
.keep repo
```

This protects tracked files.

### Keep absolutely everything

Create an empty file named:

```text
.keep all stuff
```

This enables repository-wide file protection and remembers branches so deleted branches can be recreated.

## Behavior

Keep Stuff restores deletions; it does not overwrite a protected file merely because its contents were edited. A newly created protected file becomes protectable after it exists in a push, so a later deletion can be restored from the previous commit.

Use `dry-run: "true"` to preview actions:

```yaml
- uses: treatwashere/keep-stuff@main
  with:
    dry-run: "true"
```

## Empty folders

Git does not track empty directories by themselves. To keep an empty folder present, the folder still needs a tracked marker file such as `.keep folder`.

## License

MIT
