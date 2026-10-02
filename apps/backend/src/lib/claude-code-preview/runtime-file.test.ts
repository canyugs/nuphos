import { beforeEach, expect, mock, test } from 'bun:test'

let conversation: Record<string, unknown> | null
let calls = 0
const endpoint = { runtimeId: 'r', url: 'wss://agent.test/acp', authKey: 'fixture' }

await mock.module('@/lib/agent/db', () => ({ getReadableConversation: async () => conversation }))
await mock.module('./runtime-catalog', () => ({
  requireRuntimeInstance: async () => ({
    id: 'r',
    provider: 'codex',
    status: 'active',
    kind: 'external',
  }),
  developmentRuntimeEndpoint: () => undefined,
}))
await mock.module('./runtime-registry', () => ({
  resolveTeamRuntimeEndpoints: async () => [endpoint],
}))
await mock.module('./agent-chat-registry', () => ({
  controlRegistry: {
    acquire: async () => ({
      runJob: async (request: { stdin: string }) => {
        calls++
        expect(JSON.parse(request.stdin).params).toEqual({ sessionId: 's', path: 'report.md' })

        return { stdout: JSON.stringify({ name: 'report.md', data: 'aGk=', size: 2 }) }
      },
    }),
    runtimeJobs: () => ['panel'],
  },
}))
const { readRuntimeFile, parseRuntimeFile } = await import('./runtime-file')

beforeEach(() => {
  calls = 0
  conversation = { sessionId: 's', userId: 'owner', teamId: 'team', runtimeId: 'r' }
})

test('reads the requested source through its panel job', async () => {
  expect(await readRuntimeFile('team', 'owner', 'r', 's', 'report.md')).toEqual({
    name: 'report.md',
    data: 'aGk=',
    size: 2,
  })
  expect(calls).toBe(1)
})

test('rejects another viewer, team and unrelated runtime before reading', async () => {
  for (const value of [
    null,
    { userId: 'someone', teamId: 'team', runtimeId: 'r' },
    { userId: 'owner', teamId: 'other', runtimeId: 'r' },
    { userId: 'owner', teamId: 'team', runtimeId: 'other' },
  ]) {
    conversation = value
    await expect(readRuntimeFile('team', 'owner', 'r', 's', 'report.md')).rejects.toThrow()
  }
  expect(calls).toBe(0)
})

test('a moved conversation reads the original runtime without redirecting', async () => {
  conversation = {
    userId: 'owner',
    teamId: 'team',
    runtimeId: 'new',
    previousRuntimeUrls: [endpoint.url],
  }
  expect((await readRuntimeFile('team', 'owner', 'r', 's', 'report.md')).name).toBe('report.md')
})

test('maps file errors and rejects malformed runtime responses', () => {
  expect(() => parseRuntimeFile('{"error":"file_not_found"}')).toThrow('no longer exists')
  expect(() => parseRuntimeFile('{"error":"file_too_large"}')).toThrow('512 KiB')
  for (const value of ['garbage', 'null', '{}', '{"name":"x","size":99,"data":"aGk="}'])
    expect(() => parseRuntimeFile(value)).toThrow()
})
