#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const DECISION_PACKAGE_GATE_CONTRACT_VERSION = '2026-06-shared-owner-rp-v1'

const USAGE = `
Usage:
  node check-shared-owner-regression-gate.mjs --mode bugfix|pr-review --package <decision-package.md> [--changed-files a.ts,b.ts]
  node check-shared-owner-regression-gate.mjs --mode bugfix|pr-review --packages-dir docs/plans
  node check-shared-owner-regression-gate.mjs --self-test

Fails when shared/lower-level owner files changed but no owner regression
decision package is supplied. When a package is supplied, this gate invokes the
skill-local check-decision-package.mjs with the detected changed files.
`

const SHARED_FILE_RE =
  /(^|\/)(api\/request|src\/api\/request|hooks?|components?|utils?|helpers?|scripts?|workflow|templates?|generator|config|auth|queryClient|routes?|atoms?|types?|permissions?|router|store)\b/i

const args = process.argv.slice(2)

if (args.includes('--version')) {
  console.log(DECISION_PACKAGE_GATE_CONTRACT_VERSION)
  process.exit(0)
}

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
  console.log(USAGE.trim())
  process.exit(args.length === 0 ? 1 : 0)
}

if (args.includes('--self-test')) {
  runSelfTest()
  process.exit(0)
}

const mode = getOption('--mode') || 'generic'
const changedFiles = getChangedFiles()
const sharedFiles = changedFiles.filter(isSharedOwnerPath)
const packageFiles = getPackageFiles()

if (changedFiles.length === 0) {
  fail('changed-file input is required; pass --changed-files, set DECISION_PACKAGE_CHANGED_FILES, or run inside a git worktree.')
}

if (sharedFiles.length === 0) {
  pass('no shared/lower-level owner files changed.')
}

if (packageFiles.length === 0) {
  fail(`shared/lower-level owner files changed but no decision package was provided: ${sharedFiles.join(', ')}`)
}

let passedPackageCount = 0
const checkerPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), 'check-decision-package.mjs')

for (const packageFile of packageFiles) {
  if (!fs.existsSync(packageFile)) {
    console.log(`FAIL: decision package does not exist: ${packageFile}`)
    continue
  }

  const result = runChecker(checkerPath, packageFile, changedFiles)
  if (result.ok) {
    passedPackageCount += 1
    console.log(`PASS: ${packageFile}`)
    continue
  }

  console.log(`FAIL: ${packageFile}`)
  console.log(result.output.trim())
}

if (passedPackageCount === 0) {
  fail(`shared/lower-level owner files changed but no decision package passed owner regression checks: ${sharedFiles.join(', ')}`)
}

pass(`shared/lower-level owner changes are covered by ${passedPackageCount} decision package(s).`)

function runChecker(checkerPath, packageFile, changedFiles) {
  try {
    const output = execFileSync(
      process.execPath,
      [
        checkerPath,
        '--mode',
        mode,
        '--changed-files',
        changedFiles.join(','),
        packageFile,
      ],
      {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      },
    )
    return { ok: true, output }
  } catch (error) {
    return {
      ok: false,
      output: `${error.stdout || ''}${error.stderr || ''}`,
    }
  }
}

function getPackageFiles() {
  const directPackages = getOptions('--package')
    .flatMap((value) => splitCsv(value))
    .map((value) => path.resolve(value))

  const packageDirs = getOptions('--packages-dir')
    .flatMap((value) => splitCsv(value))
    .map((value) => path.resolve(value))

  const discoveredPackages = packageDirs.flatMap((directory) => {
    if (!fs.existsSync(directory)) return []
    return fs.readdirSync(directory)
      .filter((name) => /\.md$/i.test(name))
      .map((name) => path.join(directory, name))
  })

  return unique([...directPackages, ...discoveredPackages])
}

function getChangedFiles() {
  const explicit = getOptions('--changed-files').flatMap((value) => splitCsv(value))
  if (explicit.length > 0) return unique(explicit)

  const envFiles = splitCsv(process.env.DECISION_PACKAGE_CHANGED_FILES || '')
  if (envFiles.length > 0) return unique(envFiles)

  return detectGitChangedFiles()
}

function detectGitChangedFiles() {
  try {
    const tracked = execFileSync('git', ['diff', '--name-only', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    const staged = execFileSync('git', ['diff', '--name-only', '--cached', 'HEAD'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    const untracked = execFileSync('git', ['ls-files', '--others', '--exclude-standard'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    return unique(splitLines(`${tracked}\n${staged}\n${untracked}`))
  } catch {
    return []
  }
}

function isSharedOwnerPath(file) {
  if (isDocumentPath(file)) return false
  if (isTestFilePath(file)) return false
  return SHARED_FILE_RE.test(file)
}

function isDocumentPath(file) {
  return /^(docs|openspec)\//i.test(file)
}

function isTestFilePath(file) {
  return /(^|\/)__tests__\/|\.test\.|\.spec\./i.test(file)
}

function getOption(name) {
  return getOptions(name)[0] || ''
}

function getOptions(name) {
  const values = []
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === name && args[index + 1]) {
      values.push(args[index + 1])
      index += 1
    }
  }
  return values
}

function splitCsv(value) {
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
}

function splitLines(value) {
  return value
    .split('\n')
    .map((item) => item.trim())
    .filter(Boolean)
}

function unique(values) {
  return [...new Set(values)]
}

function pass(message) {
  console.log(`PASS: ${message}`)
  process.exit(0)
}

function fail(message) {
  console.log(`FAIL: ${message}`)
  process.exit(1)
}

function runSelfTest() {
  if (!isSharedOwnerPath('src/api/request.tsx')) {
    throw new Error('self-test expected src/api/request.tsx to be shared')
  }
  if (!isSharedOwnerPath('src/auth.tsx')) {
    throw new Error('self-test expected src/auth.tsx to be shared')
  }
  if (isSharedOwnerPath('src/pages/login/LoginModal.tsx')) {
    throw new Error('self-test expected page component to be local')
  }
  console.log('PASS: self-test fixtures behaved as expected.')
}
