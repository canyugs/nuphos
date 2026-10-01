import { mock } from 'bun:test'

import * as actual from '@/lib/agent/trigger-scheduler'

import { buildDouble, makeInstaller } from '../double-registry'

const double = buildDouble('@/lib/agent/trigger-scheduler', actual)

await mock.module('@/lib/agent/trigger-scheduler', () => double)

export const useTriggerScheduler = makeInstaller<typeof actual>('@/lib/agent/trigger-scheduler')
