import { expect, test } from 'bun:test'
import { ObjectId } from 'mongodb'

import { useDb } from '@/lib/test/doubles/db'
import { useTriggerScheduler } from '@/lib/test/doubles/trigger-scheduler'

import { routeWebhookSession } from './webhook-session-router'

import type { AgentTrigger } from './trigger-db'
import type { WebhookTurnJob } from './trigger-scheduler'

const queued: { data: WebhookTurnJob; id: string }[] = []
let unavailable = false

useTriggerScheduler({
  enqueueWebhookTurn: async (data, id) => {
    if (unavailable) throw new Error('queue unavailable')
    queued.push({ data, id })
  },
})
useDb({ db: () => ({ collection: () => ({}) }) })

const trigger: AgentTrigger = {
  _id: new ObjectId(),
  teamId: new ObjectId().toHexString(),
  userId: 'actor',
  name: 'PRs',
  triggerType: 'webhook',
  enabled: true,
  messageTemplate: '{{payload.number}}',
  sessionRouting: { keyTemplate: 'pr:{{payload.number}}' },
  configRevision: 1,
  createdAt: new Date(),
  updatedAt: new Date(),
}

test('concurrent first deliveries share a session; duplicate IDs share a durable job ID', async () => {
  queued.length = 0
  const sessions = await Promise.all([
    routeWebhookSession(trigger, { number: 1 }, 'delivery-1'),
    routeWebhookSession(trigger, { number: 1 }, 'delivery-1'),
    routeWebhookSession(trigger, { number: 1 }, 'delivery-2'),
    routeWebhookSession(trigger, { number: 2 }, 'delivery-3'),
  ])

  expect(sessions[0]).toBe(sessions[1])
  expect(sessions[0]).toBe(sessions[2])
  expect(sessions[0]).not.toBe(sessions[3])
  expect(queued[0]?.id).toBe(queued[1]?.id)
  expect(queued[0]?.id).not.toBe(queued[2]?.id)
  expect(queued[0]?.data.revision).toBe(1)
  expect(queued[0]?.data.deliveryId).toBe('delivery-1')
})

test('invalid keys and disabled or expired triggers never enqueue', async () => {
  queued.length = 0
  await expect(routeWebhookSession(trigger, {}, 'd')).rejects.toThrow('missing')
  await expect(routeWebhookSession(trigger, { number: 1 }, '')).rejects.toThrow('delivery ID')
  await routeWebhookSession({ ...trigger, enabled: false }, { number: 1 }, 'd')
  await routeWebhookSession({ ...trigger, expiresAt: new Date(0) }, { number: 1 }, 'd')
  expect(queued).toHaveLength(0)
})

test('persistence failure rejects acceptance so the sender can retry', async () => {
  unavailable = true
  try {
    await expect(routeWebhookSession(trigger, { number: 1 }, 'retry-me')).rejects.toThrow(
      'queue unavailable',
    )
  } finally {
    unavailable = false
  }
})
