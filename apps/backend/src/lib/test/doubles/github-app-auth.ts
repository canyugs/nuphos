import { mock } from 'bun:test'

import * as actual from '@/lib/byos/github-app-auth'

import { buildDouble, makeInstaller } from '../double-registry'

const double = buildDouble('@/lib/byos/github-app-auth', actual)

await mock.module('@/lib/byos/github-app-auth', () => double)
export const useGithubAppAuth = makeInstaller<typeof actual>('@/lib/byos/github-app-auth')
