import { expect, test } from 'bun:test'
import { ObjectId } from 'mongodb'

import { useAgentDb } from '@/lib/test/doubles/agent-db'
import { useDb } from '@/lib/test/doubles/db'

import { assertGithubReviewRequest, githubReviewScope } from './github-review-scope'

import type { SessionRouting } from './session-routing'

const triggerId = new ObjectId()
const scope: NonNullable<SessionRouting['github']> = {
  installationId: 123,
  repositoryId: 456,
  actions: ['opened'],
}
let storedTrigger: unknown = { sessionRouting: { github: scope } }

useAgentDb({
  getConversationBySessionId: () =>
    Promise.resolve({
      teamId: 'team',
      metadata: { trigger: { id: triggerId.toHexString() } },
    }),
})
useDb({
  db: () => ({ collection: () => ({ findOne: () => Promise.resolve(storedTrigger) }) }),
})

test('review scope is derived from the stored trigger, never a caller repository parameter', async () => {
  expect(await githubReviewScope('session', 'team')).toEqual(scope)
  await expect(githubReviewScope('session', 'other-team')).rejects.toThrow('not in this team')
  expect(await githubReviewScope(undefined, 'team')).toBeUndefined()
})

test('removing the trigger cannot restore installation-wide access', async () => {
  storedTrigger = null
  try {
    await expect(githubReviewScope('session', 'team')).rejects.toThrow('no longer available')
  } finally {
    storedTrigger = { sessionRouting: { github: scope } }
  }
})

test('only scoped token issuance and installation metadata are allowed; proxy and mutation bypasses fail', () => {
  const root = '/teams/team/github-installations/123'

  expect(() => assertGithubReviewRequest(scope, 'GET', `${root}/token`)).not.toThrow()
  expect(() => assertGithubReviewRequest(scope, 'GET', root)).not.toThrow()
  for (const path of [
    `${root}/repositories`,
    `${root}/repos/owner/other-repo/pulls`,
    '/teams/team/github-installations/789/token',
  ]) {
    expect(() => assertGithubReviewRequest(scope, 'GET', path)).toThrow('repository-scoped')
  }
  expect(() => assertGithubReviewRequest(scope, 'DELETE', root)).toThrow('repository-scoped')
})
