// A self-hosted backend chosen on the sign-in screen.
//
// Every module resolves its API base URL from NUPHOS_API_URL once, at import
// time, so the saved choice is applied by seeding that variable before any of
// them load: main.ts imports this module first. Changing it relaunches the app
// instead of re-pointing live clients one by one. An explicit NUPHOS_API_URL
// (or the legacy ATLAS_API_URL) still wins over the saved value.

import fs from 'node:fs'
import path from 'node:path'

import { app } from 'electron'

import { CLI_CONFIG_PATH } from './cli-config-path.ts'

// Paired with the sign-in file (cli.yaml → cli.api-url), so `bun run dev`'s
// cli.dev.yaml never shares an endpoint with the installed app.
const SAVED_PATH = `${CLI_CONFIG_PATH.replace(/\.ya?ml$/, '')}.api-url`

if (!process.env.NUPHOS_API_URL && !process.env.ATLAS_API_URL) {
  try {
    const saved = fs.readFileSync(SAVED_PATH, 'utf8').trim()

    if (saved) process.env.NUPHOS_API_URL = saved
  } catch {
    // No saved endpoint: use the default.
  }
}

/** Saves the endpoint (`null` restores the default) and relaunches. */
export function setApiEndpoint(raw: string | null) {
  if (raw === null) {
    fs.rmSync(SAVED_PATH, { force: true })
    delete process.env.NUPHOS_API_URL
  } else {
    const url = new URL(raw.trim())

    if (url.protocol !== 'https:' && url.protocol !== 'http:') throw new Error('Not an http(s) URL')

    fs.mkdirSync(path.dirname(SAVED_PATH), { recursive: true })
    fs.writeFileSync(SAVED_PATH, `${url.origin}\n`, 'utf8')
    // The relaunched process inherits this environment.
    process.env.NUPHOS_API_URL = url.origin
  }
  delete process.env.ATLAS_API_URL
  app.relaunch()
  app.exit(0)
}
