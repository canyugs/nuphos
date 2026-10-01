# Contributing to Nuphos

## Before you write code

For anything beyond a small fix, open an issue first. A session here spans
several people, several machines and whatever accounts the team has connected,
so a change that looks local often is not — credential handling, team scoping
and agent permissions all have blast radius past the file you are editing.

If you are fixing something that is clearly broken, just send the pull request.

## Getting it running

`bun run dev` at the repository root. Prerequisites and the full local-stack
walkthrough are in the [README](README.md#local-development).

If you want the whole thing rather than a dev loop, `deploy/compose` brings it
up with one `docker compose up` — see
[`deploy/compose/README.md`](deploy/compose/README.md).

## What CI checks

Every pull request runs typecheck, tests, lint, format and an import-cycle
check, scoped to the apps your change touches. Run them locally first:

```sh
cd apps/backend && bun run typecheck && bun test        # backend
cd apps/desktop && pnpm typecheck && pnpm test          # desktop
bun run check:cycles                                     # import cycles
```

Formatting is Prettier, configured once at the repository root. Lint is per-app,
because each app has a different package manager and framework preset.

Two lint rules surprise people, so they are worth stating up front:

- **Comment blocks are capped at three consecutive lines.** The rule's own
  message explains why: a long comment usually means the code below should be
  clearer, and decision history belongs in the pull request.
- **No nested ternaries, and complexity ceilings per function.** Both fire as
  warnings, not errors, but a reviewer will usually ask.

## What we look for in a pull request

Say what the change does and why the problem exists, not just what you edited.
If there was a choice between adding something and removing something, say why
the subtraction did not work — that question comes up in review every time.

Tests for behaviour, not for coverage. A test that would have caught the bug is
worth more than three that restate the implementation.

Pull requests get an automated review in addition to a human one. It will
sometimes be wrong; say so and explain why rather than changing code you believe
is correct.

## Commit messages

Imperative subject, under about 72 characters, optionally prefixed with a scope
(`fix(desktop):`). The body is for _why_. We squash on merge, so the pull
request title and description end up as the permanent record — write them for
whoever is bisecting this in a year.

## Security

Do not open a pull request for a vulnerability. See [SECURITY.md](SECURITY.md) —
it goes through GitHub's private vulnerability reporting so the fix can land
before the details are public.

## Licence and naming

Contributions are under Apache-2.0, the same as the rest of the repository. The
Nuphos name and logo are trademarks and are handled separately — see
[TRADEMARK.md](TRADEMARK.md). In short: fork freely, rename if you ship it as
your own product.
