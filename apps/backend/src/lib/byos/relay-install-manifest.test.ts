import { describe, expect, it } from 'bun:test'

import { renderRelayInstallManifest } from '@/lib/byos/relay-install-manifest'

const REFERENCE_MANIFEST = '../kube-relay-agent/deploy/nuphos-relay-agent.yaml'

describe('renderRelayInstallManifest', () => {
  it('stays byte-identical to the manifest customers can also apply by hand', async () => {
    // The backend image cannot read the other app's files at runtime, so the
    // template is duplicated in TypeScript. This is the guard that the copy in
    // apps/kube-relay-agent/deploy and the one customers are handed never drift.
    //
    // apps/kube-relay-agent is not in every checkout — the open-source snapshot
    // drops it — and a drift guard cannot run against one copy. Skipping says so
    // rather than failing for a reason that has nothing to do with drift.
    const file = Bun.file(REFERENCE_MANIFEST)

    if (!(await file.exists())) {
      console.log(`skip drift check: ${REFERENCE_MANIFEST} is not in this checkout`)

      return
    }
    const reference = await file.text()
    const expected = reference
      .replaceAll('RELAY_ENDPOINT_PLACEHOLDER', 'relay.nuphos.ai:8444')
      .replaceAll('RELAY_TOKEN_PLACEHOLDER', 'nr1_token')
      .replaceAll('IMAGE_PLACEHOLDER', 'public.ecr.aws/alias/kube-relay-agent@sha256:abc')

    expect(
      renderRelayInstallManifest({
        agentEndpoint: 'relay.nuphos.ai:8444',
        agentToken: 'nr1_token',
        agentImage: 'public.ecr.aws/alias/kube-relay-agent@sha256:abc',
      }),
    ).toBe(expected)
  })

  it('leaves no placeholder behind', () => {
    const manifest = renderRelayInstallManifest({
      agentEndpoint: 'relay.nuphos.ai:8444',
      agentToken: 'nr1_token',
      agentImage: 'image@sha256:abc',
    })

    for (const placeholder of [
      'RELAY_ENDPOINT_PLACEHOLDER',
      'RELAY_TOKEN_PLACEHOLDER',
      'IMAGE_PLACEHOLDER',
    ]) {
      expect(manifest).not.toContain(placeholder)
    }
    expect(manifest).toContain('automountServiceAccountToken: false')
    expect(manifest).toContain('readOnlyRootFilesystem: true')
    // No inbound surface: the pod must never grow a Service or a container port.
    expect(manifest).not.toContain('kind: Service')
    expect(manifest).not.toContain('containerPort')
  })
})
