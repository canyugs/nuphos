import { useState } from 'react'

import { api } from '../../api'
import { runtimeFilePreview } from '../../lib/runtimeFileLink'
import { Modal } from '../Modal'

import type { RuntimeFileReference } from '../../lib/runtimeFileLink'
import type { ReactNode } from 'react'

export function RuntimeFileLink({
  reference,
  children,
}: {
  reference: RuntimeFileReference
  children: ReactNode
}) {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [preview, setPreview] = useState<ReturnType<typeof runtimeFilePreview>>(null)

  async function show() {
    setOpen(true)
    setLoading(true)
    setError('')
    setPreview(null)
    try {
      const file = await api.atlasReadRuntimeFile(
        reference.teamId,
        reference.runtimeId,
        reference.sessionId,
        reference.path,
      )
      const content = runtimeFilePreview(file)

      if (!content)
        setError('This file format cannot be previewed. Ask the agent to provide a download.')
      setPreview(content)
    } catch (cause) {
      setError(
        cause instanceof Error ? cause.message : 'Could not read the file from its source agent.',
      )
    } finally {
      setLoading(false)
    }
  }

  return (
    <>
      <button
        type="button"
        className="text-zViolet-accent hover:underline"
        onClick={() => void show()}
        disabled={loading}
      >
        {children}
      </button>
      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title={reference.path.split(/[\\/]/).at(-1) || 'File preview'}
        width={900}
      >
        <div className="mb-3 break-all text-xs text-tertiary">{reference.path} · Live file</div>
        {loading && <p role="status">Reading file…</p>}
        {error && (
          <p role="alert" className="text-sm text-error">
            {error}
          </p>
        )}
        {preview &&
          ('image' in preview ? (
            <img
              src={preview.image}
              alt={reference.path}
              className="max-h-[70vh] max-w-full object-contain"
            />
          ) : (
            <pre className="max-h-[70vh] overflow-auto whitespace-pre-wrap break-words font-mono text-sm">
              {preview.text}
            </pre>
          ))}
      </Modal>
    </>
  )
}
