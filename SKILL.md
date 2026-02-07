---
name: shopify-store-dev
description: >
  Shopify store development with safety rails. Use this skill when working on
  Shopify themes, Liquid templates, theme assets, CSS/JS on any Shopify store.
  Covers: theme development, theme deployment, theme rollback, theme promotion,
  Shopify Admin API, Liquid editing, asset management, Git-backed version control,
  dev/live theme safety, preview URLs, theme snapshots, safe push, safe deploy.
  This skill connects to live Shopify stores via Admin API (no Shopify CLI needed)
  and provides Git-backed rollback protection so you never break a live store.
---

# Shopify Store Dev Skill

Safe, Git-backed Shopify theme development for AI agents. Connects to live stores
via Admin API with automatic rollback protection.

## Quick Start

1. **Create a Custom App** in Shopify Admin → Settings → Apps → Develop apps
   (see `references/setup-guide.md` for step-by-step)
2. **Run init:** `./scripts/init-store.sh <store-name> <access-token>`
3. **Start developing:** Edit files locally, push with `./scripts/safe-push.sh`

## Workflow Decision Tree

```
What do you need to do?
│
├─ First time setup?
│  └─ Run: scripts/init-store.sh <store> <token>
│
├─ Push changes to dev theme?
│  └─ Run: scripts/safe-push.sh <file1> [file2...]
│     (auto-snapshots before & after, outputs preview URL)
│
├─ Something broke? Need to undo?
│  └─ Run: scripts/rollback.sh [--list | --to <tag>]
│     (shows versions, restores any previous state)
│
├─ Ready to go live?
│  └─ Run: scripts/promote.sh
│     (snapshots live first, copies dev→live, gives rollback cmd)
│
├─ Compare versions?
│  └─ Run: scripts/diff.sh <ref1> <ref2>
│
├─ View change history?
│  └─ Run: scripts/history.sh
│
└─ Check if a theme is safe to modify?
   └─ Run: scripts/theme-guard.sh <theme-id>
```

## ⚠️ Safety Rules (CRITICAL)

1. **NEVER trust theme names.** A theme named "DEV-Kayl" can be the live theme.
   Always check the `role` field via API — `"main"` = live.
2. **ALWAYS snapshot before changes.** Every push auto-commits current state to Git.
3. **Dev-only by default.** Scripts refuse to modify the live theme unless you
   explicitly run `promote.sh` with confirmation.
4. **Real incident:** We pushed to a theme named "DEV-Kayl" that was actually live.
   It broke the store. This skill exists because of that mistake.

## Scripts Reference

| Script | Purpose | Key Flags |
|--------|---------|-----------|
| `init-store.sh` | One-time store setup | `<store> <token>` |
| `theme-guard.sh` | Safety check (is it live?) | `<theme-id> [--promote]` |
| `safe-push.sh` | Git-backed push to dev | `<file1> [file2...] [-m "msg"]` |
| `rollback.sh` | Restore previous version | `--list` or `--to <tag>` |
| `promote.sh` | Dev → Live promotion | `[--yes]` to skip confirm |
| `diff.sh` | Compare two versions | `<ref1> <ref2>` |
| `history.sh` | List all tagged versions | `[-n <count>]` |

## DO / DON'T

### DO
- ✅ Always use `safe-push.sh` instead of raw API calls
- ✅ Run `theme-guard.sh` before any manual API operations
- ✅ Review `diff.sh` output before promoting to live
- ✅ Keep your access token secret (never commit it)
- ✅ Use preview URLs to verify changes before promoting

### DON'T
- ❌ Never push directly to the live theme
- ❌ Never trust theme names — always verify by role/ID
- ❌ Never skip the snapshot step
- ❌ Never store access tokens in Git
- ❌ Never use Shopify CLI when these scripts are available (keeps deps minimal)

## Dependencies

- `curl` — HTTP requests to Shopify Admin API
- `git` — Version control and rollback
- `jq` — JSON parsing

No Shopify CLI required. Works on macOS and Linux.

## Config File

After `init-store.sh`, config lives at `.shopify-dev/config.json`:
```json
{
  "store": "your-store",
  "api_version": "2024-01",
  "live_theme_id": "123456",
  "dev_theme_id": "789012",
  "created_at": "2024-01-15T10:30:00Z"
}
```

## References

- `references/safety-rules.md` — Hard lessons from real incidents
- `references/setup-guide.md` — Non-technical guide for store owners
- `references/api-patterns.md` — Shopify Admin API reference patterns

## API Authentication

All scripts use `X-Shopify-Access-Token` header. Token is stored in
`.shopify-dev/config.json` (gitignored). Base URL pattern:
```
https://{store}.myshopify.com/admin/api/2024-01/
```

## Preview URLs

After pushing to dev theme:
```
https://{store}.myshopify.com/?preview_theme_id={dev_theme_id}
```
