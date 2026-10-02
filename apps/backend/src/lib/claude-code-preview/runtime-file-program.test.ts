import { expect, test } from 'bun:test'
import { execFileSync } from 'node:child_process'
import { mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { RUNTIME_FILE_PROGRAM } from './runtime-file-program'

test('the cloud panel runner reads JSON params and returns exact binary bytes', async () => {
  const root = await mkdtemp(join(tmpdir(), 'runtime-file-'))

  try {
    const bytes = Buffer.from([0, 255, 10, 128])

    await writeFile(join(root, 'image.bin'), bytes)
    await writeFile(join(root, 'runner.mjs'), RUNTIME_FILE_PROGRAM)
    await writeFile(
      join(root, 'params.json'),
      JSON.stringify({ sessionId: 's', path: 'image.bin', workspace: root }),
    )
    // eslint-disable-next-line sonarjs/no-os-command-from-path -- Executes the fixture with the installed Node interpreter, without a shell.
    const output = execFileSync('node', [join(root, 'runner.mjs'), root], {
      env: { PATH: process.env.PATH },
      encoding: 'utf8',
      timeout: 5000,
    })

    expect(JSON.parse(output)).toEqual({
      name: 'image.bin',
      size: 4,
      data: bytes.toString('base64'),
    })
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
