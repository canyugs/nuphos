/* eslint-disable sonarjs/no-os-command-from-path -- Runs real git and the setup script against fixture-owned CLI shims. */
import { execFileSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { expect, test } from 'bun:test'

const setup = join(import.meta.dir, 'skills/github/scripts/setup-credentials.sh')

test('current actor authors and self-hosted App committers stay repository-local', () => {
  const root = mkdtempSync(join(tmpdir(), 'github-identity-'))
  const bin = join(root, 'bin')
  const repo = join(root, 'repo')
  const other = join(root, 'other')
  const globalConfig = join(root, 'gitconfig')
  const env = {
    PATH: `${bin}:${process.env.PATH ?? ''}`,
    HOME: root,
    GH_CONFIG_DIR: join(root, 'gh'),
    GIT_CONFIG_GLOBAL: globalConfig,
    GIT_CONFIG_NOSYSTEM: '1',
    NUPHOS_TOKEN: 'fixture',
    NUPHOS_BACKEND_URL: 'https://fixture.invalid',
    TEST_APP_SLUG: 'customer-automation',
    TEST_BOT_TYPE: 'Bot',
    TEST_AUTHOR_NAME: 'Current Teammate',
    TEST_AUTHOR_EMAIL: 'teammate@example.invalid',
  }
  const git = (cwd: string, ...args: string[]) =>
    execFileSync('git', ['-C', cwd, ...args], { env, encoding: 'utf8', stdio: 'pipe' }).trim()
  const run = () =>
    execFileSync('bash', [setup, '0123456789abcdef01234567', '123', repo], {
      env,
      stdio: 'pipe',
    })

  try {
    mkdirSync(bin)
    mkdirSync(repo)
    mkdirSync(other)
    writeFileSync(globalConfig, '[user]\n\tname = Human\n\temail = human@example.invalid\n')
    const original = readFileSync(globalConfig, 'utf8')

    writeFileSync(
      join(bin, 'curl'),
      `#!/usr/bin/env python3
import json, os
print(json.dumps(dict(token='fixture', accountLogin='different-org', appSlug=os.environ['TEST_APP_SLUG'], commitAuthor=dict(name=os.environ['TEST_AUTHOR_NAME'], email=os.environ['TEST_AUTHOR_EMAIL']))))
`,
      { mode: 0o755 },
    )
    writeFileSync(
      join(bin, 'gh'),
      `#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:] == ['auth', 'setup-git', '--hostname', 'github.com']:
    pass
elif sys.argv[1:] == ['api', '--hostname', 'github.com', 'users/' + os.environ['TEST_APP_SLUG'] + '[bot]']:
    print(json.dumps(dict(login=os.environ['TEST_APP_SLUG'] + '[bot]', id=7654321, type=os.environ['TEST_BOT_TYPE'])))
else:
    raise AssertionError(sys.argv)
`,
      { mode: 0o755 },
    )
    git(repo, 'init')
    git(other, 'init')
    run()
    git(repo, 'commit', '--allow-empty', '-m', 'identity test')
    expect(git(repo, 'log', '-1', '--format=%an <%ae>|%cn <%ce>')).toBe(
      'Current Teammate <teammate@example.invalid>|customer-automation[bot] <7654321+customer-automation[bot]@users.noreply.github.com>',
    )
    expect(git(other, 'config', 'user.email')).toBe('human@example.invalid')
    expect(readFileSync(globalConfig, 'utf8')).toBe(original)

    env.TEST_APP_SLUG = 'second-app'
    env.TEST_AUTHOR_NAME = 'Next Teammate'
    env.TEST_AUTHOR_EMAIL = 'next@example.invalid'
    run()
    expect(git(repo, 'config', '--local', 'committer.email')).toBe(
      '7654321+second-app[bot]@users.noreply.github.com',
    )
    expect(git(repo, 'var', 'GIT_AUTHOR_IDENT')).toStartWith('Next Teammate <next@example.invalid>')
    const beforeFailure = readFileSync(join(repo, '.git/config'), 'utf8')

    env.TEST_BOT_TYPE = 'User'
    expect(run).toThrow()
    expect(readFileSync(join(repo, '.git/config'), 'utf8')).toBe(beforeFailure)
    env.TEST_BOT_TYPE = 'Bot'
    env.TEST_AUTHOR_EMAIL = ''
    expect(run).toThrow()
    expect(readFileSync(join(repo, '.git/config'), 'utf8')).toBe(beforeFailure)
    env.TEST_AUTHOR_EMAIL = 'next@example.invalid\nInjected'
    expect(run).toThrow()
    expect(readFileSync(join(repo, '.git/config'), 'utf8')).toBe(beforeFailure)
    env.TEST_AUTHOR_EMAIL = 'next@example.invalid'
    env.TEST_APP_SLUG = ''
    expect(run).toThrow()
    expect(readFileSync(join(repo, '.git/config'), 'utf8')).toBe(beforeFailure)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
})
