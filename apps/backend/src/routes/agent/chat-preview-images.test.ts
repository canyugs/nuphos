import { expect, test } from 'bun:test'

import { inputImages } from './chat-preview-prepare'
import { turnInputMessages } from './turn-start-frame'

import type { UIMessage } from 'ai'

const photo = (id: string): UIMessage => ({
  id,
  role: 'user',
  parts: [
    { type: 'text', text: 'Read this image' },
    { type: 'file', mediaType: 'image/jpeg', url: 'data:image/jpeg;base64,/9j/AA==' },
  ],
})

test('turn input image becomes a native ACP image without the data URL prefix', () => {
  expect(inputImages([photo('current')])).toEqual([
    { type: 'image', mimeType: 'image/jpeg', data: '/9j/AA==' },
  ])
})

test('prior-turn images are not replayed in the next prompt', () => {
  const messages: UIMessage[] = [
    photo('old'),
    { id: 'answer', role: 'assistant', parts: [] },
    photo('new'),
  ]

  expect(inputImages(turnInputMessages(messages))).toHaveLength(1)
})

test('non-images and mismatched data URL media types do not become vision content', () => {
  expect(
    inputImages([
      {
        id: 'files',
        role: 'user',
        parts: [
          { type: 'file', mediaType: 'application/pdf', url: 'data:application/pdf;base64,AA==' },
          { type: 'file', mediaType: 'image/jpeg', url: 'data:image/png;base64,AA==' },
        ],
      },
    ]),
  ).toEqual([])
})
