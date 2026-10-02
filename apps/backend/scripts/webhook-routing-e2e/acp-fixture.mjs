// Deterministic model substitute, behind the real OpenAB executable and ACP transport.
// No network tools, GitHub credentials, or real inference are used.
import { randomUUID } from 'node:crypto'
import { appendFileSync } from 'node:fs'
import { createInterface } from 'node:readline'

const send = (message) =>
  process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`)
for await (const line of createInterface({ input: process.stdin })) {
  const request = JSON.parse(line)
  if (request.id === undefined) continue
  let result = {}
  switch (request.method) {
    case 'initialize':
      result = {
        protocolVersion: 1,
        agentCapabilities: { loadSession: true },
        agentInfo: { name: 'routing-e2e', version: '1' },
        authMethods: [],
      }
      break
    case 'session/new':
      result = { sessionId: randomUUID() }
      break
    case 'session/prompt': {
      const text = request.params.prompt
        .filter((part) => part.type === 'text')
        .map((part) => part.text)
        .join('\n')
      const markers = text.match(/E2E_DELIVERY:[a-z0-9-]+/g) ?? []
      const marker = markers.at(-1) ?? 'E2E_DELIVERY:missing'
      appendFileSync(
        process.env.E2E_ACP_LOG,
        `${JSON.stringify({ sessionId: request.params.sessionId, marker, event: 'start' })}\n`,
      )
      await new Promise((resolve) => setTimeout(resolve, 1000))
      send({
        method: 'session/update',
        params: {
          sessionId: request.params.sessionId,
          update: {
            sessionUpdate: 'agent_message_chunk',
            content: { type: 'text', text: `ACK ${marker}` },
          },
        },
      })
      appendFileSync(
        process.env.E2E_ACP_LOG,
        `${JSON.stringify({ sessionId: request.params.sessionId, marker, event: 'finish' })}\n`,
      )
      result = { stopReason: 'end_turn' }
      break
    }
    case 'session/load':
    case 'session/set_mode':
    case 'session/set_config_option':
      break
    default:
      send({
        id: request.id,
        error: { code: -32601, message: `Unsupported fixture method: ${request.method}` },
      })
      continue
  }
  send({ id: request.id, result })
}
