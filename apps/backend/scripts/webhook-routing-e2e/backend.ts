// Real ingress and worker; only unrelated API routes/startup jobs are omitted.
import { Hono } from 'hono'

import { config } from '../../src/config'
import { initTriggerScheduler } from '../../src/lib/agent/trigger-scheduler'
import { connectDb } from '../../src/lib/db'
import { errorHandler } from '../../src/lib/errors'
import { githubAppRoutes } from '../../src/routes/github-app'

await connectDb()
await initTriggerScheduler()
const app = new Hono().onError(errorHandler)

app.route('/github-app', githubAppRoutes)
app.get('/health', (c) => c.text('ready'))
Bun.serve({ hostname: '127.0.0.1', port: config.port, fetch: app.fetch })
