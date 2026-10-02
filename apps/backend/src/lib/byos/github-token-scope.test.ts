import { expect, test } from 'bun:test'

import { useGithubAppAuth } from '@/lib/test/doubles/github-app-auth'
import { useGithubHttp } from '@/lib/test/doubles/github-http'

import { getInstallationToken } from './github'

const bodies: unknown[] = []

useGithubAppAuth({ generateAppJwt: () => 'unit-test-jwt' })
useGithubHttp({
  githubFetch: (_url, init) => {
    bodies.push(typeof init.body === 'string' ? JSON.parse(init.body) : null)

    return Promise.resolve(
      Response.json({ token: 'unit-test-token', expires_at: '2099-01-01T00:00:00Z' }),
    )
  },
})

test('repository token requests cannot reuse an installation-wide cached token', async () => {
  bodies.length = 0
  await getInstallationToken(987654)
  await getInstallationToken(987654, 456)
  await getInstallationToken(987654, 789)
  expect(bodies).toEqual([
    null,
    {
      repository_ids: [456],
      permissions: { contents: 'read', pull_requests: 'write', metadata: 'read' },
    },
    {
      repository_ids: [789],
      permissions: { contents: 'read', pull_requests: 'write', metadata: 'read' },
    },
  ])
})
