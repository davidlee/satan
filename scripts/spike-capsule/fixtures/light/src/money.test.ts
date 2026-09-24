import { test } from 'node:test'
import assert from 'node:assert/strict'
import { toCents, formatCents } from './money.ts'

test('toCents converts a decimal amount to integer cents', () => {
  assert.equal(toCents(12.34), 1234)
  assert.equal(toCents(0), 0)
  assert.equal(toCents(-1.5), -150)
})

test('toCents absorbs binary floating-point drift', () => {
  assert.equal(toCents(0.1 + 0.2), 30)
})

test('formatCents renders two minor places', () => {
  assert.equal(formatCents(1234), '12.34')
  assert.equal(formatCents(0), '0.00')
  assert.equal(formatCents(5), '0.05')
  assert.equal(formatCents(-5), '-0.05')
})
