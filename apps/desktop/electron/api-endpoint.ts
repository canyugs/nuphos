// A self-hosted backend chosen on the sign-in screen.
//
// Every module resolves its API base URL from NUPHOS_API_URL once, at import
// time, so the saved choice is applied by seeding that variable before any of
// them load: main.ts imports this module first. Changing it relaunches the app
// instead of re-pointing live clients one by one.

import fs from 'node:fs'

import { app } from 'electron'

import { CLI_CONFIG_PATH } from './cli-config-path.ts'

// Paired with the sign-in file (cli.yaml → cli.api-url), so `bun run dev`'s
// cli.dev.yaml never shares an endpoint with the installed app.
const SAVED_PATH = `${CLI_CONFIG_PATH.replace(/\.ya?ml$/, '')}.api-url`

// A launch-time NUPHOS_API_URL (the dev launcher, or a user's own) pins the
// endpoint; the sign-in screen only shows it.
const pinned = Boolean(process.env.NUPHOS_API_URL || process.env.ATLAS_API_URL)

if (!pinned) {
  try {
    const saved = fs.readFileSync(SAVED_PATH, 'utf8').trim()

    if (saved) process.env.NUPHOS_API_URL = saved
  } catch {
    // No saved endpoint: use the default.
  }
}

export function getApiEndpoint() {
  return {
    url: process.env.NUPHOS_API_URL || process.env.ATLAS_API_URL || 'https://api.nuphos.ai',
    // An unpackaged app runs under vite, which a relaunch would leave behind.
    editable: app.isPackaged && !pinned,
  }
}

/** Saves the endpoint (`null` restores the default) and relaunches. */
export function setApiEndpoint(raw: string | null) {
  if (!getApiEndpoint().editable) throw new Error('The API endpoint is set at launch')
  if (raw === null) {
    fs.rmSync(SAVED_PATH, { force: true })
  } else {
    const url = new URL(raw.trim())

    if (url.protocol !== 'https:' && url.protocol !== 'http:') throw new Error('Not an http(s) URL')
    fs.writeFileSync(SAVED_PATH, `${url.origin}\n`, 'utf8')
  }
  // Unset, so the relaunched process reads the file instead of inheriting a pin.
  delete process.env.NUPHOS_API_URL
  app.relaunch()
  app.exit(0)
}
