# Keep Stuff

Keep Stuff is a GitHub Action for protecting repository content from deletion.

## The `.addkeep` file

Users can declare the Keep Stuff action in one file:

```text
import treatwashere/keep-stuff@main
```

Keep Stuff reads that import and uses the supported protection markers in the same repository.

**GitHub limitation:** a plain `.addkeep` file cannot start a GitHub Action by itself. GitHub only executes workflow files from `.github/workflows/`. The `.addkeep` format is supported by the action, but invoking the action still requires a GitHub Actions workflow or another installer mechanism.

## Supported protection markers

- `.keepfolder` — protects folders listed inside the marker.
- `.keepbranch` — protects branches listed inside the marker.
- `.keeprepo` — protects all tracked repository files.
- `.keepallstuff` — protects all tracked files and remembered branches.

The old `.keepfile` and `.keeptree` markers are no longer supported.

## Standard GitHub Actions reference

```yaml
- uses: treatwashere/keep-stuff@main
```

Keep Stuff restores protected files after deletion and can recreate protected branches from their remembered commit.

## Empty folders

Git does not track empty directories by themselves, so a tracked file is still required for an empty folder to exist in Git.
