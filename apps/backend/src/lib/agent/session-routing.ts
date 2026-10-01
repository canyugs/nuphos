import { createHash } from 'node:crypto'

import { z } from 'zod'

import { AppError } from '@/lib/errors'

export const sessionRoutingSchema = z
  .object({
    keyTemplate: z.string().trim().min(1).max(500),
    github: z
      .object({
        installationId: z.number().int().positive(),
        repositoryId: z.number().int().positive(),
        actions: z
          .array(z.enum(['opened', 'reopened', 'synchronize', 'ready_for_review', 'labeled']))
          .min(1),
        label: z.string().trim().min(1).max(100).optional(),
      })
      .strict()
      .optional(),
  })
  .strict()

export type SessionRouting = z.infer<typeof sessionRoutingSchema>

/** Missing or compound values must never collapse unrelated events onto one session. */
export function resolveSessionKey(template: string, payload: unknown): string {
  const key = template.replace(/\{\{([^{}]+)\}\}/g, (_match, path: string) => {
    let value: unknown = { payload }

    for (const part of path.trim().split('.')) {
      if (!value || typeof value !== 'object' || !Object.hasOwn(value, part)) {
        throw new AppError(400, 'invalid_session_key', 'Session key field is missing')
      }
      value = (value as Record<string, unknown>)[part]
    }
    if ((typeof value !== 'string' && typeof value !== 'number') || String(value).trim() === '') {
      throw new AppError(400, 'invalid_session_key', 'Session key fields must be nonempty scalars')
    }

    return encodeURIComponent(String(value))
  })

  if (!key || key.length > 1000 || key.includes('{{') || key.includes('}}')) {
    throw new AppError(400, 'invalid_session_key', 'Invalid session key')
  }

  return key
}

/** Deterministic UUID: no lookup/create race or second mapping collection. */
export function routedSessionId(teamId: string, triggerId: string, key: string): string {
  const hex = createHash('sha256')
    .update(JSON.stringify([teamId, triggerId, key]))
    .digest('hex')

  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-8${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`
}

export function matchesGithubRoute(
  route: SessionRouting,
  event: string,
  payload: unknown,
): boolean {
  const filter = route.github

  if (!filter || event !== 'pull_request' || !payload || typeof payload !== 'object') return false
  const body = payload as {
    action?: string
    installation?: { id?: number }
    repository?: { id?: number }
    pull_request?: { number?: number; labels?: { name?: string }[] }
  }

  return (
    body.installation?.id === filter.installationId &&
    body.repository?.id === filter.repositoryId &&
    Number.isSafeInteger(body.pull_request?.number) &&
    filter.actions.some((action) => action === body.action) &&
    (!filter.label ||
      body.pull_request?.labels?.some((label) => label.name === filter.label) === true)
  )
}
