import { mock } from 'bun:test'

import * as actual from '@/lib/byos/github-http'

import { buildDouble, makeInstaller } from '../double-registry'

const double = buildDouble('@/lib/byos/github-http', actual)

await mock.module('@/lib/byos/github-http', () => double)
export const useGithubHttp = makeInstaller<typeof actual>('@/lib/byos/github-http')
