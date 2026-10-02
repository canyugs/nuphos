import { createHash } from 'node:crypto'

import { ObjectId } from 'mongodb'

import { findGithubInstallation } from '@/lib/byos/account'
import { AppError } from '@/lib/errors'

import { matchesGithubRoute, resolveSessionKey, routedSessionId } from './session-routing'
import { agentTriggers } from './trigger-db'
import { resolveExecutionAuthorization } from './trigger-executor-authorization'
import { enqueueWebhookTurn } from './trigger-scheduler'

import type { AgentTrigger } from './trigger-db'

/** Called only after the provider-specific ingress authenticated the raw request. */
export async function routeWebhookSession(
  trigger: AgentTrigger,
  payload: unknown,
  deliveryId: string,
) {
  if (!trigger._id || !trigger.teamId || !trigger.sessionRouting) {
    throw new AppError(400, 'invalid_routing', 'Trigger has no session routing')
  }
  if (!deliveryId || deliveryId.length > 200) {
    throw new AppError(400, 'invalid_delivery_id', 'A bounded delivery ID is required')
  }
  if (!trigger.enabled || (trigger.expiresAt && trigger.expiresAt.getTime() <= Date.now())) return
  const github = trigger.sessionRouting.github

  if (github) {
    if (!(await findGithubInstallation(new ObjectId(trigger.teamId), github.installationId))) return
    const { credentialAccess } = await resolveExecutionAuthorization(trigger)

    if (!credentialAccess.githubInstallationIds?.includes(String(github.installationId))) {
      throw new AppError(
        403,
        'github_route_forbidden',
        'Trigger cannot access this GitHub installation',
      )
    }
  }
  const triggerId = trigger._id.toHexString()
  const key = resolveSessionKey(trigger.sessionRouting.keyTemplate, payload)
  const sessionId = routedSessionId(trigger.teamId, triggerId, key)
  const jobId = createHash('sha256')
    .update(JSON.stringify([triggerId, deliveryId]))
    .digest('hex')

  await enqueueWebhookTurn(
    { triggerId, sessionId, payload, deliveryId, revision: trigger.configRevision ?? 0 },
    jobId,
  )

  return sessionId
}

export async function routeGithubWebhook(event: string, payload: unknown, deliveryId: string) {
  if (event !== 'pull_request') return
  const installationId = (payload as { installation?: { id?: unknown } } | null)?.installation?.id

  if (!Number.isSafeInteger(installationId)) return
  const triggers = await agentTriggers()
    .find({
      triggerType: 'webhook',
      enabled: true,
      'sessionRouting.github.installationId': installationId,
    })
    .toArray()

  for (const trigger of triggers) {
    if (trigger.sessionRouting && matchesGithubRoute(trigger.sessionRouting, event, payload)) {
      await routeWebhookSession(trigger, payload, deliveryId)
    }
  }
}
