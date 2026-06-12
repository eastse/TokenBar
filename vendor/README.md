# Vendored dependencies

| Crate | Source | Vendored from |
|---|---|---|
| `tokscale-core` | [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) (`crates/tokscale-core`, MIT) | [Nanako0129/TokenBar](https://github.com/Nanako0129/TokenBar) `vendor/tokscale-core` @ `606cae1` (v0.4.4: backfill missing cache rates from runner-up pricing source) |

> **Sync rule (historical):** the Tauri repo (`Nanako0129/TokenBar-Tauri`,
> archived 2026-06-12) used to be the single upstream-sync point. With it
> archived, this repo now owns the vendored copy; future syncs come straight
> from junhoyeo/tokscale and must re-apply the local patches below.

## Local patches (diverged from upstream)

| Patch | Files | Status upstream |
|---|---|---|
| PR #2 (perf): `HASH_MEMO` + `STORE_MEMO` process-level memos; `LocalParseOptions.modified_after` mtime pruning; `latest_source_mtime_ms()` change probe | `src/message_cache.rs`, `src/lib.rs` | not yet forwarded to junhoyeo/tokscale |
