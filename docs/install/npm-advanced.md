# Advanced: install via GitHub Packages (`npm install` semantics)

> **Most users should use the installer script.** See [README Install](../../README.md#install). This page covers the advanced path for users who want `package.json` dependency pinning, CI integration, or lockfile reproducibility — and who are OK making a one-line addition to their `.npmrc`.

---

## When to use this path

- CI pipelines where pinning a specific aegis version in `package.json` is useful
- Organizations with an internal policy that all binaries flow through npm-compatible registries
- Users who already have a GitHub PAT set up for other GitHub Packages installs

## When NOT to use this path

- One-shot scans on personal machines — use the installer instead
- Air-gapped hosts — the installer's `--skip-verify` path is simpler
- Users who don't want to deal with PAT management

---

## Setup (~1 minute)

1. **Create a GitHub PAT with `read:packages` scope.**
   - Classic token: https://github.com/settings/tokens (pick `read:packages`)
   - Fine-grained: https://github.com/settings/personal-access-tokens/new — scope to `automagik-dev` with "Packages: Read"

2. **Add to your `.npmrc`.** You can put this either in the project root (preferred — scoped to the project) or in `~/.npmrc` (applies globally).

   ```
   @automagik-dev:registry=https://npm.pkg.github.com
   //npm.pkg.github.com/:_authToken=YOUR_GITHUB_PAT_HERE
   ```

   Important:
   - The `@automagik-dev:registry=...` line is **scoped** — it only routes `@automagik-dev/*` packages to GitHub Packages. **Your other `npm install` calls are unaffected.**
   - The `//npm.pkg.github.com/:_authToken=...` line applies only when that host is contacted (same scope limit).
   - `chmod 600 ~/.npmrc` if you stored the token there — it's a secret.

3. **Install:**
   ```bash
   npm install --save-dev @automagik-dev/aegis
   # or:
   npx @automagik-dev/aegis scan --all-homes --root "$PWD"
   ```

## Does this affect my other `npm install` calls?

**No.** The `@automagik-dev:registry=...` line is scope-specific — npm only routes packages whose name starts with `@automagik-dev/` to GitHub Packages. Every other package (unscoped, different scope) continues to resolve from `registry.npmjs.org` (the default).

The auth token line (`//npm.pkg.github.com/:_authToken=...`) is host-scoped — it's only sent when npm talks to `npm.pkg.github.com`, which only happens for `@automagik-dev` packages under the rule above.

## CI example (GitHub Actions)

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: '22'
    registry-url: 'https://npm.pkg.github.com'
    scope: '@automagik-dev'
- run: npm install --save-dev @automagik-dev/aegis
  env:
    NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
- run: npx aegis scan --all-homes --root "$PWD"
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `npm ERR! 401 Unauthorized` | PAT missing, expired, or lacks `read:packages` scope |
| `npm ERR! 404 Not Found` | Scope line missing from `.npmrc` (npm tried npmjs.com instead) |
| PAT works locally but not in CI | CI is using a different identity — set `NODE_AUTH_TOKEN` to a workflow-scoped token |

## Why GitHub Packages at all?

See the main README's "Why GitHub Releases + installer, not npmjs.com" section. Short version: `aegis` ships its tarball to GitHub Packages as a **secondary** path (the primary is the installer script) so that power users and CI systems can pin versions via `package.json` without losing the triple-attested release chain.
