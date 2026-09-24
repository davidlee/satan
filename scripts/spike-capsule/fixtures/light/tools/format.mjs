#!/usr/bin/env node
// Dependency-free formatter for the ledger fixture: no trailing whitespace,
// exactly one final newline. `--check` (default) reports and exits nonzero;
// `--write` rewrites in place.
import { readdir, readFile, writeFile } from 'node:fs/promises'
import { join, extname } from 'node:path'

const args = process.argv.slice(2)
const write = args.includes('--write')
const roots = args.filter((a) => !a.startsWith('--'))
const extensions = new Set(['.ts', '.mjs', '.js', '.json'])

async function* walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(path)
    else if (extensions.has(extname(path))) yield path
  }
}

const normalise = (text) => text.replace(/[ \t]+$/gm, '').replace(/\n*$/, '\n')

let offenders = 0
for (const root of roots) {
  for await (const file of walk(root)) {
    const before = await readFile(file, 'utf8')
    const after = normalise(before)
    if (before === after) continue
    offenders += 1
    if (write) await writeFile(file, after)
    else console.error(`format: needs formatting: ${file}`)
  }
}

if (offenders > 0 && !write) {
  console.error(`format: ${offenders} file(s) need formatting`)
  process.exit(1)
}
console.log(write ? `format: ${offenders} file(s) rewritten` : 'format: clean')
