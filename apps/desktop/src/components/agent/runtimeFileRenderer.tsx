import { useCallback } from 'react'

import { parseRuntimeFileLink } from '../../lib/runtimeFileLink'

import { RuntimeFileLink } from './RuntimeFileLink'

import type { ReactNode } from 'react'

export function useRuntimeFileRenderer(teamId?: string, sessionId?: string) {
  return useCallback(
    (href: string, children: ReactNode) => {
      const reference = parseRuntimeFileLink(href)

      if (!reference || reference.teamId !== teamId || reference.sessionId !== sessionId)
        return null

      return (
        <RuntimeFileLink key={href} reference={reference}>
          {children}
        </RuntimeFileLink>
      )
    },
    [teamId, sessionId],
  )
}
