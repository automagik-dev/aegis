# Reserved Signature-Pack IDs

This document lists the reserved ID prefixes for canonical Namastex-authored signature packs. Community packs MUST use a distinct namespace.

## Reserved prefixes (cannot be used by community packs)

| Prefix | Family | Example |
|---|---|---|
| `canisterworm-*` | CanisterWorm / TeamPCP npm-worm family | `canisterworm-2026-04` |
| `teampcp-*` | TeamPCP-named variants | `teampcp-2026-05` |
| `shai-hulud-*` | Shai-Hulud worm family | `shai-hulud-2025-11` |

Any pack with an ID matching a reserved prefix that is NOT signed by the pinned Namastex cosign identity will be refused by the loader.

## Community packs MUST use

- `community-<handle>-<description>-<YYYY>-<MM>`
- `org-<org-name>-<description>-<YYYY>-<MM>`
- Any prefix that does not collide with the reserved list.

This file is updated by Namastex security team when new incident families are named.
