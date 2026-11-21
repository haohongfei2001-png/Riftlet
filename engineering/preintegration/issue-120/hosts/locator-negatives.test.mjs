import test from 'node:test'
import assert from 'node:assert/strict'

// These are counterexamples to candidate keys, independent of browser implementation.
const slotView = tabs => ({ window: 1, index: 0, URL: tabs[0].URL })
test('closing the original same-URL tab preserves the slot key', () => {
  const tabs = ['A', 'B'].map(document => ({ document, URL: '/same' }))
  const original = tabs[0]
  const seen = slotView(tabs)
  tabs.shift()
  assert.deepEqual(slotView(tabs), seen)
  assert.notEqual(tabs[0], original)
})

test('a token first installed after a swap cannot prove the clicked document', () => {
  const stable = {document: 'B', URL: '/same'}
  const swapped = {document: 'A', URL: '/same'}
  const bind = original => ({ before: slotView([original]), firstPin: { document: 'B', token: 'new' } })
  assert.deepEqual(bind(stable), bind(swapped))
  assert.notEqual(stable.document, swapped.document)
})

test('filename, size and count cannot identify the original attachment bytes', () => {
  const original = { name: 'capture.png', bytes: [1, 2, 3] }
  const other = { name: 'capture.png', bytes: [3, 2, 1] }
  const visible = file => ({ count: 1, name: file.name, size: file.bytes.length })
  assert.deepEqual(visible(original), visible(other))
  assert.notDeepEqual(original.bytes, other.bytes)
})
