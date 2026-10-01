import { mkdtemp } from 'node:fs/promises'
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

export const directory = await mkdtemp(join(tmpdir(), 'webhook-routing-e2e-'))
export const children: ReturnType<typeof Bun.spawn>[] = []
// Deliberately do not inherit provider credentials or runtime configuration.
const baseEnv = Object.fromEntries(
  ['PATH', 'HOME', 'LD_LIBRARY_PATH'].flatMap((key) =>
    process.env[key] ? [[key, String(process.env[key])]] : [],
  ),
)

export async function port() {
  const server = createServer()

  await new Promise<void>((done) => server.listen(0, '127.0.0.1', done))
  const value = (server.address() as { port: number }).port

  await new Promise<void>((done) => server.close(() => done()))

  return value
}
export async function until(label: string, check: () => Promise<boolean>, timeout = 60000) {
  const deadline = Date.now() + timeout

  while (Date.now() < deadline) {
    if (await check().catch(() => false)) return
    await Bun.sleep(200)
  }
  throw new Error(`Timed out: ${label}; logs: ${directory}`)
}
export function spawn(name: string, cmd: string[], env: Record<string, string> = {}) {
  const log = Bun.file(join(directory, `${name}.log`))
  const child = Bun.spawn(cmd, {
    cwd: directory,
    env: { ...baseEnv, ...env },
    stdout: log,
    stderr: log,
  })

  children.push(child)

  return child
}
export async function stop(child: ReturnType<typeof Bun.spawn>) {
  if (child.exitCode !== null) return
  child.kill('SIGTERM')
  await Promise.race([child.exited, Bun.sleep(3000)])
  if (child.exitCode === null) child.kill('SIGKILL')
  await child.exited
}
