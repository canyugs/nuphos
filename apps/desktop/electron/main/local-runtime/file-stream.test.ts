import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, symlink, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { LocalFileStream } from './file-stream.ts'

async function fixture(run: (root: string) => Promise<void>) {
  const root = await mkdtemp(join(tmpdir(), 'runtime-preview-'))

  try {
    await mkdir(join(root, 'conv-session'))
    await run(root)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
}

async function read(root: string, path: string, workspace?: string, action?: 'list') {
  const stream = new LocalFileStream(root)

  return await new Promise<Record<string, unknown>>((resolve, reject) => {
    stream.addEventListener('open', () =>
      stream.send(JSON.stringify({ sessionId: 'session', path, workspace, action })),
    )
    stream.addEventListener('message', ({ data }) => resolve(JSON.parse(String(data))))
    stream.addEventListener('close', () => reject(new Error('closed without a result')))
  })
}

test('reads UTF-8 and empty files through the local tunnel stream', () =>
  fixture(async (root) => {
    await writeFile(join(root, 'conv-session/報告.md'), 'hello 世界')
    await writeFile(join(root, 'conv-session/empty'), '')
    const result = await read(root, '/workspace/報告.md')

    assert.equal(Buffer.from(String(result.data), 'base64').toString(), 'hello 世界')
    assert.equal((await read(root, 'empty')).size, 0)
  }))

test('rejects sibling paths, symlink escapes, directories and oversized files', () =>
  fixture(async (root) => {
    await writeFile(join(root, 'secret'), 'private')
    await symlink(join(root, 'secret'), join(root, 'conv-session/link'))
    await writeFile(join(root, 'conv-session/large'), Buffer.alloc(512 * 1024 + 1))
    assert.equal((await read(root, '../secret')).error, 'forbidden_path')
    assert.equal((await read(root, 'link')).error, 'forbidden_path')
    assert.equal((await read(root, 'large')).error, 'file_too_large')
    assert.equal((await read(root, 'missing')).error, 'file_not_found')
    await mkdir(join(root, 'conv-session/folder'))
    assert.equal((await read(root, 'folder')).error, 'not_a_file')
  }))

test('refuses a workspace root replaced with a symlink', () =>
  fixture(async (root) => {
    await rm(join(root, 'conv-session'), { recursive: true })
    await mkdir(join(root, 'other'))
    await writeFile(join(root, 'other/file'), 'private')
    await symlink(join(root, 'other'), join(root, 'conv-session'))
    assert.equal((await read(root, 'file')).error, 'forbidden_path')
  }))

test('ignores a caller-supplied workspace outside the local runtime', () =>
  fixture(async (root) => {
    await writeFile(join(root, 'secret'), 'private')
    assert.equal((await read(root, 'secret', root)).error, 'file_not_found')
  }))

test('lists directories over the local stream without trusting caller roots', () =>
  fixture(async (root) => {
    await writeFile(join(root, 'conv-session/file.txt'), 'hello')
    await mkdir(join(root, 'conv-other'))
    const result = await read(root, '/workspace', '/ignored-root', 'list')

    assert.deepEqual(result.entries, [{ name: 'file.txt', kind: 'file' }])
    assert.equal(result.truncated, false)
  }))

test('rejects sibling conversation reads and a missing conversation root', () =>
  fixture(async (root) => {
    await mkdir(join(root, 'conv-other'))
    await writeFile(join(root, 'conv-other/secret'), 'private')
    assert.equal((await read(root, '../conv-other/secret')).error, 'forbidden_path')
    assert.equal((await read(root, join(root, 'conv-other/secret'))).error, 'forbidden_path')
    await rm(join(root, 'conv-session'), { recursive: true })
    assert.equal((await read(root, '/workspace', undefined, 'list')).error, 'file_not_found')
  }))
