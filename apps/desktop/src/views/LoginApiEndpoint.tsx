import { useEffect, useState } from 'react'

import { api } from '../api'
import { Button } from '../components/ui/button'
import { toast } from '../components/ui/toast'

const DEFAULT_API_URL = 'https://api.nuphos.ai'

type Props = { inputClassName: string }

function isHttpUrl(raw: string) {
  try {
    return ['http:', 'https:'].includes(new URL(raw.trim()).protocol)
  } catch {
    return false
  }
}

function save(url: string | null) {
  if (url !== null && !isHttpUrl(url)) {
    toast.error('Invalid API endpoint', 'Enter a full URL, e.g. https://nuphos.example.com')

    return
  }
  void api.appSetApiEndpoint(url)
}

/** The sign-in screen's quiet "self-hosted backend" switch. Saving relaunches the app. */
export function LoginApiEndpoint({ inputClassName }: Props) {
  const [current, setCurrent] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [value, setValue] = useState('')

  useEffect(() => {
    void api.atlasGetApiUrl().then(setCurrent)
  }, [])

  if (!current) return null
  const custom = current !== DEFAULT_API_URL

  if (!editing) {
    return (
      <button
        type="button"
        onClick={() => {
          setValue(custom ? current : '')
          setEditing(true)
        }}
        className="mt-6 text-[12px] text-tertiary hover:text-secondary titlebar-no-drag"
      >
        {custom ? `Server: ${new URL(current).host} · Change` : 'Self-hosted? Set API endpoint'}
      </button>
    )
  }

  return (
    <form
      className="mt-6 w-full flex flex-col gap-2"
      onSubmit={(e) => {
        e.preventDefault()
        save(value)
      }}
    >
      <input
        type="url"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="https://nuphos.example.com"
        autoFocus
        className={inputClassName}
      />
      <div className="flex items-center gap-2">
        <Button type="submit" size="sm" disabled={!value.trim()} className="titlebar-no-drag">
          Save and restart
        </Button>
        {custom && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => save(null)}
            className="titlebar-no-drag"
          >
            Use Nuphos Cloud
          </Button>
        )}
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={() => setEditing(false)}
          className="ml-auto titlebar-no-drag"
        >
          Cancel
        </Button>
      </div>
    </form>
  )
}
