<!-- Copy this section into your project's AGENTS.md -->

## GIT WORKFLOW (AI-ASSISTED)

### ⛔ Pre-Implementation Gate (MANDATORY)

**Before ANY code change, classify the task and load the corresponding skill. No exceptions.**

```
Count files that will change
        │
        ▼
   1 file only? ──yes──▶ Work directly on current branch (no skill needed)
        │
       no (2+ files)
        │
        ▼
   Need main & feature    ──yes──▶ Load skill: wf-worktree-workflow
   in parallel? Or will
   span multiple sessions?
        │
       no
        │
        ▼
   Load skill: wf-branch-workflow
   (branch + plan, no worktree)
```

**BLOCKING — you MUST load one of these skills before touching code. The skill guides the rest.**

| Scenario                            | Skill                  | Example                                   |
| ----------------------------------- | ---------------------- | ----------------------------------------- |
| Single file fix                     | None                   | Typo, config change                       |
| Multi-file feature, standard        | `wf-branch-workflow`   | New entity, new menu, API integration     |
| Multi-file feature, needs isolation | `wf-worktree-workflow` | Long-running feature, parallel dev needed |
| Not sure which                      | Ask user               | —                                         |
