/**
 * Money is integer cents. Floats never survive contact with a ledger.
 */

/** Convert a decimal amount to integer cents, rounding half away from zero. */
export function toCents(amount: number): number {
  return Math.round(amount * 100)
}

/** Render integer cents as a fixed two-place decimal string. */
export function formatCents(cents: number): string {
  const sign = cents < 0 ? '-' : ''
  const abs = Math.abs(cents)
  const minor = String(abs % 100).padStart(2, '0')
  return `${sign}${Math.floor(abs / 100)}.${minor}`
}
