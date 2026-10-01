import { ObjectId } from 'mongodb'

import { AppError } from '@/lib/errors'

import { normalizeConversationTriggerRun } from './conversation-trigger-run'
import { getConversationBySessionId } from './db'
import { agentTriggers } from './trigger-db'

/** Derive the immutable repository boundary from the server-owned trigger stamp. */
export async function githubReviewScope(sessionId: string | undefined, teamId: string) {
  if (!sessionId) return
  const conversation = await getConversationBySessionId(sessionId)

  if (!conversation || conversation.teamId !== teamId) {
    throw new AppError(403, 'github_review_scope', 'Conversation is not in this team')
  }
  const stamp = normalizeConversationTriggerRun(conversation.metadata)

  if (!stamp) return
  if (!ObjectId.isValid(stamp.id)) throw new AppError(403, 'github_review_scope', 'Invalid trigger')
  const trigger = await agentTriggers().findOne({ _id: new ObjectId(stamp.id), teamId })

  if (!trigger) throw new AppError(403, 'github_review_scope', 'Trigger is no longer available')

  return trigger.sessionRouting?.github
}

export function assertGithubReviewRequest(
  scope: { installationId: number },
  method: string,
  path: string,
) {
  const root = `/github-installations/${String(scope.installationId)}`

  if (
    method !== 'GET' ||
    !(path.endsWith(root) || path.endsWith(`${root}/`) || path.endsWith(`${root}/token`))
  ) {
    throw new AppError(
      403,
      'github_review_scope',
      'Use the repository-scoped GitHub token for this review',
    )
  }
}
