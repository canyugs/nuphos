/** Opt-in, isolated process E2E. Requires MONGOD, REDIS_SERVER, OPENAB on PATH or env. */
import assert from 'node:assert/strict'
import { createHash, createHmac } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

import { Queue } from 'bullmq'
import { MongoClient, ObjectId } from 'mongodb'

import { directory, children, port, until, spawn, stop } from './processes'

const team = new ObjectId()
const user = new ObjectId()
const trigger = new ObjectId()
const installationId = 12345
const repositoryId = 67890
const secret = 'local-e2e-webhook-secret'
const authKey = 'local-e2e-openab-transport-key-123456789'
const controlKey = 'local-e2e-openab-control-key-123456789'
const acpLog = join(directory, 'acp.jsonl')
let mongo: MongoClient | undefined
let queue: Queue | undefined
const mongoPort = await port()
const redisPort = await port()
const sentinelPort = await port()
const runtimePort = await port()
const backendPort = await port()
const redis = process.env.REDIS_SERVER ?? 'redis-server'
const mongoUri = `mongodb://127.0.0.1:${mongoPort}/routing_e2e`
const backendEnv = {
  NODE_ENV: 'development',
  NUPHOS_LOCAL_STACK: 'true',
  MONGODB_URI: mongoUri,
  MONGODB_DB: 'routing_e2e',
  PORT: String(backendPort),
  NUPHOS_JWT_SECRET: 'local-e2e-jwt-secret-not-a-production-credential',
  GITHUB_APP_WEBHOOK_SECRET: secret,
  ATLAS_REDIS_ENABLED: 'true',
  ATLAS_REDIS_SENTINELS: `127.0.0.1:${sentinelPort}`,
  CLAUDE_CODE_RUNTIME_DEV_URL: `ws://127.0.0.1:${runtimePort}/acp`,
  CLAUDE_CODE_RUNTIME_DEV_AUTH_KEY: authKey,
  NUPHOS_CLAUDE_CONTROL_KEY: controlKey,
}
const startBackend = (name: string) =>
  spawn(name, [process.execPath, 'run', join(import.meta.dir, 'backend.ts')], backendEnv)
const healthy = () =>
  until('backend ready', async () => (await fetch(`http://127.0.0.1:${backendPort}/health`)).ok)
const payload = (number = 1, repo = repositoryId) => ({
  action: 'synchronize',
  installation: { id: installationId },
  repository: { id: repo },
  pull_request: { number },
  number,
})

async function deliver(id: string, body = payload(), valid = true) {
  const raw = JSON.stringify(body)

  return fetch(`http://127.0.0.1:${backendPort}/github-app/webhook`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-github-event': 'pull_request',
      'x-github-delivery': id,
      // eslint-disable-next-line sonarjs/hardcoded-secret-signatures -- generated HMAC for synthetic local fixture
      'x-hub-signature-256': `sha256=${createHmac('sha256', secret)
        .update(valid ? raw : 'tampered')
        .digest('hex')}`,
    },
    body: raw,
  })
}
const jobId = (id: string) =>
  createHash('sha256')
    .update(JSON.stringify([trigger.toHexString(), id]))
    .digest('hex')

async function complete(id: string) {
  await until(`delivery ${id} completed`, async () => {
    const job = await queue!.getJob(jobId(id))
    const state = await job?.getState()

    if (state === 'failed') throw new Error(job?.failedReason)

    return state === 'completed'
  })
}
try {
  console.log(`Artifacts: ${directory}`)
  await mkdir(join(directory, 'mongo'))
  spawn('mongo', [
    process.env.MONGOD ?? 'mongod',
    '--bind_ip',
    '127.0.0.1',
    '--port',
    String(mongoPort),
    '--dbpath',
    join(directory, 'mongo'),
    '--wiredTigerCacheSizeGB',
    '0.25',
  ])
  spawn('redis', [
    redis,
    '--bind',
    '127.0.0.1',
    '--port',
    String(redisPort),
    '--dir',
    directory,
    '--appendonly',
    'yes',
    '--appendfsync',
    'always',
    '--maxmemory',
    '128mb',
    '--maxmemory-policy',
    'noeviction',
  ])
  await writeFile(
    join(directory, 'sentinel.conf'),
    `port ${sentinelPort}\nbind 127.0.0.1\ndir ${directory}\nsentinel monitor mymaster 127.0.0.1 ${redisPort} 1\n`,
  )
  spawn('sentinel', [redis, join(directory, 'sentinel.conf'), '--sentinel'])
  mongo = new MongoClient(mongoUri, { serverSelectionTimeoutMS: 1000 })
  await until('mongo ready', async () => {
    await mongo!.connect()

    return true
  })
  const db = mongo.db()
  const now = new Date()

  await db.collection('users').insertOne({
    _id: user,
    name: 'E2E',
    email: 'e2e@example.invalid',
    username: 'e2e',
    language: 'en',
    avatarURL: '',
    createdAt: now,
    updatedAt: now,
  })
  await db.collection('teams').insertOne({
    _id: team,
    name: 'E2E',
    ownerID: user,
    avatarUrl: '',
    contactEmails: [],
    agentRuntime: 'claude-code',
    members: [{ userId: user, role: 'owner', joinedAt: now }],
    createdAt: now,
    updatedAt: now,
  })
  await db.collection('team_byos_bindings').insertOne({
    _id: team,
    githubInstallations: [
      { installationId, accountLogin: 'e2e', accountType: 'Organization', addedAt: now },
    ],
  })
  await db.collection('agent_triggers').insertOne({
    _id: trigger,
    userId: user.toHexString(),
    teamId: team.toHexString(),
    executionPrincipalUserId: user.toHexString(),
    name: 'Local E2E',
    triggerType: 'webhook',
    enabled: true,
    configRevision: 1,
    messageTemplate: 'E2E_DELIVERY:{{trigger.deliveryId}}',
    sessionRouting: {
      keyTemplate: '{{payload.repository.id}}:{{payload.pull_request.number}}',
      github: { installationId, repositoryId, actions: ['synchronize'] },
    },
    createdAt: now,
    updatedAt: now,
  })
  await writeFile(acpLog, '')
  await writeFile(
    join(directory, 'openab.toml'),
    `[agent]\ncommand = ${JSON.stringify(Bun.which('node'))}\nargs = [${JSON.stringify(join(import.meta.dir, 'acp-fixture.mjs'))}]\nworking_dir = ${JSON.stringify(directory)}\n[agent.env]\nE2E_ACP_LOG = ${JSON.stringify(acpLog)}\n[pool]\nmax_sessions = 4\nsession_ttl_hours = 1\n`,
  )
  spawn('openab', [process.env.OPENAB ?? 'openab', 'run', '-c', join(directory, 'openab.toml')], {
    GATEWAY_ALLOWED_USERS: 'acp_client',
    OPENAB_ACP_ENABLED: 'true',
    OPENAB_ACP_AUTH_KEY: authKey,
    OPENAB_ACP_CONTROL_KEY: controlKey,
    OPENAB_ACP_MCP_SERVERS: 'true',
    GATEWAY_LISTEN: `127.0.0.1:${runtimePort}`,
  })
  queue = new Queue('atlas-agent-triggers', { connection: { host: '127.0.0.1', port: redisPort } })
  await queue.waitUntilReady()
  const backend = startBackend('backend')

  await healthy()
  assert.equal((await deliver('bad-signature', payload(), false)).status, 401)
  assert.equal(await queue.getJob(jobId('bad-signature')), undefined)
  assert.equal((await deliver('wrong-repository', payload(1, repositoryId + 1))).status, 204)
  assert.equal(await queue.getJob(jobId('wrong-repository')), undefined)
  console.log('PASS signature rejection and repository isolation')
  assert.equal((await deliver('first')).status, 204)
  await complete('first')
  const firstJob = await queue.getJob(jobId('first'))
  const sessionId = firstJob!.data.sessionId as string
  const results = await Promise.all([deliver('second'), deliver('third'), deliver('second')])

  assert(results.every((response) => response.status === 204))
  await complete('second')
  await complete('third')
  assert.equal((await queue.getJob(jobId('second')))!.data.sessionId, sessionId)
  assert.equal((await queue.getJob(jobId('third')))!.data.sessionId, sessionId)
  const starts = () =>
    readFile(acpLog, 'utf8').then((text) =>
      text
        .trim()
        .split('\n')
        .filter(Boolean)
        .map((line) => JSON.parse(line))
        .filter((event) => event.event === 'start'),
    )

  assert.equal((await starts()).length, 3)
  console.log('PASS same PR, concurrent events, duplicate delivery')
  // Pause the real durable queue so a delivery is acknowledged but not processed.
  await queue.pause()
  assert.equal((await deliver('after-restart')).status, 204)
  assert(await queue.getJob(jobId('after-restart')))
  await stop(backend)
  startBackend('backend-restarted')
  await healthy()
  await queue.resume()
  await complete('after-restart')
  assert.equal((await queue.getJob(jobId('after-restart')))!.data.sessionId, sessionId)
  assert.equal((await deliver('first')).status, 204)
  assert.equal((await deliver('other-pr', payload(2))).status, 204)
  await complete('other-pr')
  assert.notEqual((await queue.getJob(jobId('other-pr')))!.data.sessionId, sessionId)
  const observed = await starts()

  assert.equal(observed.length, 5)
  assert.equal(new Set(observed.slice(0, 4).map((event) => event.sessionId)).size, 1)
  assert.notEqual(observed[0].sessionId, observed[4].sessionId)
  const events = (await readFile(acpLog, 'utf8'))
    .trim()
    .split('\n')
    .map((line) => JSON.parse(line))

  assert.deepEqual(
    events.map((event) => event.event),
    Array.from({ length: 5 }, () => ['start', 'finish']).flat(),
  )
  assert.equal(await db.collection('agent_conversations').countDocuments({ sessionId }), 1)
  const messages = await db.collection('agent_messages').find({ sessionId }).toArray()

  assert.equal(messages.filter((message) => message.role === 'user').length, 4)
  assert.equal(messages.filter((message) => message.role === 'assistant').length, 4)
  for (const id of ['first', 'second', 'third', 'after-restart']) {
    assert(
      JSON.stringify(messages).includes(`ACK E2E_DELIVERY:${id}`),
      `Missing durable assistant answer: ${id}`,
    )
  }
  console.log('PASS worker restart, durable transcript, redelivery dedupe, different PR separation')
  console.log(
    'PASS webhook routing E2E (real MongoDB, Redis/Sentinel, BullMQ, OpenAB; fixture model)',
  )
} finally {
  await queue?.close()
  await mongo?.close()
  for (const child of children.toReversed()) await stop(child)
}
