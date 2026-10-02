import { describe, expect, test } from 'bun:test'

import {
  matchesGithubRoute,
  resolveSessionKey,
  routedSessionId,
  sessionRoutingSchema,
} from './session-routing'

const template = 'github-pr:{{payload.repository.id}}:{{payload.pull_request.number}}'
const payload = {
  installation: { id: 1 },
  repository: { id: 2 },
  pull_request: { number: 3, labels: [{ name: 'review' }] },
  action: 'synchronize',
}

describe('session routing', () => {
  test('same PR keeps its identity across commits, different scopes stay separate', () => {
    const key = resolveSessionKey(template, payload)
    const session = routedSessionId('team', 'trigger', key)

    expect(
      routedSessionId('team', 'trigger', resolveSessionKey(template, { ...payload, sha: 'new' })),
    ).toBe(session)
    expect(routedSessionId('other-team', 'trigger', key)).not.toBe(session)
    expect(routedSessionId('team', 'other-trigger', key)).not.toBe(session)
    expect(
      routedSessionId(
        'team',
        'trigger',
        resolveSessionKey(template, { ...payload, pull_request: { number: 4 } }),
      ),
    ).not.toBe(session)
  })
  test('missing, compound and inherited properties fail closed', () => {
    for (const data of [{}, { repository: { id: {} } }, Object.create(payload)]) {
      expect(() => resolveSessionKey(template, data)).toThrow()
    }
    expect(() => resolveSessionKey('{{payload.foo}', {})).toThrow()
  })
  test('encoding prevents delimiter collisions', () => {
    expect(resolveSessionKey('{{payload.a}}:{{payload.b}}', { a: 'a:b', b: 'c' })).not.toBe(
      resolveSessionKey('{{payload.a}}:{{payload.b}}', { a: 'a', b: 'b:c' }),
    )
  })
  test('GitHub filters require installation, repository, PR, action and optional label', () => {
    const route = sessionRoutingSchema.parse({
      keyTemplate: template,
      github: { installationId: 1, repositoryId: 2, actions: ['synchronize'], label: 'review' },
    })

    expect(matchesGithubRoute(route, 'pull_request', payload)).toBe(true)
    for (const data of [
      null,
      {},
      { ...payload, installation: { id: 9 } },
      { ...payload, repository: { id: 9 } },
      { ...payload, action: 'closed' },
      { ...payload, pull_request: { number: 3, labels: [] } },
    ]) {
      expect(matchesGithubRoute(route, 'pull_request', data)).toBe(false)
    }
    expect(matchesGithubRoute(route, 'push', payload)).toBe(false)
  })
})
