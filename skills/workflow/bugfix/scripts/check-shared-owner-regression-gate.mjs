/* v8 ignore start -- CLI behavior is covered by spawned decision-package gate tests. */

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
  /^(package\.json$|[^/]+\.config\.(?:js|cjs|mjs|ts|mts|cts)$|tsconfig[^/]*\.json$|src\/(App|main)\.tsx$|src\/api\/(request|responseFeedback|index\.tsx$)|api\/request|src\/(hooks?|components?|utils?|helpers?|config|auth|queryClient|routes?|atoms?|types?|permissions?|router|store)\b|(hooks?|components?|utils?|helpers?|config|auth|queryClient|routes?|atoms?|types?|permissions?|router|store)\b|scripts?\/|\.github\/workflows?\/|workflows?\/|templates?\/|generator(\/|$))/i

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

const checkerPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), 'check-decision-package.mjs')
const missingPackageResults = []
const invalidClaimResults = []

for (const packageFile of packageFiles) {
  if (!fs.existsSync(packageFile)) {
    missingPackageResults.push({
      packageFile,
      output: `FAIL: decision package does not exist: ${packageFile}`,
    })
  }
}

const coveredPackageFiles = new Set()
const uncoveredSharedFiles = sharedFiles.filter((sharedFile) =>
  !packageFiles.some((packageFile) => {
    if (!fs.existsSync(packageFile)) return false
    const result = runChecker(checkerPath, packageFile, [sharedFile])
    if (result.ok) {
      coveredPackageFiles.add(packageFile)
      return true
    }
    if (hasOwnerCoverage(packageFile, sharedFile)) {
      invalidClaimResults.push({
        packageFile,
        sharedFile,
        output: result.output,
      })
    }
    return false
  }),
)

if (invalidClaimResults.length > 0) {
  for (const result of invalidClaimResults) {
    console.log(`FAIL: ${result.packageFile}`)
    console.log(`Changed shared owner: ${result.sharedFile}`)
    console.log(result.output.trim())
  }
  fail(
    `decision package checker failed for packages that claimed shared-owner coverage: ${
      unique(invalidClaimResults.map((result) => result.packageFile)).join(', ')
    }`,
  )
}

if (uncoveredSharedFiles.length === 0) {
  const coveredCount = coveredPackageFiles.size
  if (coveredCount === 1) {
    pass('shared/lower-level owner changes are covered by 1 decision package(s).')
  }
  pass('shared/lower-level owner changes are covered by decision packages.')
}

for (const result of missingPackageResults) {
  console.log(`FAIL: ${result.packageFile}`)
  console.log(result.output.trim())
}

fail(`shared/lower-level owner files changed but no decision package covered every owner: ${uncoveredSharedFiles.join(', ')}`)

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

function hasOwnerCoverage(packageFile, sharedFile) {
  const markdown = fs.readFileSync(packageFile, 'utf8')
  const rpGroups = markdown
    .split('\n')
    .filter((line) =>
      /^\s*\|/.test(line) && rowMentionsChangedPath(line, sharedFile),
    )
    .flatMap((line) => [...line.matchAll(/\bRP-[A-Za-z0-9_-]+\b/g)])
    .map((match) => match[0])

  return unique(rpGroups).some((rpGroup) =>
    markdown
      .split('\n')
      .filter((line) => line.includes(rpGroup))
      .some((line) =>
        rowMentionsChangedPath(line, sharedFile) &&
          /\b(Existing GREEN|Add old-GREEN|RED|Post-fix GREEN|N\/A)\b/i.test(line) &&
          /\b(owner[- ]level|shared owner|owner)\b/i.test(line) &&
          !/\b(callers?|call site|page[- ]?only|caller[- ]?only|page[- ]?level|only through|调用方|页面级)\b/i.test(line),
      ),
  )
}

function rowMentionsChangedPath(row, file) {
  const normalizedFile = file.replace(/^.*?src\//, 'src/').toLowerCase()
  return extractPathTokens(row).includes(normalizedFile)
}

function extractPathTokens(text) {
  return text
    .replace(/`/g, '')
    .replace(/\\/g, '/')
    .toLowerCase()
    .split(/[^a-z0-9_./-]+/)
    .filter(Boolean)
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

  const changedPackages = changedFiles
    .filter((file) => /^docs\/plans\/.*\.md$/i.test(file))
    .map((file) => path.resolve(file))

  return unique([...directPackages, ...discoveredPackages, ...changedPackages])
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
  if (!isSharedOwnerPath('src/api/responseFeedback.ts')) {
    throw new Error('self-test expected src/api/responseFeedback.ts to be shared')
  }
  if (!isSharedOwnerPath('src/auth.tsx')) {
    throw new Error('self-test expected src/auth.tsx to be shared')
  }
  if (!isSharedOwnerPath('package.json')) {
    throw new Error('self-test expected package.json to be shared')
  }
  if (!isSharedOwnerPath('vite.config.ts')) {
    throw new Error('self-test expected vite.config.ts to be shared')
  }
  if (!isSharedOwnerPath('tsconfig.json')) {
    throw new Error('self-test expected tsconfig.json to be shared')
  }
  if (isSharedOwnerPath('src/pages/login/LoginModal.tsx')) {
    throw new Error('self-test expected page component to be local')
  }
  console.log('PASS: self-test fixtures behaved as expected.')
}
