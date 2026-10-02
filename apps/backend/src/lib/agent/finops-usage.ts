import { agentConversations } from '@/lib/agent/db'
import { fetchCachedTeams, fetchCachedUsers } from '@/lib/agent/directory'
import { foldByKey, foldTotals } from '@/lib/agent/finops-fold'
import { rangeFilter } from '@/lib/agent/finops-range'
import { agentTokenUsage } from '@/lib/agent/token-usage'
import { KIND_TOKEN_SUMS } from '@/lib/agent/usage-aggregation'

import type { FinopsRow, FinopsTotals, KeyedUsageTokenRow } from '@/lib/agent/finops-fold'
import type { FinopsRange } from '@/lib/agent/finops-range'
import type { Document } from 'mongodb'

export type FinopsTeamRow = FinopsRow & {
  teamId: string
  name: string
  userCount: number
  sessionCount: number
}

export type FinopsUserRow = FinopsRow & {
  userId: string
  name: string
  username: string
  sessionCount: number
}

export type FinopsSessionRow = FinopsRow & {
  sessionId: string
  title: string
  lastActiveAt: string | null
}

export type FinopsProviderRow = FinopsRow & {
  provider: string
  // Distinct model ids seen for this provider in the range — what the pricing
  // table was applied to, so a reader can check the rates themselves.
  modelIds: string[]
}

export type FinopsSummary = {
  // The window the totals cover. `until` is null for ranges still running, and
  // `asOf` is when the numbers were read.
  range: string
  since: string
  until: string | null
  asOf: string
  totals: FinopsTotals
  teams: FinopsTeamRow[]
  providers: FinopsProviderRow[]
}

// Rows without a teamId (personal chats) still cost money, so they get their
// own bucket rather than being dropped from the tally.
const NO_TEAM = ''

function tokenPipeline(keyExpr: unknown, match: Document): Document[] {
  return [
    { $match: match },
    {
      $group: {
        _id: { key: keyExpr, provider: '$provider', modelId: '$modelId' },
        ...KIND_TOKEN_SUMS,
      },
    },
    {
      $project: {
        _id: 0,
        key: '$_id.key',
        provider: '$_id.provider',
        modelId: '$_id.modelId',
        inputTokens: 1,
        cachedInputTokens: 1,
        cacheWriteTokens: 1,
        outputTokens: 1,
        totalTokens: 1,
      },
    },
  ]
}

type CountRow = { key: string; sessionCount: number; userIds: string[] }

// Distinct sessions and users per bucket. Counting these in the token pipeline
// is not possible — it is already grouped per model, so one session spanning
// two models would count twice.
function countPipeline(keyExpr: unknown, match: Document): Document[] {
  return [
    { $match: match },
    { $group: { _id: { key: keyExpr, userId: '$userId', sessionId: '$sessionId' } } },
    {
      $group: {
        _id: '$_id.key',
        sessionCount: { $sum: 1 },
        userIds: { $addToSet: '$_id.userId' },
      },
    },
    { $project: { _id: 0, key: '$_id', sessionCount: 1, userIds: 1 } },
  ]
}

async function runLevel(
  keyExpr: unknown,
  match: Document,
): Promise<{
  rows: FinopsRow[]
  totals: FinopsTotals
  counts: Map<string, CountRow>
  tokenRows: KeyedUsageTokenRow[]
}> {
  const [tokenRows, countRows] = await Promise.all([
    agentTokenUsage().aggregate<KeyedUsageTokenRow>(tokenPipeline(keyExpr, match)).toArray(),
    agentTokenUsage().aggregate<CountRow>(countPipeline(keyExpr, match)).toArray(),
  ])

  return {
    rows: foldByKey(tokenRows),
    totals: foldTotals(tokenRows),
    counts: new Map(countRows.map((row) => [row.key, row])),
    tokenRows,
  }
}

// The same rows the team breakdown is folded from, re-keyed by provider — no
// second query, and the two views cannot disagree.
function foldProviders(tokenRows: KeyedUsageTokenRow[]): FinopsProviderRow[] {
  const modelsByProvider = new Map<string, Set<string>>()

  for (const row of tokenRows) {
    const models = modelsByProvider.get(row.provider) ?? new Set<string>()

    models.add(row.modelId)
    modelsByProvider.set(row.provider, models)
  }

  return foldByKey(tokenRows.map((row) => ({ ...row, key: row.provider }))).map((row) => ({
    ...row,
    provider: row.key,
    modelIds: Array.from(modelsByProvider.get(row.key) ?? []).sort((a, b) => a.localeCompare(b)),
  }))
}

const teamKey = { $ifNull: ['$teamId', NO_TEAM] }

/** Totals for the whole install over one range, plus the per-team breakdown. */
export async function getFinopsSummary(
  range: FinopsRange,
  now: Date = new Date(),
): Promise<FinopsSummary> {
  const { rows, totals, counts, tokenRows } = await runLevel(teamKey, {
    createdAt: rangeFilter(range),
  })
  const teamNames = await fetchCachedTeams(rows.map((row) => row.key).filter(Boolean))

  return {
    range: range.key,
    since: range.since.toISOString(),
    until: range.until?.toISOString() ?? null,
    asOf: now.toISOString(),
    totals,
    providers: foldProviders(tokenRows),
    teams: rows.map((row) => ({
      ...row,
      teamId: row.key,
      name: row.key ? teamNames[row.key]?.name || row.key : 'No team (personal)',
      userCount: counts.get(row.key)?.userIds.length ?? 0,
      sessionCount: counts.get(row.key)?.sessionCount ?? 0,
    })),
  }
}

function teamMatch(teamId: string, range: FinopsRange): Document {
  const createdAt = rangeFilter(range)

  return teamId
    ? { teamId, createdAt }
    : { createdAt, $or: [{ teamId: { $exists: false } }, { teamId: NO_TEAM }, { teamId: null }] }
}

/** Spend of every member inside one team (or the no-team bucket) over a range. */
export async function getFinopsTeamUsers(
  teamId: string,
  range: FinopsRange,
): Promise<{ users: FinopsUserRow[] }> {
  const { rows, counts } = await runLevel('$userId', teamMatch(teamId, range))
  const userNames = await fetchCachedUsers(rows.map((row) => row.key))

  return {
    users: rows.map((row) => ({
      ...row,
      userId: row.key,
      name: userNames[row.key]?.name ?? '',
      username: userNames[row.key]?.username ?? '',
      sessionCount: counts.get(row.key)?.sessionCount ?? 0,
    })),
  }
}

/** Spend of one member's sessions inside one team over a range. */
export async function getFinopsUserSessions(
  teamId: string,
  userId: string,
  range: FinopsRange,
): Promise<{ sessions: FinopsSessionRow[] }> {
  const { rows } = await runLevel('$sessionId', { ...teamMatch(teamId, range), userId })
  const sessionIds = rows.map((row) => row.key)
  const conversations = sessionIds.length
    ? await agentConversations()
        .find(
          { sessionId: { $in: sessionIds } },
          { projection: { sessionId: 1, title: 1, firstMessage: 1, lastActiveAt: 1 } },
        )
        .toArray()
    : []
  const byId = new Map(conversations.map((conv) => [conv.sessionId, conv]))

  return {
    sessions: rows.map((row) => {
      const conv = byId.get(row.key)

      return {
        ...row,
        sessionId: row.key,
        title: conv?.title || conv?.firstMessage || 'Untitled chat',
        lastActiveAt: conv?.lastActiveAt ? new Date(conv.lastActiveAt).toISOString() : null,
      }
    }),
  }
}
