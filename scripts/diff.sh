#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# diff.sh — Compare two versions of the theme
#
# Usage:
#   ./scripts/diff.sh <ref1> <ref2>           # Diff between two refs
#   ./scripts/diff.sh HEAD~1 HEAD             # Last change
#   ./scripts/diff.sh v1-push v3-push         # Between two tags
#   ./scripts/diff.sh v2-push HEAD --stat     # Summary only
#   ./scripts/diff.sh --staged                # Uncommitted changes
#
# Refs can be: tags (v1-push), HEAD, HEAD~N, commit hashes
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR=".shopify-dev/theme"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_header() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"; }
print_err()    { echo -e "${RED}✗${NC} $1"; }
print_info()   { echo -e "  $1"; }

# --- Usage ---
usage() {
    echo "Usage: $0 <ref1> <ref2> [--stat]"
    echo "       $0 --staged"
    echo ""
    echo "  ref1, ref2    Git references (tags, HEAD, HEAD~N, commit hashes)"
    echo "  --stat        Show summary stats only (no full diff)"
    echo "  --staged      Show uncommitted changes"
    echo ""
    echo "Examples:"
    echo "  $0 HEAD~1 HEAD                  # Last change"
    echo "  $0 v1-push v3-push              # Between tagged versions"
    echo "  $0 v0-init HEAD --stat          # All changes since init (summary)"
    exit 1
}

# --- Main ---
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    if [[ ! -d "${THEME_DIR}/.git" ]]; then
        print_err "No Git repo found at ${THEME_DIR}. Run init-store.sh first."
        exit 1
    fi

    local ref1=""
    local ref2=""
    local stat_only=false
    local staged=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stat|-s)
                stat_only=true
                shift
                ;;
            --staged)
                staged=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [[ -z "$ref1" ]]; then
                    ref1="$1"
                elif [[ -z "$ref2" ]]; then
                    ref2="$1"
                else
                    print_err "Too many arguments."
                    usage
                fi
                shift
                ;;
        esac
    done

    # --- Staged changes ---
    if [[ "$staged" == true ]]; then
        print_header "Uncommitted Changes"

        (
            cd "${THEME_DIR}"
            git add -A --dry-run 2>/dev/null | head -50

            local changes
            changes=$(git status --short 2>/dev/null)
            if [[ -z "$changes" ]]; then
                echo "  No uncommitted changes."
                exit 0
            fi

            echo ""
            echo -e "${BOLD}Changed files:${NC}"
            echo "$changes" | while read -r status file; do
                case "$status" in
                    M)  echo -e "  ${YELLOW}modified:${NC}  $file" ;;
                    A)  echo -e "  ${GREEN}added:${NC}     $file" ;;
                    D)  echo -e "  ${RED}deleted:${NC}   $file" ;;
                    *)  echo -e "  ${status}:  $file" ;;
                esac
            done

            echo ""
            git diff --stat 2>/dev/null || true
        )
        exit 0
    fi

    # --- Ref-based diff ---
    if [[ -z "$ref1" || -z "$ref2" ]]; then
        print_err "Two refs required for comparison."
        usage
    fi

    # Validate refs
    (cd "${THEME_DIR}" && git rev-parse "$ref1" &>/dev/null) || {
        print_err "Invalid ref: ${ref1}"
        echo "  Available tags:"
        (cd "${THEME_DIR}" && git tag --list --sort=-creatordate | head -10 | sed 's/^/    /')
        exit 1
    }

    (cd "${THEME_DIR}" && git rev-parse "$ref2" &>/dev/null) || {
        print_err "Invalid ref: ${ref2}"
        echo "  Available tags:"
        (cd "${THEME_DIR}" && git tag --list --sort=-creatordate | head -10 | sed 's/^/    /')
        exit 1
    }

    print_header "Diff: ${ref1} → ${ref2}"

    # Show summary stats
    echo -e "${BOLD}Summary:${NC}"
    (
        cd "${THEME_DIR}"

        local stat_output
        stat_output=$(git diff --stat "$ref1" "$ref2" 2>/dev/null)

        if [[ -z "$stat_output" ]]; then
            echo "  No differences found."
            exit 0
        fi

        echo "$stat_output"
        echo ""

        # File-level summary
        local added modified deleted
        added=$(git diff --name-status "$ref1" "$ref2" | grep -c '^A' || true)
        modified=$(git diff --name-status "$ref1" "$ref2" | grep -c '^M' || true)
        deleted=$(git diff --name-status "$ref1" "$ref2" | grep -c '^D' || true)

        echo -e "${GREEN}+${added} added${NC}  ${YELLOW}~${modified} modified${NC}  ${RED}-${deleted} deleted${NC}"
    )

    # Full diff (unless --stat)
    if [[ "$stat_only" != true ]]; then
        echo ""
        echo -e "${BOLD}Full diff:${NC}"
        echo "────────────────────────────────────────"
        (cd "${THEME_DIR}" && git diff --color "$ref1" "$ref2") || true
    fi
}

main "$@"
