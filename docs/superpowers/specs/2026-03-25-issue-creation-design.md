# Design Spec: Automated Issue Creation

## Goal
Create 6 GitHub issues from markdown files located in `doc/spec/issues/` for the `DecentralizedGeo/location-protocol-dart` repository.

## Requirements
- **FR-1**: Exclude `2026-03-13_attest-return-uid-from-receipt.md`.
- **FR-2**: Parse the first `#` header as the issue title.
- **FR-3**: Use the remaining file content as the issue body.
- **FR-4**: Add labels `enhancement` and `feature` to each issue.
- **FR-5**: Use `gh` CLI for creation.

## Proposed Approach
A PowerShell script block will:
1. Iterate through `Get-ChildItem doc\spec\issues\*.md`.
2. Filter out the excluded file.
3. Use regex or string splitting to extract the title and body.
4. Execute `gh issue create`.

## Verification Plan
1. Check the output of each `gh` command for a successful issue URL.
2. List the last 6 issues using `gh issue list --limit 6 --json title,labels` to verify titles and labels.
