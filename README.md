# aegis

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**npm supply-chain incident-response CLI.**

`aegis` is a read-only scanner + auditable remediator for known npm supply-chain compromises. Think Windows Defender, but for `node_modules`, caches, and running processes.

Spun out of `@automagik/genie sec` after the April 2026 CanisterWorm / TeamPCP incident demonstrated that supply-chain incident-response deserves its own dedicated tool, independently versioned and signed.

---

## Quick start

```bash
# One-shot scan
npx -y @automagik/aegis scan --all-homes --root "$PWD"

# Interactive incident fix (scan → kill processes → purge caches → reinstall clean → re-scan)
npx -y @automagik/aegis fix

# Verify your installed binary is genuine (cosign keyless + SLSA L3)
npx -y @automagik/aegis verify-install
```

Exit codes:
- `0` — clean and complete
- `1` — findings present
- `2` — clean but incomplete (capped roots, banner at top tells you what was skipped)

---

## Commands

| Command | What it does |
|---|---|
| `aegis scan` | Read-only host sweep. Bounded walks, versioned JSON envelope, `scan_id` ULID, coverage banner. |
| `aegis fix` | One-shot incident remediation wrapper. Interactive by default; `--yes` for CI. |
| `aegis remediate` | Granular pipeline: dry-run produces a plan manifest, `--apply --plan <path>` executes it with per-action typed consent. |
| `aegis restore <id>` | Undo one quarantined action. sha256-verified per file. |
| `aegis rollback <scan-id>` | Bulk undo every quarantined action for a scan. Walks the audit log in reverse. |
| `aegis quarantine list` | Enumerate quarantine dirs with size, status, scan_id. |
| `aegis quarantine gc --older-than 30d` | Garbage-collect restored/abandoned quarantines. Active quarantines refused. |
| `aegis verify-install` | Verify cosign signature + SLSA provenance of the running binary. |

Full flag surface: `aegis <command> --help`.

---

## What it detects today

Bundled signatures cover the **CanisterWorm / TeamPCP (April 2026)** incident:

- Compromised `@automagik/genie` versions `4.260421.33` through `4.260421.40`
- Compromised `pgserve` versions `1.1.11`, `1.1.12`, `1.1.13`
- Compromised `@fairwords/*` and `@openwebconcept/*` entries
- IOC strings: `telemetry.api-monitor.com`, `raw.icp0.io/drop`, ICP canister ID `cjn37-uyaaa-aaaac-qgnva-cai`, `TEL_ENDPOINT`, `ICP_CANISTER_ID`, etc.
- Payload file basenames: `env-compat.cjs`, `env-compat.js`, `public.pem`
- Known-bad sha256 hashes
- Exfil POST endpoints (`/v1/telemetry`, `/v1/drop`) distinguished from bare-domain probes

---

## Detection invariants

- **Read-only scanner.** `aegis scan` never mutates host state.
- **Version-gated matching.** A package flagged only when its installed version is in the compromise list. `pgserve@1.1.10` (clean) does not fire a `pgserve` IOC.
- **Self-skip.** The aegis binary itself never appears in its own findings.
- **Scoring honest.** Shell-history `npm uninstall` lines (remediation) and `genie sec scan` lines (investigation) do not inflate the suspicion score.
- **Coverage-gap banner.** If the scanner hit caps or skipped roots, the banner appears at the top of the report. Exit code `2`.

---

## Remediation invariants

- **Dry-run is default.** `aegis remediate` without `--apply` produces a plan manifest (mode `0600`), mutates nothing.
- **Quarantine, never delete.** Findings move to `~/.genie/sec-scan/quarantine/<ts>/<action_id>/` with a sidecar manifest; `aegis restore` round-trips via sha256.
- **Typed consent.** Per-action confirmation requires typing `CONFIRM-QUARANTINE-<6-hex-of-action-id>`. Keystroke prompts prohibited.
- **Signature verified for `--apply`.** The running binary is cosign-verified before mutations unless `--unsafe-unverified <INCIDENT_ID>` is passed (logged in audit trail).
- **Append-only audit log.** `~/.genie/sec-scan/audit/<scan_id>.jsonl`, mode `0600`, `fsync` per event.
- **Bulk undo.** `aegis rollback <scan-id>` walks the audit log in reverse and restores every action.

---

## Release integrity

Every release of `@automagik/aegis` ships:
- Cosign keyless signature (OIDC via GitHub Actions) → `<artifact>.sig` + `<artifact>.cert`
- SLSA Level 3 provenance attestation → `provenance.intoto.jsonl`
- Public-key fingerprint pinned in three channels: `SECURITY.md`, `/.well-known/security.txt`, and a pinned GitHub issue

Verify:
```bash
npx -y @automagik/aegis verify-install
# or manually
cosign verify-blob --certificate-identity '<identity>' --signature <a>.sig --certificate <a>.cert <artifact>
slsa-verifier verify-artifact <artifact> --provenance-path provenance.intoto.jsonl --source-uri github.com/automagik-dev/aegis
```

---

## Incident response runbook

See [`docs/incident-response/canisterworm.md`](docs/incident-response/canisterworm.md) for the full three-branch decision tree (LIKELY COMPROMISED / LIKELY AFFECTED / OBSERVED ONLY) keyed off scanner status bands. Every referenced command is covered by the cold-runbook test at `scripts/test-runbook.sh` so the playbook doesn't rot.

---

## Signature subscription (Phase 2 — planned)

Today, bundled signatures cover one incident. The next phase ships `@automagik/aegis-signatures` — a separate signed npm package containing YAML files for every known npm supply-chain incident. Operators will run `aegis signatures update` on an hourly cron; new worm definitions arrive in minutes, not days.

See [`docs/signatures/`](docs/signatures/) for the draft design (landing post-brainstorm).

---

## Contributing

Security-critical tool. PRs go through mandatory review by the Namastex security team. See `CONTRIBUTING.md` (TBD) for the bar.

**Responsible disclosure:** `/.well-known/security.txt` + `SECURITY.md` for reporting channels.

---

## License

[MIT](LICENSE) © 2026 Namastex Labs
