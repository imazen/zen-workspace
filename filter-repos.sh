#!/bin/bash
# filter-repos.sh — Surgical git history cleanup for zen repos
#
# For each repo: mirror-clone from remote, filter, compare HEAD tree against
# local copy, preserve tags/releases/branches, then optionally force-push.
#
# Usage:
#   ./filter-repos.sh [--dry-run]     # compare only, no push
#   ./filter-repos.sh --push          # actually force-push after verification
#
# Prerequisites:
#   - git-filter-repo installed
#   - gh CLI authenticated
#   - All local repos committed and pushed (pre-filter state)

set -euo pipefail

PUSH=false
DRY_RUN=true
if [[ "${1:-}" == "--push" ]]; then
    PUSH=true
    DRY_RUN=false
fi

ZEN_DIR="/home/lilith/work/zen"
PRE_FILTER_DIR="/home/lilith/work/pre-filter"
POST_FILTER_DIR="/home/lilith/work/post-filter"
BACKUP_DIR="/mnt/v/dev/pre-filter-backups"
LOG_FILE="/tmp/zen-filter-$$.log"

mkdir -p "$PRE_FILTER_DIR" "$POST_FILTER_DIR" "$BACKUP_DIR"
echo "Pre-filter backups: $PRE_FILTER_DIR" | tee "$LOG_FILE"
echo "Post-filter mirrors: $POST_FILTER_DIR" | tee -a "$LOG_FILE"
echo "Zip backups: $BACKUP_DIR" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE"
echo ""

# ─── Surgical removal list ───────────────────────────────────────────────
# Each entry: REPO|REMOTE|FILTER_ARGS
# FILTER_ARGS are passed to git filter-repo --invert-paths
#
# These paths were verified as:
#   - Not on HEAD (already removed)
#   - Only in history (bloating .git)
#   - Not referenced by any code on HEAD
REPOS=(
    "zenjpeg|https://github.com/imazen/zenjpeg.git|--path ssimulacra2-fork/ssimulacra2/test_data/"
)

# ─── Helper functions ────────────────────────────────────────────────────

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
err() { echo "[$(date +%H:%M:%S)] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

check_worktrees() {
    local repo_dir="$1"
    local name="$2"
    if [ ! -d "$repo_dir/.git" ]; then return 0; fi
    local wt_count
    wt_count=$(cd "$repo_dir" && git worktree list 2>/dev/null | grep -cv "$(pwd)" || true)
    if [ "$wt_count" -gt 0 ]; then
        err "$name has $wt_count active worktree(s):"
        (cd "$repo_dir" && git worktree list 2>/dev/null | grep -v "$(pwd)") | tee -a "$LOG_FILE" >&2
        return 1
    fi
    return 0
}

check_clean() {
    local repo_dir="$1"
    local name="$2"
    if [ ! -d "$repo_dir/.git" ]; then return 0; fi
    local status
    status=$(cd "$repo_dir" && git status --porcelain --ignore-submodules=dirty 2>/dev/null | grep -v '^??' | head -5)
    if [ -n "$status" ]; then
        err "$name has uncommitted changes:"
        echo "$status" | tee -a "$LOG_FILE" >&2
        return 1
    fi
    return 0
}

compare_branch_tree() {
    # Compare a single branch's tree between filtered mirror and local repo
    local filtered_dir="$1"
    local local_dir="$2"
    local name="$3"
    local branch="$4"

    local filtered_ref="refs/heads/$branch"
    local local_ref

    # Local might have it as a local branch or as origin/<branch>
    if (cd "$local_dir" && git rev-parse --verify "$branch" &>/dev/null); then
        local_ref="$branch"
    elif (cd "$local_dir" && git rev-parse --verify "origin/$branch" &>/dev/null); then
        local_ref="origin/$branch"
    else
        err "$name: branch '$branch' exists in filtered mirror but not locally"
        return 1
    fi

    # Compare file lists
    local diff_output
    diff_output=$(diff \
        <(git -C "$filtered_dir" ls-tree -r "$filtered_ref" --name-only | sort) \
        <(cd "$local_dir" && git ls-tree -r "$local_ref" --name-only | sort) \
    ) || true

    if [ -n "$diff_output" ]; then
        err "$name/$branch: file lists DIFFER after filter!"
        echo "$diff_output" | head -10 | tee -a "$LOG_FILE" >&2
        return 1
    fi

    # File lists match — verify blob content is identical
    local mismatch=0
    while IFS= read -r file; do
        local fsha lsha
        fsha=$(git -C "$filtered_dir" rev-parse "$filtered_ref:$file" 2>/dev/null || echo "MISSING")
        lsha=$(cd "$local_dir" && git rev-parse "$local_ref:$file" 2>/dev/null || echo "MISSING")
        if [ "$fsha" != "$lsha" ]; then
            err "$name/$branch: CONTENT MISMATCH in $file"
            mismatch=$((mismatch + 1))
            if [ "$mismatch" -ge 5 ]; then
                err "$name/$branch: (stopping after 5 mismatches)"
                break
            fi
        fi
    done < <(cd "$local_dir" && git ls-tree -r "$local_ref" --name-only)

    if [ "$mismatch" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

compare_all_branches() {
    local filtered_dir="$1"  # bare mirror
    local local_dir="$2"
    local name="$3"

    # Get all branches in the filtered mirror
    local branches
    branches=$(git -C "$filtered_dir" branch --format='%(refname:short)' 2>/dev/null)

    if [ -z "$branches" ]; then
        err "$name: no branches found in filtered mirror"
        return 1
    fi

    local failed=0
    local checked=0
    while IFS= read -r branch; do
        if compare_branch_tree "$filtered_dir" "$local_dir" "$name" "$branch"; then
            checked=$((checked + 1))
        else
            failed=$((failed + 1))
        fi
    done <<< "$branches"

    if [ "$failed" -eq 0 ]; then
        log "$name: all $checked branches verified identical"
        return 0
    else
        err "$name: $failed of $((checked + failed)) branches FAILED verification"
        return 1
    fi
}

# ─── Pre-flight checks ──────────────────────────────────────────────────

log "=== Pre-flight checks ==="

FAILED=false
for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    local_dir="$ZEN_DIR/$name"

    if [ ! -d "$local_dir" ]; then
        err "$name: local directory not found at $local_dir"
        FAILED=true
        continue
    fi

    if ! check_worktrees "$local_dir" "$name"; then
        FAILED=true
    fi

    if ! check_clean "$local_dir" "$name"; then
        FAILED=true
    fi

    # Check local is up to date with remote
    (cd "$local_dir" && git fetch origin 2>/dev/null)
    local_head=$(cd "$local_dir" && git rev-parse HEAD 2>/dev/null)
    remote_head=$(cd "$local_dir" && git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null || echo "NONE")

    if [ "$local_head" != "$remote_head" ] && [ "$remote_head" != "NONE" ]; then
        err "$name: local HEAD ($local_head) != remote HEAD ($remote_head)"
        err "  Push local changes first, or pull remote changes."
        FAILED=true
    fi
done

if $FAILED; then
    err ""
    err "Pre-flight checks failed. Fix the above issues and retry."
    exit 1
fi

log "All pre-flight checks passed."
echo ""

# ─── Backup release metadata ────────────────────────────────────────────

log "=== Backing up release metadata ==="

for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    local_dir="$ZEN_DIR/$name"
    backup_dir="$POST_FILTER_DIR/$name-meta"
    mkdir -p "$backup_dir"

    # Save tags
    (cd "$local_dir" && git tag -l) > "$backup_dir/tags-before.txt"
    tag_count=$(wc -l < "$backup_dir/tags-before.txt")

    # Save branches
    (cd "$local_dir" && git branch -a) > "$backup_dir/branches-before.txt"

    # Save GitHub releases
    release_count=0
    if (cd "$local_dir" && gh release list --limit 100 > "$backup_dir/releases-before.txt" 2>/dev/null); then
        release_count=$(wc -l < "$backup_dir/releases-before.txt")
    fi

    # Save tag→SHA mapping
    (cd "$local_dir" && git show-ref --tags) > "$backup_dir/tag-shas-before.txt" 2>/dev/null || true

    log "$name: $tag_count tags, $release_count releases backed up"
done

echo ""

# ─── Mirror clone + filter ───────────────────────────────────────────────

log "=== Cloning and filtering ==="

for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    local_dir="$ZEN_DIR/$name"
    mirror_dir="$POST_FILTER_DIR/$name-mirror"
    backup_dir="$POST_FILTER_DIR/$name-meta"

    # Record .git size before
    before_size=$(du -sh "$local_dir/.git" | cut -f1)

    log "$name: cloning mirror from $remote ..."
    git clone --mirror "$remote" "$mirror_dir" 2>&1 | tail -2 | tee -a "$LOG_FILE"

    mirror_size_before=$(du -sh "$mirror_dir" | cut -f1)

    log "$name: filtering with: --invert-paths $filters"
    # shellcheck disable=SC2086
    git -C "$mirror_dir" filter-repo --invert-paths $filters --force 2>&1 | tee -a "$LOG_FILE"

    # filter-repo strips the origin remote — re-add it for pushing
    git -C "$mirror_dir" remote add origin "$remote"

    mirror_size_after=$(du -sh "$mirror_dir" | cut -f1)
    log "$name: mirror $mirror_size_before → $mirror_size_after"

    # Verify tags survived
    tags_after=$(git -C "$mirror_dir" tag -l | wc -l)
    tags_before=$(wc -l < "$backup_dir/tags-before.txt")
    if [ "$tags_after" -ne "$tags_before" ]; then
        err "$name: tag count changed! Before: $tags_before, After: $tags_after"
        diff <(sort "$backup_dir/tags-before.txt") <(git -C "$mirror_dir" tag -l | sort) | head -20 | tee -a "$LOG_FILE" >&2
    else
        log "$name: all $tags_before tags preserved"
    fi

    # Verify branches survived
    branches_after=$(git -C "$mirror_dir" branch | wc -l)
    log "$name: $branches_after branches in filtered mirror"

    echo ""
done

# ─── Compare HEAD trees ─────────────────────────────────────────────────

log "=== Verifying all branch content matches local ==="

ALL_MATCH=true
for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    local_dir="$ZEN_DIR/$name"
    mirror_dir="$POST_FILTER_DIR/$name-mirror"

    if ! compare_all_branches "$mirror_dir" "$local_dir" "$name"; then
        ALL_MATCH=false
        err "$name: BRANCH VERIFICATION FAILED — will NOT push"
    fi
done

if ! $ALL_MATCH; then
    err ""
    err "Some repos have branch mismatches. Review above and fix before pushing."
    if $DRY_RUN; then
        log "Dry run complete. Mirror repos preserved in $POST_FILTER_DIR for inspection."
    fi
    exit 1
fi

log "All branches verified identical."
echo ""

# ─── Force push (if --push) ─────────────────────────────────────────────

if $DRY_RUN; then
    log "=== DRY RUN — not pushing ==="
    log "Mirror repos preserved in $POST_FILTER_DIR"
    log "Re-run with --push to force-push filtered history."
    echo ""

    # Print summary
    log "=== Summary ==="
    for entry in "${REPOS[@]}"; do
        IFS='|' read -r name remote filters <<< "$entry"
        local_dir="$ZEN_DIR/$name"
        mirror_dir="$POST_FILTER_DIR/$name-mirror"
        before=$(du -sh "$local_dir/.git" | cut -f1)
        after=$(du -sh "$mirror_dir" | cut -f1)
        log "$name: $before → $after (filtered: $filters)"
    done
    exit 0
fi

log "=== Force pushing ==="

for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    local_dir="$ZEN_DIR/$name"
    mirror_dir="$POST_FILTER_DIR/$name-mirror"

    # Move local repo to pre-filter backup BEFORE pushing
    pre_dir="$PRE_FILTER_DIR/$name"
    if [ -d "$pre_dir" ]; then
        err "$name: $pre_dir already exists — aborting to avoid overwrite"
        exit 1
    fi
    log "$name: backing up $local_dir → $pre_dir"
    mv "$local_dir" "$pre_dir"

    log "$name: force pushing all branches and tags..."
    git -C "$mirror_dir" push origin --force --all 2>&1 | tee -a "$LOG_FILE"
    git -C "$mirror_dir" push origin --force --tags 2>&1 | tee -a "$LOG_FILE"

    log "$name: pushed successfully"
done

echo ""

# ─── Verify releases survived ───────────────────────────────────────────

log "=== Verifying GitHub releases ==="

for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    backup_dir="$POST_FILTER_DIR/$name-meta"

    releases_before=$(wc -l < "$backup_dir/releases-before.txt" 2>/dev/null || echo 0)
    if [ "$releases_before" -gt 0 ]; then
        # Use gh with the repo flag since local dir was moved
        org_repo=$(echo "$remote" | sed 's|.*github.com/||; s|\.git$||')
        releases_after=$(gh release list --repo "$org_repo" --limit 100 2>/dev/null | wc -l)
        if [ "$releases_after" -ne "$releases_before" ]; then
            err "$name: release count changed! Before: $releases_before, After: $releases_after"
        else
            log "$name: all $releases_before releases intact"
        fi
    fi
done

echo ""

# ─── Fresh clone into zen/ ──────────────────────────────────────────────

log "=== Cloning fresh copies ==="

for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    local_dir="$ZEN_DIR/$name"
    pre_dir="$PRE_FILTER_DIR/$name"

    log "$name: cloning fresh from $remote"
    git clone "$remote" "$local_dir" 2>&1 | tail -2 | tee -a "$LOG_FILE"

    new_size=$(du -sh "$local_dir/.git" | cut -f1)
    log "$name: fresh clone .git = $new_size"

    # Restore .claude/ from pre-filter backup
    if [ -d "$pre_dir/.claude" ]; then
        cp -r "$pre_dir/.claude" "$local_dir/.claude"
        log "$name: restored .claude/"
    fi
done

echo ""

# ─── Zip pre-filter backups to V: drive ─────────────────────────────────

log "=== Zipping pre-filter backups to $BACKUP_DIR ==="

for entry in "${REPOS[@]}"; do
    IFS='|' read -r name remote filters <<< "$entry"
    pre_dir="$PRE_FILTER_DIR/$name"
    zip_file="$BACKUP_DIR/${name}-pre-filter-$(date +%Y%m%d).zip"

    if [ ! -d "$pre_dir" ]; then
        err "$name: pre-filter dir not found at $pre_dir"
        continue
    fi

    log "$name: zipping $pre_dir → $zip_file ..."
    (cd "$PRE_FILTER_DIR" && zip -rq "$zip_file" "$name/") 2>&1 | tee -a "$LOG_FILE"

    zip_size=$(du -sh "$zip_file" | cut -f1)
    log "$name: zip = $zip_size"
done

echo ""
log "=== Done ==="
log ""
log "Fresh repos cloned into $ZEN_DIR"
log "Pre-filter repos in $PRE_FILTER_DIR"
log "Zip backups in $BACKUP_DIR"
log "Post-filter mirrors in $POST_FILTER_DIR"
log ""
log "After verifying everything works:"
log "  rm -rf $PRE_FILTER_DIR"
log "  rm -rf $POST_FILTER_DIR"
