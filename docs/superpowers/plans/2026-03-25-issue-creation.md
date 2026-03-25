# Issue Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 6 GitHub issues from documentation in `doc/spec/issues/` with labels `enhancement` and `feature`.

**Architecture:** Use a PowerShell script block to iterate through markdown files, parse titles and bodies, and call the `gh` CLI.

**Tech Stack:** GitHub CLI (`gh`), PowerShell.

---

### Task 1: Environment and File Preparation

**Files:**
- Read: `doc/spec/issues/*.md`

- [ ] **Step 1: Confirm the list of files to process**
Run: `Get-ChildItem doc\spec\issues\*.md | Where-Object { $_.Name -ne "2026-03-13_attest-return-uid-from-receipt.md" } | Select-Object Name`
Expected: 6 files listed.

- [ ] **Step 2: Dry run parsing for one file**
Run:
```powershell
$file = "doc/spec/issues/lib-feat-abstract-signer-interface.md"
$content = Get-Content $file -Raw
$title = ($content -split "`n")[0].Trim('# ').Trim("`r")
$body = ($content -split "`n", 2)[1].Trim()
Write-Host "Title: $title"
Write-Host "Body Preview: $($body.Substring(0, 50))..."
```
Expected: Correct title and body preview.

---

### Task 2: Create Issues

**Files:**
- Read: `doc/spec/issues/*.md`

- [ ] **Step 1: Run the creation loop**
Run:
```powershell
$files = Get-ChildItem doc\spec\issues\*.md | Where-Object { $_.Name -ne "2026-03-13_attest-return-uid-from-receipt.md" }
foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $title = ($content -split "`n")[0].Trim('# ').Trim("`r")
    $body = ($content -split "`n", 2)[1].Trim()
    gh issue create --title "$title" --body "$body" --label "enhancement,feature"
}
```
Expected: 6 success messages with issue URLs.

---

### Task 3: Verification

- [ ] **Step 1: Verify issues on GitHub**
Run: `gh issue list --limit 6 --json title,labels --state open`
Expected: 6 new issues with labels `enhancement` and `feature`.

- [ ] **Step 2: Commit documentation design**
Run: `git add docs/superpowers/specs/2026-03-25-issue-creation-design.md`
Run: `git commit -m "docs: add issue creation design spec"`
