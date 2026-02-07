# Safety Rules — Hard Lessons from Real Incidents

## Rule #1: NEVER Trust Theme Names

**The Incident:** We had a theme named "DEV-Kayl" — sounds like a dev theme, right?
It was actually the **live theme**. We pushed changes to it thinking it was safe.
The store broke. Customers saw a broken homepage.

**The Fix:** ALWAYS check the `role` field from the API response.

```json
{
  "theme": {
    "id": 123456,
    "name": "DEV-Kayl",     ← Name says "DEV" — LIES
    "role": "main"           ← Role says "main" — THIS IS LIVE
  }
}
```

- `"role": "main"` = **LIVE THEME** (what customers see)
- `"role": "unpublished"` = safe dev/staging theme
- `"role": "demo"` = demo theme

**Never, ever use theme name to determine if it's live.** Only the `role` field matters.

## Rule #2: ALWAYS Snapshot Before Changes

Every operation that modifies theme files must:
1. Download the current state of affected files
2. Commit that state to Git
3. Only then make changes

This gives you a guaranteed rollback point. The `safe-push.sh` script does this
automatically, but if you're making manual API calls, snapshot first.

## Rule #3: Dev-Only by Default

All scripts default to operating on the **dev theme only**. The live theme is
protected by `theme-guard.sh`, which blocks operations unless you explicitly
use the `--promote` flag.

This is a deliberate friction point. Making it slightly harder to modify the
live theme prevents accidental damage.

## Rule #4: Verify Before Promote

Before promoting dev → live:
1. Preview the dev theme at the preview URL
2. Check on mobile and desktop
3. Run `diff.sh` to review all changes
4. Have someone else look at it if possible

The `promote.sh` script requires you to type "PROMOTE" to confirm. This is
intentional. If you're automating with `--yes`, you accept full responsibility.

## Rule #5: Keep Your Token Secret

The Admin API access token has write access to your store's themes. If it leaks:
- Anyone can modify your live theme
- Anyone can download your theme code
- Anyone can break your store

**Security checklist:**
- ✅ `.shopify-dev/config.json` is gitignored by default
- ✅ Never commit tokens to any repository
- ✅ Rotate tokens if you suspect a leak (Settings → Apps → Develop apps)
- ✅ Use minimal scopes (read_themes + write_themes only)

## Rule #6: Respect Rate Limits

Shopify REST Admin API: **2 requests per second** (bucket-based with leaky bucket).

If you exceed this, you'll get `429 Too Many Requests`. All scripts include
`rate_limit` calls (0.55s delay) to stay safely under the limit.

For large operations (full theme download/upload), expect:
- 50 files ≈ 30 seconds
- 100 files ≈ 60 seconds
- Full theme (200+ files) ≈ 2-3 minutes

## Rule #7: Git Is Your Safety Net

The entire system relies on Git for rollback. Never:
- Delete the `.shopify-dev/theme/.git` directory
- Force-push or rebase the Git history
- Remove tags (they're your restore points)

If Git history is lost, you lose the ability to rollback. The files on Shopify
are still there, but you lose your local version history.

## Summary: The 3 Absolute Rules

1. **Check the role, not the name** — `"main"` = live
2. **Snapshot before any change** — no exceptions
3. **Dev only by default** — promote is a deliberate, confirmed action
