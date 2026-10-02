import assert from 'node:assert/strict'
import { test } from 'node:test'

import { parseDevOptions } from './dev-options.ts'

test('reset and managed default off', () => {
  assert.deepEqual(parseDevOptions([]), { reset: false, managed: null })
})

test('--reset wipes the stack first', () => {
  assert.deepEqual(parseDevOptions(['--reset']), {
    reset: true,
    managed: null,
  })
})

test('--managed runs managed agents on OrbStack unless it names another context', () => {
  assert.equal(parseDevOptions(['--managed']).managed, 'orbstack')
  assert.equal(parseDevOptions(['--managed=kind-nuphos']).managed, 'kind-nuphos')
  assert.equal(parseDevOptions(['--managed=kind-a', '--managed']).managed, 'orbstack')
})
