#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
EVENT_NAME="${GITHUB_EVENT_NAME:-}"
REF_NAME="${GITHUB_REF_NAME:-}"
CURRENT_SHA="${GITHUB_SHA:-}"
BEFORE_SHA="${GITHUB_EVENT_BEFORE:-}"
DRY_RUN="${INPUT_DRY_RUN:-false}"
STATE_BRANCH="${INPUT_STATE_BRANCH:-keep-stuff-state}"
COMMIT_MESSAGE="${INPUT_COMMIT_MESSAGE:-chore: restore kept files}"

log() {
  printf '[Keep Stuff] %s\n' "$*"
}

warn() {
  printf '[Keep Stuff] WARNING: %s\n' "$*" >&2
}

normalize_item() {
  local base="$1"
  local item="$2"
  item="$(printf '%s' "$item" | sed 's/\r$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
  [ -z "$item" ] && return 1

  case "$item" in
    \#*) return 1 ;;
    true|false|enabled|disabled) return 1 ;;
    /*|../*|*/../*|*/..)
      warn "Ignoring unsafe path/branch value: $item"
      return 1
      ;;
  esac

  if [ "$base" = "." ]; then
    printf '%s' "$item" | sed 's#^\./##'
  else
    printf '%s/%s' "$base" "$item" | sed 's#^\./##'
  fi
}

read_marker_lines() {
  local marker="$1"
  local base
  base="$(dirname "$marker")"

  while IFS= read -r raw; do
    raw="$(printf '%s' "$raw" | sed 's/\r$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
    [ -z "$raw" ] && continue
    [[ "$raw" == \#* ]] && continue
    if normalized="$(normalize_item "$base" "$raw")"; then
      printf '%s\n' "$normalized"
    fi
  done < "$marker"
}

KEEP_REPO=false
KEEP_ALL=false

[ -f ".keep repo" ] && KEEP_REPO=true
[ -f ".keep all stuff" ] && KEEP_ALL=true

mapfile -t FILE_MARKERS < <(find . -type f -name '.keepfile' -print | sort)
mapfile -t FOLDER_MARKERS < <(find . -type f -name '.keepfolder' -print | sort)
mapfile -t TREE_MARKERS < <(find . -type f -name '.keeptree' -print | sort)
mapfile -t BRANCH_MARKERS < <(find . -type f -name '.keepbranch' -print | sort)

KEEP_FILES=()
KEEP_DIRS=()
KEEP_BRANCHES=()

for marker in "${FILE_MARKERS[@]}"; do
  while IFS= read -r item; do
    [ -n "$item" ] && KEEP_FILES+=("$item")
  done < <(read_marker_lines "$marker")
done

for marker in "${FOLDER_MARKERS[@]}" "${TREE_MARKERS[@]}"; do
  [ -n "$marker" ] || continue
  while IFS= read -r item; do
    [ -n "$item" ] && KEEP_DIRS+=("$item")
  done < <(read_marker_lines "$marker")
done

for marker in "${BRANCH_MARKERS[@]}"; do
  while IFS= read -r item; do
    [ -n "$item" ] && KEEP_BRANCHES+=("$item")
  done < <(read_marker_lines "$marker")
done

keep_path() {
  local path="$1"

  local name
  name="$(basename "$path")"
  if [[ "$name" == .keep* ]]; then
    return 0
  fi

  if [ "$KEEP_REPO" = true ] || [ "$KEEP_ALL" = true ]; then
    return 0
  fi

  local item dir
  for item in "${KEEP_FILES[@]}"; do
    [ "$path" = "$item" ] && return 0
  done

  for dir in "${KEEP_DIRS[@]}"; do
    [ "$path" = "$dir" ] && return 0
    [[ "$path" == "$dir/"* ]] && return 0
  done

  return 1
}

restore_deleted_files() {
  local restored=0
  local before="$1"

  [ -n "$before" ] || return 0
  [[ "$before" =~ ^0+$ ]] && return 0

  if ! git cat-file -e "$before^{commit}" 2>/dev/null; then
    log "Fetching the previous push commit $before for deletion detection."
    git fetch --no-tags origin "$before" --depth=1 >/dev/null 2>&1 || git fetch --no-tags origin >/dev/null 2>&1 || true
  fi

  if ! git cat-file -e "$before^{commit}" 2>/dev/null; then
    warn "Could not load previous commit $before; protected-file restoration was skipped."
    return 0
  fi

  while IFS= read -r -d '' path; do
    if keep_path "$path"; then
      log "Restoring protected file: $path"
      if [ "$DRY_RUN" != "true" ]; then
        git checkout "$before" -- "$path"
      fi
      restored=$((restored + 1))
    fi
  done < <(git diff --name-only --diff-filter=D -z "$before" "$CURRENT_SHA" || true)

  if [ "$restored" -gt 0 ] && [ "$DRY_RUN" != "true" ]; then
    git config user.name "Keep Stuff Bot"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add -A
    git commit -m "$COMMIT_MESSAGE"
    git push origin "HEAD:$REF_NAME"
  fi

  if [ "$restored" -gt 0 ]; then
    log "Protected file count handled: $restored"
  else
    log "No protected files needed restoration."
  fi
}

STATE_JSON='{"version":1,"branches":{}}'
STATE_FILE_SHA=""

default_branch() {
  gh api "repos/$REPO" --jq '.default_branch'
}

default_branch_sha() {
  local branch="$1"
  gh api "repos/$REPO/commits/$branch" --jq '.sha'
}

load_state() {
  local encoded
  encoded="$(gh api "repos/$REPO/contents/.keep-stuff-state.json?ref=$STATE_BRANCH" --jq '.content' 2>/dev/null || true)"
  if [ -n "$encoded" ]; then
    encoded="$(printf '%s' "$encoded" | tr -d '\r\n')"
    STATE_JSON="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null || true)"
    if [ -z "$STATE_JSON" ] || ! jq -e . >/dev/null 2>&1 <<<"$STATE_JSON"; then
      STATE_JSON='{"version":1,"branches":{}}'
    fi
  fi

  STATE_FILE_SHA="$(gh api "repos/$REPO/contents/.keep-stuff-state.json?ref=$STATE_BRANCH" --jq '.sha' 2>/dev/null || true)"
}

ensure_state_branch() {
  local db db_sha
  db="$(default_branch)"
  db_sha="$(default_branch_sha "$db")"

  if ! gh api "repos/$REPO/git/ref/heads/$STATE_BRANCH" >/dev/null 2>&1; then
    log "Creating state branch $STATE_BRANCH."
    gh api --method POST "repos/$REPO/git/refs" \
      -f "ref=refs/heads/$STATE_BRANCH" \
      -f "sha=$db_sha" >/dev/null
  fi
}

state_set_branch() {
  local branch="$1"
  local sha="$2"
  STATE_JSON="$(jq --arg branch "$branch" --arg sha "$sha" '.branches[$branch] = $sha' <<<"$STATE_JSON")"
}

state_get_branch() {
  local branch="$1"
  jq -r --arg branch "$branch" '.branches[$branch] // empty' <<<"$STATE_JSON"
}

branch_is_listed() {
  local needle="$1"
  local branch
  for branch in "${KEEP_BRANCHES[@]}"; do
    [ "$branch" = "$needle" ] && return 0
  done
  return 1
}

branch_should_be_kept() {
  local branch="$1"
  if [ "$KEEP_ALL" = true ]; then
    return 0
  fi
  branch_is_listed "$branch"
}

remember_current_branches() {
  [ "$KEEP_ALL" = true ] || [ "${#KEEP_BRANCHES[@]}" -gt 0 ] || return 0

  local row branch sha
  while IFS=$'\t' read -r branch sha; do
    [ -n "$branch" ] || continue
    if [ "$KEEP_ALL" = true ] || branch_is_listed "$branch"; then
      state_set_branch "$branch" "$sha"
    fi
  done < <(gh api --paginate "repos/$REPO/branches?per_page=100" --jq '.[] | [.name, .commit.sha] | @tsv' 2>/dev/null || true)

  if [ "$KEEP_ALL" = true ] && [ -n "$REF_NAME" ] && [ "$REF_NAME" != "$STATE_BRANCH" ]; then
    if sha="$(gh api "repos/$REPO/commits/$REF_NAME" --jq '.sha' 2>/dev/null)"; then
      state_set_branch "$REF_NAME" "$sha"
    fi
  fi
}

restore_missing_protected_branches() {
  [ "$KEEP_ALL" = true ] || [ "${#KEEP_BRANCHES[@]}" -gt 0 ] || return 0

  local branch saved_sha default_sha
  default_sha="$(default_branch_sha "$(default_branch)")"

  mapfile -t STATE_BRANCH_NAMES < <(jq -r '.branches | keys[]' <<<"$STATE_JSON")

  for branch in "${STATE_BRANCH_NAMES[@]}"; do
    [ -n "$branch" ] || continue
    if gh api "repos/$REPO/branches/$branch" >/dev/null 2>&1; then
      continue
    fi

    if ! branch_should_be_kept "$branch"; then
      continue
    fi

    saved_sha="$(state_get_branch "$branch")"
    [ -n "$saved_sha" ] || saved_sha="$default_sha"

    if [ "$DRY_RUN" = "true" ]; then
      log "Would recreate protected branch $branch at $saved_sha."
      continue
    fi

    log "Recreating protected branch $branch at $saved_sha."
    gh api --method POST "repos/$REPO/git/refs" \
      -f "ref=refs/heads/$branch" \
      -f "sha=$saved_sha" >/dev/null || warn "Could not recreate branch $branch."
  done
}

save_state() {
  [ "$KEEP_ALL" = true ] || [ "${#KEEP_BRANCHES[@]}" -gt 0 ] || return 0
  [ "$DRY_RUN" = "true" ] && return 0

  ensure_state_branch

  local body b64
  body="$(jq -S . <<<"$STATE_JSON")"
  b64="$(printf '%s' "$body" | base64 --wrap=0)"

  if [ -n "$STATE_FILE_SHA" ]; then
    gh api --method PUT "repos/$REPO/contents/.keep-stuff-state.json" \
      -f message="chore: update Keep Stuff branch state" \
      -f content="$b64" \
      -f branch="$STATE_BRANCH" \
      -f sha="$STATE_FILE_SHA" >/dev/null
  else
    gh api --method PUT "repos/$REPO/contents/.keep-stuff-state.json" \
      -f message="chore: create Keep Stuff branch state" \
      -f content="$b64" \
      -f branch="$STATE_BRANCH" >/dev/null
  fi
}

show_summary() {
  local mode="scoped markers"
  [ "$KEEP_ALL" = true ] && mode="all stuff"
  [ "$KEEP_REPO" = true ] && [ "$KEEP_ALL" = false ] && mode="repo"

  log "Mode: $mode"
  log "File markers: ${#FILE_MARKERS[@]}"
  log "Folder/tree markers: $(( ${#FOLDER_MARKERS[@]} + ${#TREE_MARKERS[@]} ))"
  log "Branch markers: ${#BRANCH_MARKERS[@]}"
  [ "$DRY_RUN" = "true" ] && log "Dry-run mode is enabled; no repository changes will be made."
}

if [ ! -d .git ]; then
  warn "No .git directory was found. Add actions/checkout before using Keep Stuff."
  exit 1
fi

show_summary
if [ "$EVENT_NAME" = "push" ]; then
  restore_deleted_files "$BEFORE_SHA"
fi

if [ "$KEEP_ALL" = true ] || [ "${#KEEP_BRANCHES[@]}" -gt 0 ]; then
  load_state
  remember_current_branches
  restore_missing_protected_branches
  save_state
fi

log "Keep Stuff finished."
