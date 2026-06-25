#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import { execSync } from 'node:child_process'

const USAGE = `
Usage:
  node check-decision-package.mjs [--mode pr-review|bugfix] [--no-require-changed-files] [--changed-files a.ts,b.ts] <decision-package.md>
  node check-decision-package.mjs --self-test

Checks a markdown decision package for:
  - Decision Table
  - Problem / Root Cause / Timeline or Inventory Summary
  - Evidence & Ownership
  - Owner/RP Coverage Matrix
  - shared owners named in Fix Strategy also appearing in the matrix
  - no Coverage Status=missing rows
  - changed shared-owner paths mapped to owner-level regression rows from --changed-files, env, or git diff
  - owner RP groups mapped to owner-level Regression Plan action rows
  - Regression Plan rows using explicit proof actions, not only preserve/保留

Changed files can be supplied with --changed-files, the
DECISION_PACKAGE_CHANGED_FILES environment variable, or git diff. Missing
changed-file input fails closed by default; use --no-require-changed-files only
for manual document-only checks with explicit residual risk.
`

const ACTION_RE =
  /^(Existing GREEN|Add old-GREEN|RED|Post-fix GREEN|N\/A)$/i
const SHARED_OWNER_RE =
  /\b(shared|owner|request|wrapper|hook|shared component|helper|generator|template|script|workflow|public API|API surface|lower-level|auth|config|queryClient|route|router|atom|type|store|permission|底层|共享|共享组件|封装|生成器|模板|脚本|公共)\b/i
const PRESERVE_ONLY_RE = /\b(preserve|keep|保留|保持|兼容|不变)\b/i
const VALID_MODES = new Set(['generic', 'pr-review', 'bugfix'])
const ASPIRATIONAL_RE =
  /\b(todo|tbd|later|planned|plan to|will|should|expected|intend|pending|未执行|待执行|计划|应该|将会|稍后)\b/i
const VALID_COVERAGE_STATUS_RE =
  /^(covered|owner-covered|owner covered|n\/a|not applicable)$/i
const SUBAGENT_ID_RE =
  /019[0-9a-f]{5}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i

const args = process.argv.slice(2)
const modeIndex = args.indexOf('--mode')
const mode = modeIndex === -1 ? 'generic' : args[modeIndex + 1]
const positionalArgs = args.filter((_, index) =>
  !isOptionToken(args, index)
)
const changedFileResult = getChangedFiles(args)
const changedFiles = changedFileResult.files
const requireChangedFiles = !args.includes('--no-require-changed-files')

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
  console.log(USAGE.trim())
  process.exit(args.length === 0 ? 1 : 0)
}

if (args[0] === '--self-test') {
  runSelfTest()
  process.exit(0)
}

const file = positionalArgs[0]
const markdown = fs.readFileSync(file, 'utf8')
const result = checkDecisionPackage(markdown, mode, {
  changedFiles,
  requireChangedFiles,
  changedFileSource: changedFileResult.source,
  evidenceBaseDir: path.dirname(path.resolve(file)),
})

for (const line of result.messages) {
  console.log(line)
}

if (!result.ok) {
  process.exit(1)
}

function checkDecisionPackage(markdown, mode = 'generic', options = {}) {
  const messages = []
  const changedFiles = options.changedFiles || []
  const requireChangedFiles = Boolean(options.requireChangedFiles)
  const changedFileSource = options.changedFileSource || 'none'
  const evidenceBaseDir = options.evidenceBaseDir || process.cwd()
  const changedSharedFiles = changedFiles.filter(isSharedOwnerPath)
  const normalized = markdown.replace(/\r\n/g, '\n')
  const sections = parseSections(normalized)
  let regressionDataRows = []

  if (!VALID_MODES.has(mode)) {
    messages.push(
      `FAIL: invalid mode "${mode}". Expected one of: generic, pr-review, bugfix.`,
    )
  }

  if (requireChangedFiles && changedFiles.length === 0) {
    messages.push(
      'FAIL: changed-file input is required by default, but none was provided or detected.',
    )
  }

  const bugfixContextSection = findSection(sections, /problem.*root cause.*timeline/i)
  const prContextSection = findSection(sections, /inventory summary/i)
  const decisionSection = findSection(sections, /decision table/i)
  const evidenceSection = findSection(sections, /evidence\s*&\s*ownership/i)
  const matrixSection = findSection(sections, /owner\/rp coverage matrix/i)
  const regressionSection = findSection(sections, /regression plan/i)
  const tddSection = findSection(
    sections,
    /tdd.*(commit|verification).*plan/i,
  )
  const reviewSection = findSection(
    sections,
    /(3|three).*review|subagent.*review/i,
  )
  const localCiSection = findSection(sections, /local\/ci gate design/i)
  const matrixRows = matrixSection
    ? parseMatrixRows(extractFirstTableRows(matrixSection.body))
    : []
  const sharedOwners = decisionSection
    ? extractSharedOwners(decisionSection.body)
    : []
  const sharedOrLowerLevelOwners = unique([
    ...sharedOwners.filter(isLikelySharedOwner),
    ...matrixRows
      .map((row) => row.owner)
      .filter(isLikelySharedOwner),
    ...changedSharedFiles,
  ])

  if (!decisionSection) {
    messages.push('FAIL: missing Decision Table section.')
  }

  if (
    (mode === 'bugfix' && !bugfixContextSection) ||
    (mode === 'pr-review' && !prContextSection) ||
    (mode === 'generic' && !bugfixContextSection && !prContextSection)
  ) {
    messages.push(
      'FAIL: missing required context section: Problem / Root Cause / Timeline for bugfix or Inventory Summary for PR review.',
    )
  }

  if (!matrixSection) {
    messages.push('FAIL: missing Owner/RP Coverage Matrix section.')
  }

  if (!evidenceSection) {
    messages.push('FAIL: missing Evidence & Ownership section.')
  }

  if (!regressionSection) {
    messages.push('FAIL: missing Regression Plan section.')
  }

  if (!tddSection) {
    messages.push('FAIL: missing TDD / Verification / Commit Plan section.')
  } else if (!hasTddPlanTable(tddSection.body)) {
    messages.push(
      'FAIL: TDD / Verification / Commit Plan must include an execution table with Sequence and Checks columns.',
    )
  } else if (mode === 'bugfix' && !hasBugfixTddTargets(tddSection.body)) {
    messages.push(
      'FAIL: bugfix TDD plan must include target test file and target test command.',
    )
  }

  if (decisionSection) {
    const decisionColumns = getFirstTableHeader(decisionSection.body)
    for (const requiredColumn of [
      'fix strategy',
      'regression plan',
      'evidence/owner',
      'action',
    ]) {
      if (!decisionColumns.includes(requiredColumn)) {
        messages.push(
          `FAIL: Decision Table must include ${requiredColumn} column.`,
        )
      }
    }

    for (const row of extractFirstTableRows(decisionSection.body).slice(1)) {
      const header = decisionColumns
      const actionIndex = header.indexOf('action')
      if (actionIndex !== -1 && !normalizeCell(row[actionIndex] || '')) {
        messages.push(`FAIL: Decision Table row has empty Action cell: ${row.join(' | ')}`)
      }
    }
  }

  if (matrixSection) {
    if (!/\|\s*Coverage Status\s*\|/i.test(matrixSection.body)) {
      messages.push(
        'FAIL: Owner/RP Coverage Matrix must include Coverage Status column.',
      )
    }

    if (matrixRows.length === 0) {
      messages.push('FAIL: Owner/RP Coverage Matrix must include at least one data row.')
    }

    const missingRows = matrixRows.filter((row) => /^missing$/i.test(row.status))
    const invalidStatusRows = matrixRows.filter(
      (row) => !VALID_COVERAGE_STATUS_RE.test(row.status),
    )
    const incompleteRows = matrixRows.filter(
      (row) => !normalizeCell(row.owner) || !normalizeCell(row.rpGroup),
    )

    for (const row of incompleteRows) {
      messages.push(
        `FAIL: Owner/RP Coverage Matrix rows must include non-empty Owner / Surface and RP Group: ${row.raw.join(' | ')}`,
      )
    }

    for (const row of missingRows) {
      messages.push(
        `FAIL: Owner/RP Coverage Matrix has missing coverage: ${row.raw.join(' | ')}`,
      )
    }

    for (const row of invalidStatusRows.filter((row) => !/^missing$/i.test(row.status))) {
      messages.push(
        `FAIL: Owner/RP Coverage Matrix Coverage Status must be covered or N/A, not "${row.status || '(blank)'}": ${row.raw.join(' | ')}`,
      )
    }
  }

  if (decisionSection && matrixSection) {
    for (const owner of sharedOwners) {
      if (!matrixRows.some((row) => rowMentionsOwner(row.owner, owner))) {
        messages.push(
          `FAIL: Fix Strategy names shared owner "${owner}" but it is absent from Owner/RP Coverage Matrix.`,
        )
      }
    }

    for (const changedFile of changedSharedFiles) {
      if (!matrixRows.some((row) => rowMentionsChangedPath(row.owner, changedFile))) {
        messages.push(
          `FAIL: changed shared owner path "${changedFile}" is absent from Owner/RP Coverage Matrix.`,
        )
      }
    }
  }

  if (regressionSection) {
    regressionDataRows = extractRegressionActionRows(regressionSection.body)

    const actionRows = regressionDataRows.filter((row) =>
      ACTION_RE.test(row.action),
    )

    if (actionRows.length === 0) {
      messages.push(
        'FAIL: Regression Plan must include explicit action rows: Existing GREEN / Add old-GREEN / RED / Post-fix GREEN / N/A.',
      )
    }

    if (
      mode === 'bugfix' &&
      !regressionDataRows.some((row) => /^RED$/i.test(row.action))
    ) {
      messages.push('FAIL: bugfix Regression Plan must include a bug RED action row.')
    }

    for (const row of regressionDataRows) {
      const joined = row.action || row.text
      if (ACTION_RE.test(row.action)) continue

      if (PRESERVE_ONLY_RE.test(joined)) {
        messages.push(
          `FAIL: Regression Plan row uses preserve/保留 language without an explicit action: ${row.cells.join(' | ')}`,
        )
      } else {
        messages.push(
          `FAIL: Regression Plan row lacks explicit action: ${row.cells.join(' | ')}`,
        )
      }
    }

    for (const row of regressionDataRows.filter((row) => ACTION_RE.test(row.action))) {
      const proofMessage = validateRegressionProof(row)
      if (proofMessage) {
        messages.push(proofMessage)
      }
    }
  }

  if (matrixSection && regressionSection) {
    for (const matrixRow of matrixRows) {
      if (/^missing$/i.test(matrixRow.status)) continue

      const matchingRows = regressionDataRows.filter((row) =>
        row.text.includes(matrixRow.rpGroup),
      )

      if (matchingRows.length === 0) {
        messages.push(
          `FAIL: shared owner "${matrixRow.owner}" uses ${matrixRow.rpGroup} in matrix but has no matching Regression Plan row.`,
        )
        continue
      }

      if (!isLikelySharedOwner(matrixRow.owner)) {
        continue
      }

      const ownerCovered = matchingRows.some(
        (row) =>
          isOwnerCoverageAction(row) && hasOwnerLevelSignal(row, matrixRow.owner),
      )

      if (!ownerCovered) {
        messages.push(
          `FAIL: shared owner "${matrixRow.owner}" has ${matrixRow.rpGroup} Regression Plan rows, but none look owner-level with an explicit action.`,
        )
      }
    }
  }

  if (sharedOrLowerLevelOwners.length > 0) {
    if (changedFiles.length === 0) {
      messages.push(
        'FAIL: shared/lower-level owner packages must run checker with --changed-files or detectable git changed files so shared paths cannot be hidden by wording.',
      )
    } else if (changedFileSource === 'git') {
      messages.push(
        'PASS: changed files were detected from git diff for shared/lower-level owner checks.',
      )
    }

    if (!reviewSection || !hasThreeCleanReviews(reviewSection.body, evidenceBaseDir)) {
      messages.push(
        'FAIL: shared/lower-level owner decision package must include 3-Reviewer Regression Plan Review with at least three rows and Missing Owner Count=0.',
      )
    }

    if (!localCiSection || !hasLocalCiGateDesign(localCiSection.body)) {
      messages.push(
        'FAIL: shared/lower-level owner decision package must include Local/CI Gate Design with a concrete detector/gate/hook and checker command.',
      )
    }
  }

  if (messages.length === 0) {
    messages.push('PASS: decision package structure looks complete.')
  }

  return {
    ok: messages.every((line) => line.startsWith('PASS')),
    messages,
  }
}

function parseSections(markdown) {
  const lines = markdown.split('\n')
  const sections = []
  let current = { level: 0, heading: '(root)', body: '', startIndex: 0 }

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    const heading = /^(#{1,6})\s+(.+?)\s*$/.exec(line)
    if (heading) {
      if (current.heading !== '(root)') {
        current.body = collectSectionBody(lines, current.startIndex, current.level)
      }
      sections.push(current)
      current = {
        level: heading[1].length,
        heading: heading[2],
        body: '',
        startIndex: index + 1,
      }
      continue
    }
  }

  if (current.heading !== '(root)') {
    current.body = collectSectionBody(lines, current.startIndex, current.level)
  }
  sections.push(current)
  return sections
}

function collectSectionBody(lines, startIndex, level) {
  let body = ''
  for (let index = startIndex; index < lines.length; index += 1) {
    const nextHeading = /^(#{1,6})\s+/.exec(lines[index])
    if (nextHeading && nextHeading[1].length <= level) break
    body += `${lines[index]}\n`
  }
  return body
}

function findSection(sections, pattern) {
  return sections.find((section) => pattern.test(section.heading))
}

function extractTableRows(text) {
  return text
    .split('\n')
    .filter((line) => /^\s*\|.*\|\s*$/.test(line))
    .filter((line) => !/^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line))
    .map((line) =>
      line
        .trim()
        .replace(/^\|/, '')
        .replace(/\|$/, '')
        .split('|')
        .map((cell) => cell.trim()),
    )
}

function extractFirstTableRows(text) {
  const tableLines = []
  let inTable = false

  for (const line of text.split('\n')) {
    if (/^\s*\|.*\|\s*$/.test(line)) {
      inTable = true
      tableLines.push(line)
      continue
    }

    if (inTable) break
  }

  return extractTableRows(tableLines.join('\n'))
}

function extractTables(text) {
  const tables = []
  let current = []

  for (const line of text.split('\n')) {
    if (/^\s*\|.*\|\s*$/.test(line)) {
      current.push(line)
      continue
    }

    if (current.length > 0) {
      tables.push(extractTableRows(current.join('\n')))
      current = []
    }
  }

  if (current.length > 0) {
    tables.push(extractTableRows(current.join('\n')))
  }

  return tables.filter((table) => table.length > 0)
}

function extractSharedOwners(decisionBody) {
  const rows = extractTableRows(decisionBody)
  if (rows.length === 0) return []

  const header = rows[0].map((cell) => cell.toLowerCase())
  const fixIndex = header.findIndex((cell) => cell === 'fix strategy')
  if (fixIndex === -1) return []

  const owners = new Set()

  for (const row of rows.slice(1)) {
    const strategy = row[fixIndex] || ''
    const backtickOwners = [...strategy.matchAll(/`([^`]+)`/g)]
      .map((match) => match[1].trim())
      .filter(Boolean)
    const pathLikeOwners = backtickOwners.filter(isSharedOwnerPath)

    if (!SHARED_OWNER_RE.test(strategy) && pathLikeOwners.length === 0) continue
    const rowOwners = new Set()

    for (const owner of backtickOwners) {
      if (isLocalPagePath(owner)) continue
      rowOwners.add(owner)
    }

    const proseOwnerRe =
      /\b(?:shared|request|public|lower-level)\s+(?:request\s+)?(?:wrapper|hook|component|helper|contract|generator|template|script|workflow(?:\s+gate)?|api(?:\s+surface)?)\s+([A-Za-z0-9_./-]+)/gi

    for (const match of strategy.matchAll(proseOwnerRe)) {
      rowOwners.add(match[1].trim())
    }

    if (!strategy.includes('`') && rowOwners.size === 0) {
      const phrase = strategy
        .split(/[;,.，。]/)[0]
        .replace(/\b(change|update|modify|move|use|fix|refactor|调整|修改|下沉|复用|修复)\b/gi, '')
        .trim()
      if (phrase) rowOwners.add(phrase)
    }

    for (const owner of rowOwners) {
      owners.add(owner)
    }
  }

  return [...owners]
}

function parseMatrixRows(rows) {
  if (rows.length < 2) return []

  const header = rows[0].map((cell) => cell.toLowerCase())
  const ownerIndex = header.findIndex((cell) => /owner|surface/.test(cell))
  const groupIndex = header.findIndex((cell) => /rp group/.test(cell))
  const statusIndex = header.findIndex((cell) => /coverage status/.test(cell))

  if (ownerIndex === -1 || groupIndex === -1 || statusIndex === -1) {
    return []
  }

  return rows.slice(1).map((row) => ({
    owner: row[ownerIndex] || '',
    rpGroup: row[groupIndex] || '',
    status: normalizeCell(row[statusIndex] || ''),
    raw: row,
  }))
}

function rowMentionsOwner(row, owner) {
  const normalizedRow = row.toLowerCase()
  const tokens = owner
    .replace(/`/g, '')
    .split(/[^A-Za-z0-9_-]+/)
    .map((token) => token.trim().toLowerCase())
    .filter((token) => token.length >= 3)
    .filter((token) => !/^(the|and|public|api|surface|changed|strategy|owner|request|wrapper|helper|component|hook|script|workflow)$/.test(token))

  if (tokens.length === 0) return false

  return tokens.every((token) =>
    new RegExp(`(^|[^a-z0-9_-])${escapeRegExp(token)}([^a-z0-9_-]|$)`, 'i').test(
      normalizedRow,
    ),
  )
}

function extractRegressionActionRows(text) {
  const actionTables = extractTables(text).filter((table) => {
    const tableText = table.flat().join(' ')
    return (
      /regression action/i.test(tableText) ||
        /\b(Existing GREEN|Add old-GREEN|RED|Post-fix GREEN|N\/A)\b/.test(tableText) ||
      PRESERVE_ONLY_RE.test(tableText)
    )
  })

  return actionTables.flatMap((table) => {
    const header = table[0].map((cell) => cell.toLowerCase())
    const actionIndex = header.findIndex((cell) => /regression action/.test(cell))
    return table.slice(1)
      .filter((row) => row.length > 1)
      .filter((row) => !row.some((cell) => /regression action/i.test(cell)))
      .map((row) => ({
        cells: row,
        header,
        action: normalizeCell(actionIndex === -1 ? '' : row[actionIndex] || ''),
        text: row.join(' '),
      }))
  })
}

function hasOwnerLevelSignal(row, owner) {
  if (/\b(callers?|call site|page[- ]?only|caller[- ]?only|page[- ]?level|only through|调用方|页面级)\b/i.test(row.text)) {
    return false
  }

  const ownerIndex = row.header.findIndex((cell) =>
    /owner|surface/.test(cell),
  )
  if (ownerIndex === -1 || !rowMentionsOwner(row.cells[ownerIndex] || '', owner)) {
    return false
  }

  const scopeIndex = row.header.findIndex((cell) =>
    /regression scope|scope|test level/.test(cell),
  )
  if (scopeIndex !== -1 && /owner[- ]level|shared owner|owner/.test(normalizeCell(row.cells[scopeIndex]).toLowerCase())) {
    return true
  }

  return /owner[- ]level|shared owner|owner/.test(row.text)
}

function hasThreeCleanReviews(text, evidenceBaseDir) {
  const tables = extractTables(text)
  const reviewTable = tables.find((table) => {
    const header = table[0].join(' ').toLowerCase()
    return /reviewer/.test(header) && /missing owner count/.test(header)
  })

  if (!reviewTable || reviewTable.length < 4) {
    return false
  }

  const header = reviewTable[0].map((cell) => cell.toLowerCase())
  const reviewerIndex = header.findIndex((cell) => /reviewer/.test(cell))
  const sourceIndex = header.findIndex((cell) => /source|session|agent/.test(cell))
  const countIndex = header.findIndex((cell) => /missing owner count/.test(cell))
  const notesIndex = header.findIndex((cell) => /notes|check/.test(cell))
  const evidenceIndex = header.findIndex((cell) => /^evidence$|review evidence|completion evidence/.test(cell))
  if (reviewerIndex === -1 || sourceIndex === -1 || countIndex === -1 || notesIndex === -1 || evidenceIndex === -1) return false

  const reviewerNames = reviewTable
    .slice(1)
    .map((row) => normalizeCell(row[reviewerIndex] || '').toLowerCase())
    .filter(Boolean)

  if (new Set(reviewerNames).size < 3) return false

  const sourceValues = reviewTable
    .slice(1)
    .map((row) => normalizeCell(row[sourceIndex] || '').toLowerCase())
    .filter(Boolean)

  if (new Set(sourceValues).size < 3) return false

  const notesValues = reviewTable
    .slice(1)
    .map((row) => normalizeCell(row[notesIndex] || '').toLowerCase())

  if (new Set(notesValues).size < 3) return false

  return reviewTable.slice(1).every((row) => {
    const source = normalizeCell(row[sourceIndex] || '')
    const notes = normalizeCell(row[notesIndex] || '')
    const evidence = normalizeCell(row[evidenceIndex] || '')
    return (
      normalizeCell(row[countIndex] || '') === '0' &&
      SUBAGENT_ID_RE.test(source) &&
      hasReviewEvidenceFile(evidence, source, evidenceBaseDir) &&
      notes.length > 3 &&
      notes !== '-' &&
      /owner/i.test(notes) &&
      /caller/i.test(notes) &&
      /\b(RP-\d+[A-Z]?|rp group|matrix)\b/i.test(notes) &&
      /(first|action)/i.test(notes) &&
      !/\b(manual|not independent|not actual|same reviewer|placeholder|tbd|todo)\b/i.test(notes)
    )
  })
}

function hasReviewEvidenceFile(evidence, source, evidenceBaseDir) {
  const evidencePath = evidence
    .replace(/^file:/i, '')
    .replace(/^\[(.*?)\]\((.*?)\)$/, '$2')
    .trim()
  if (!evidencePath || /subagent_?notification|agent_?path/i.test(evidencePath)) {
    return false
  }

  const absolutePath = path.isAbsolute(evidencePath)
    ? evidencePath
    : path.resolve(evidenceBaseDir, evidencePath)
  if (!fs.existsSync(absolutePath)) return false

  const content = fs.readFileSync(absolutePath, 'utf8')
  return (
    content.includes(source) &&
    /subagent_notification|agent_path/i.test(content) &&
    /\bno blockers?\b/i.test(content)
  )
}

function hasLocalCiGateDesign(text) {
  const hasCommand =
    /\bCommand:\s*`?(node|pnpm|npm|yarn|bun)\b(?=.*\bcheck-decision-package\b)(?=.*--changed-files)(?!.*--no-require-changed-files)/i.test(text)
  const hasDetectorOrGate =
    hasConcreteDetector(text)
  const hasFailureRule =
    /\b(fail|fails|failure|block|gate|拒绝|阻断|失败)\b/i.test(text) &&
      /\b(shared owner|owner\/rp|matrix|coverage status|caller-level|changed-files|底层|共享)\b/i.test(text)
  return hasCommand && hasDetectorOrGate && hasFailureRule
}

function hasConcreteDetector(text) {
  const detectorLine = text
    .split('\n')
    .find((line) => /^\s*(Detector|Hook|Gate):/i.test(line))
  if (!detectorLine) return false
  if (/\b(path or command|repo-specific|example|placeholder|TBD|TODO|N\/A)\b|<[^>]+>/i.test(detectorLine)) {
    return false
  }
  const command = /`([^`]+)`/.exec(detectorLine)?.[1] || ''
  if (!command) return false
  if (/\bgit\s+diff\b/.test(command)) return true
  const detectorPath = command
    .split(/\s+/)
    .find((part) => /^(scripts\/|\.\/|\/).*\.(mjs|js|ts|sh)$/.test(part))
  if (!detectorPath) return false
  return fs.existsSync(path.resolve(process.cwd(), detectorPath))
}

function getFirstTableHeader(text) {
  const rows = extractFirstTableRows(text)
  return rows.length === 0
    ? []
    : rows[0].map((cell) => cell.toLowerCase())
}

function hasTddPlanTable(text) {
  return getTddPlanRows(text).length > 0
}

function hasBugfixTddTargets(text) {
  return getTddPlanRows(text).some(({ headerCells, row }) => {
    const fileIndex = headerCells.findIndex((cell) => /target test file/.test(cell))
    const commandIndex = headerCells.findIndex((cell) => /target test command/.test(cell))
    if (fileIndex === -1 || commandIndex === -1) return false
    const file = normalizeCell(row[fileIndex] || '')
    const command = normalizeCell(row[commandIndex] || '')
    return (
      /\.(test|spec)\.(ts|tsx|js|jsx|mjs)$/.test(file) &&
      /\b(pnpm|npm|yarn|bun|vitest|jest|playwright|test)\b/i.test(command)
    )
  })
}

function getTddPlanRows(text) {
  return extractTables(text).flatMap((table) => {
    const headerCells = table[0].map((cell) => cell.toLowerCase())
    const header = headerCells.join(' ')
    const sequenceIndex = headerCells.findIndex((cell) => /sequence/.test(cell))
    const checksIndex = headerCells.findIndex((cell) => /checks/.test(cell))
    const hasRequiredHeader =
      sequenceIndex !== -1 &&
      checksIndex !== -1 &&
      /(commit plan|reply target|target test|target command|verification)/.test(header)

    if (!hasRequiredHeader) return []

    return table
      .slice(1)
      .filter((row) =>
        cellHasConcretePlan(row[sequenceIndex] || '') &&
          cellHasConcretePlan(row[checksIndex] || ''),
      )
      .map((row) => ({ headerCells, row }))
  })
}

function validateRegressionProof(row) {
  const proofIndex = row.header.findIndex((cell) => /test|proof|reason/.test(cell))
  const proof = normalizeCell(proofIndex === -1 ? '' : row.cells[proofIndex] || '')

  if (!proof || proof === '-') {
    return `FAIL: Regression Plan row with action "${row.action}" lacks Test / Proof detail: ${row.cells.join(' | ')}`
  }

  if (!/^Add old-GREEN$/i.test(row.action) && ASPIRATIONAL_RE.test(proof)) {
    return `FAIL: Regression Plan proof is aspirational, not executed evidence: ${row.cells.join(' | ')}`
  }

  if (/^Existing GREEN$/i.test(row.action) && !hasCommandResultAndCount(proof)) {
    return `FAIL: Existing GREEN row must include baseline command/result proof: ${row.cells.join(' | ')}`
  }

  if (
    /^Add old-GREEN$/i.test(row.action) &&
    !hasAddOldGreenProof(proof)
  ) {
    return `FAIL: Add old-GREEN row must include characterization plan or executed old-GREEN proof: ${row.cells.join(' | ')}`
  }

  if (/^RED$/i.test(row.action) && !/(red|fail|fails|failing|failed|before fix|pre-fix|修复前)/i.test(proof)) {
    return `FAIL: RED row must describe the failing pre-fix proof: ${row.cells.join(' | ')}`
  }

  if (/^Post-fix GREEN$/i.test(row.action) && !hasCommandResultAndCount(proof)) {
    return `FAIL: Post-fix GREEN row must include post-fix proof: ${row.cells.join(' | ')}`
  }

  if (/^N\/A$/i.test(row.action) && !hasSubstituteEvidence(proof)) {
    return `FAIL: N/A Regression Plan row must include a reason: ${row.cells.join(' | ')}`
  }

  return ''
}

function isOwnerCoverageAction(row) {
  if (!ACTION_RE.test(row.action)) return false
  if (!/^N\/A$/i.test(row.action)) return true

  const proofIndex = row.header.findIndex((cell) => /test|proof|reason/.test(cell))
  const proof = normalizeCell(proofIndex === -1 ? '' : row.cells[proofIndex] || '')
  return hasSubstituteEvidence(proof)
}

function hasSubstituteEvidence(proof) {
  return (
    /\b(reason|substitute|evidence|not applicable|manual|不适用|替代|证据)\b/i.test(proof) &&
    !/\b(no owner regression plan|none|without evidence|无|没有)\b/i.test(proof)
  )
}

function isLikelySharedOwner(owner) {
  const normalized = owner.toLowerCase()
  if (isCallerOwner(owner)) return false
  if (isLocalPagePath(normalized)) return false
  return (
    SHARED_OWNER_RE.test(owner) ||
    /\b(get|post|put|del|request|auth|config|wrapper|hook|shared component|helper|generator|template|script|workflow)\b/.test(normalized)
  )
}

function isSharedOwnerPath(file) {
  return /(^|\/)(api\/request|src\/api\/request|hooks?|components?|utils?|helpers?|scripts?|workflow|templates?|generator|config|auth|queryClient|routes?|atoms?|types?|permissions?|router|store)\b/i.test(file)
}

function isLocalPagePath(value) {
  return /(^|\/)(src\/)?pages?\//i.test(value)
}

function rowMentionsChangedPath(row, file) {
  const normalizedFile = file.replace(/^.*?src\//, 'src/').toLowerCase()
  const basename = normalizedFile.split('/').pop()?.replace(/\.[^.]+$/, '') || normalizedFile
  return rowMentionsOwner(row, normalizedFile) || rowMentionsOwner(row, basename)
}

function cellHasConcretePlan(cell) {
  const normalized = normalizeCell(cell)
  return Boolean(normalized) && !/^(TBD|TODO|N\/A|-)$/.test(normalized)
}

function hasCommandResultAndCount(proof) {
  return (
    /\b(pnpm|npm|yarn|bun|vitest|jest|playwright|test)\b/i.test(proof) &&
    /\b(pass|passes|passed|green|ok)\b/i.test(proof) &&
    /(\d+\s*\/\s*\d+|\d+\s+(tests?|passed|pass|passes)|all\s+\d+)/i.test(proof)
  )
}

function hasAddOldGreenProof(proof) {
  const namesCharacterization =
    /(old-green|characterization|regression|回归|表征)/i.test(proof)
  if (!namesCharacterization) return false
  return (
    hasCommandResultAndCount(proof) ||
    /\b(target|planned command|command|test file|before RED|before production|first action|approval后|批准后|先补|先执行)\b/i.test(proof)
  )
}

function getChangedFiles(args) {
  const changedFilesIndex = args.indexOf('--changed-files')
  const raw =
    changedFilesIndex === -1
      ? process.env.DECISION_PACKAGE_CHANGED_FILES || ''
      : args[changedFilesIndex + 1] || ''
  const explicitFiles = raw
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
  if (explicitFiles.length > 0) {
    return {
      files: explicitFiles,
      source: changedFilesIndex === -1 ? 'env' : 'args',
    }
  }

  const gitFiles = detectGitChangedFiles()
  return {
    files: gitFiles,
    source: gitFiles.length > 0 ? 'git' : 'none',
  }
}

function detectGitChangedFiles() {
  try {
    const output = execSync(
      'git diff --name-only HEAD && git diff --name-only --cached HEAD',
      {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      },
    )
    const untracked = execSync('git ls-files --others --exclude-standard', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    return unique(
      `${output}\n${untracked}`
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean),
    )
  } catch {
    return []
  }
}

function isOptionToken(args, index) {
  const value = args[index]
  const previous = args[index - 1]
  return (
    value === '--mode' ||
    previous === '--mode' ||
    value === '--changed-files' ||
    previous === '--changed-files' ||
    value === '--require-changed-files' ||
    value === '--no-require-changed-files'
  )
}

function isCallerOwner(owner) {
  return /^(caller|page|call site|调用方|页面)/i.test(owner.toLowerCase())
}

function unique(values) {
  return [...new Set(values.filter(Boolean))]
}

function normalizeCell(cell) {
  return cell
    .replace(/[`*_]/g, '')
    .trim()
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function runSelfTest() {
  const evidenceBaseDir = fs.mkdtempSync('/tmp/decision-package-self-test-')
  fs.mkdirSync(path.join(evidenceBaseDir, 'evidence'))
  for (const id of [
    '019aaa11-1111-4111-8111-111111111111',
    '019bbb22-2222-4222-8222-222222222222',
    '019ccc33-3333-4333-8333-333333333333',
  ]) {
    fs.writeFileSync(
      path.join(evidenceBaseDir, 'evidence', `${id}.json`),
      JSON.stringify({
        subagent_notification: true,
        agent_path: id,
        status: {
          completed: 'no blockers',
        },
      }),
    )
  }

  const good = `
## Problem / Root Cause / Timeline
Shared request wrapper needs owner-level regression planning.

## Decision Table
| # | Review Item | Verdict | Fix Strategy | Regression Plan | Evidence/Owner | Action |
|---|---|---|---|---|---|---|
| 1 | temp auth | Real bug | change shared request wrapper \`get/post\` | RP-1 | EO-1 | TDD-1 |

## Evidence & Ownership
| Ref | Evidence | Owner Layer |
|---|---|---|
| EO-1 | reachable | request wrapper |

## Regression Plan
### Owner/RP Coverage Matrix
| Decision | Owner / Surface Changed By Fix Strategy | RP Group | Coverage Status |
|---|---|---|---|
| #1 | src/api/request.tsx get/post | RP-1A | covered |

| Ref | Owner / Surface | Regression Scope | Behavior | Current Coverage | Regression Action | Test / Proof |
|---|---|---|---|---|---|---|
| RP-1A | src/api/request.tsx get/post | owner-level | get/post old request behavior | covered | Existing GREEN | \`pnpm test request.test.ts\` passed 4 tests |
| RP-1B | login page | caller | new auth header behavior | missing | RED | fails first |

## 3-Reviewer Regression Plan Review
| Reviewer | Source | Missing Owner Count | Evidence | Notes |
|---|---|---:|---|---|
| A | 019aaa11-1111-4111-8111-111111111111 | 0 | evidence/019aaa11-1111-4111-8111-111111111111.json | RP-1A owner coverage, caller-only masking, first action checked |
| B | 019bbb22-2222-4222-8222-222222222222 | 0 | evidence/019bbb22-2222-4222-8222-222222222222.json | RP-1A owner matrix, caller masking, first action reviewed |
| C | 019ccc33-3333-4333-8333-333333333333 | 0 | evidence/019ccc33-3333-4333-8333-333333333333.json | RP-1A owner rows, caller-only gaps, first code action verified |

## Local/CI Gate Design
Command: \`node <skill-dir>/scripts/check-decision-package.mjs --mode bugfix --changed-files src/api/request.tsx docs/plans/password.md\`.
Detector: \`git diff --name-only HEAD\` supplies changed files for Owner/RP matrix checks.
Gate: fail when changed-files names a shared owner with no Owner/RP matrix row, missing coverage, or caller-level-only regression.

## TDD / Verification / Commit Plan
| Ref | Sequence | Target Test File | Target Test Command | Commit Plan | Checks |
|---|---|---|---|---|---|
| TDD-1 | Existing GREEN -> RED -> fix -> GREEN | src/api/__tests__/request.test.ts | pnpm test src/api/__tests__/request.test.ts | fix(auth): example | focused + check:task |
`

  const bad = `
## Decision Table
| # | Review Item | Verdict | Fix Strategy |
|---|---|---|---|
| 1 | temp auth | Real bug | change shared request wrapper \`get/post\` |

## Regression Plan
| Ref | Behavior | Plan |
|---|---|---|
| RP-1 | preserve old behavior | preserve |
`

  const mixedOwnerBad = `
## Decision Table
| # | Review Item | Verdict | Fix Strategy | Regression Plan | Evidence/Owner | Action |
|---|---|---|---|---|---|---|
| 1 | auth cleanup | Real bug | change shared wrapper \`get/post\` and shared hook useAuthSuccess | RP-1 | EO-1 | TDD-1 |

## Evidence & Ownership
| Ref | Evidence | Owner Layer |
|---|---|---|
| EO-1 | reachable | shared owners |

## Regression Plan
### Owner/RP Coverage Matrix
| Decision | Owner / Surface Changed By Fix Strategy | RP Group | Coverage Status |
|---|---|---|---|
| #1 | get/post | RP-1A | covered |

### Regression Actions
| Ref | Behavior | Current Coverage | Regression Action | Test / Proof |
|---|---|---|---|---|
| RP-1A | get/post request behavior | covered | Existing GREEN | \`pnpm test request.test.ts\` passed 4 tests |
`

  const markdownMissingBad = `
## Decision Table
| # | Review Item | Verdict | Fix Strategy | Regression Plan | Evidence/Owner | Action |
|---|---|---|---|---|---|---|
| 1 | auth cleanup | Real bug | change shared wrapper \`get/post\` | RP-1 | EO-1 | TDD-1 |

## Evidence & Ownership
| Ref | Evidence | Owner Layer |
|---|---|---|
| EO-1 | reachable | shared owners |

## Regression Plan
### Owner/RP Coverage Matrix
| Decision | Owner / Surface Changed By Fix Strategy | RP Group | Coverage Status |
|---|---|---|---|
| #1 | get/post | RP-1A | \`missing\` |

### Regression Actions
| Ref | Behavior | Current Coverage | Regression Action | Test / Proof |
|---|---|---|---|---|
| RP-1A | get/post request behavior | covered | Existing GREEN | \`pnpm test request.test.ts\` passed 4 tests |
`

  const goodResult = checkDecisionPackage(good, 'bugfix', {
    changedFiles: ['src/api/request.tsx'],
    requireChangedFiles: true,
    evidenceBaseDir,
  })
  const badResult = checkDecisionPackage(bad)
  const mixedOwnerBadResult = checkDecisionPackage(mixedOwnerBad)
  const markdownMissingBadResult = checkDecisionPackage(markdownMissingBad)

  if (!goodResult.ok) {
    throw new Error(`self-test good fixture failed:\n${goodResult.messages.join('\n')}`)
  }

  if (badResult.ok) {
    throw new Error('self-test bad fixture unexpectedly passed')
  }

  if (mixedOwnerBadResult.ok) {
    throw new Error('self-test mixed-owner bad fixture unexpectedly passed')
  }

  if (markdownMissingBadResult.ok) {
    throw new Error('self-test markdown-missing bad fixture unexpectedly passed')
  }

  console.log('PASS: self-test fixtures behaved as expected.')
}
