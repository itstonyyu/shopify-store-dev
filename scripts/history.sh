#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# history.sh — List all tagged versions with timestamps and messages
#
# Usage:
#   ./scripts/history.sh              # Show last 20 versions
#   ./scripts/history.sh -n 10        # Show last 10 versions
#   ./scripts/history.sh --all        # Show all versions
#   ./scripts/history.sh --verbose    # Include commit details
# ============================================================================

THEME_DIR=".shopify-dev/theme"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"; }
print_err()    { echo -e "${RED}✗${NC} $1"; }

# --- Usage ---
usage() {
    echo "Usage: $0 [-n <count>] [--all] [--verbose]"
    echo ""
    echo "  -n <count>   Number of versions to show (default: 20)"
    echo "  --all        Show all versions"
    echo "  --verbose    Include commit hash and author"
    exit 1
}

# --- Main ---
main() {
    local count=20
    local show_all=false
    local verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n)
                count="$2"
                shift 2
                ;;
            --all|-a)
                show_all=true
                shift
                ;;
            --verbose|-v)
                verbose=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_err "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [[ ! -d "${THEME_DIR}/.git" ]]; then
        print_err "No Git repo found at ${THEME_DIR}. Run init-store.sh first."
        exit 1
    fi

    print_header "Theme Change History"

    (
        cd "${THEME_DIR}"

        local total_tags
        total_tags=$(git tag --list | wc -l | tr -d ' ')

        if [[ "$total_tags" -eq 0 ]]; then
            echo "  No tagged versions found."
            echo ""
            echo "  Tags are created automatically by safe-push.sh and rollback.sh."
            exit 0
        fi

        if [[ "$show_all" == true ]]; then
            count="$total_tags"
        fi

        echo -e "  Showing ${count} of ${total_tags} tagged versions (newest first)\n"

        if [[ "$verbose" == true ]]; then
            # Verbose: tag, date, commit hash, message
            echo -e "${BOLD}  Tag                          Date                 Commit    Message${NC}"
            echo "  ─────────────────────────────────────────────────────────────────────────"

            git tag --list --sort=-creatordate \
                --format='%(refname:short)|%(creatordate:iso8601)|%(objectname:short)|%(subject)' | \
                head -"$count" | while IFS='|' read -r tag date hash msg; do

                # Color-code by tag type
                local color="$NC"
                case "$tag" in
                    v*-push)        color="$GREEN" ;;
                    *-rollback*)    color="$RED" ;;
                    promote-*)      color="$YELLOW" ;;
                    pre-promote-*)  color="$CYAN" ;;
                    v0-init)        color="$BLUE" ;;
                esac

                printf "  ${color}%-28s${NC} %-20s %-9s %s\n" "$tag" "$date" "$hash" "$msg"
            done
        else
            # Compact: tag, date, message
            echo -e "${BOLD}  Tag                          Date                 Message${NC}"
            echo "  ─────────────────────────────────────────────────────────────────"

            git tag --list --sort=-creatordate \
                --format='%(refname:short)|%(creatordate:iso8601)|%(subject)' | \
                head -"$count" | while IFS='|' read -r tag date msg; do

                local color="$NC"
                case "$tag" in
                    v*-push)        color="$GREEN" ;;
                    *-rollback*)    color="$RED" ;;
                    promote-*)      color="$YELLOW" ;;
                    pre-promote-*)  color="$CYAN" ;;
                    v0-init)        color="$BLUE" ;;
                esac

                printf "  ${color}%-28s${NC} %-20s %s\n" "$tag" "$date" "$msg"
            done
        fi

        echo ""
        echo -e "  Legend: ${GREEN}push${NC}  ${RED}rollback${NC}  ${YELLOW}promote${NC}  ${CYAN}pre-promote${NC}  ${BLUE}init${NC}"
        echo ""
        echo "  To compare versions: ./scripts/diff.sh <tag1> <tag2>"
        echo "  To rollback:         ./scripts/rollback.sh --to <tag>"
    )
}

main "$@"
