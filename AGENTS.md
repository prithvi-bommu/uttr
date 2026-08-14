# AGENTS.md

Conventions for any AI agent or contributor working in this repository.

## Creating GitHub Issues

Issues in this repo follow a parent/child hierarchy. Follow these rules exactly.

### Before creating any issue

1. **Draft the title and body first and get explicit confirmation.** Never create an issue without showing the draft.
2. **Ask whether it is a parent task or a child task.** Never assume.
3. **If it is a child task, ask which parent issue number it belongs to.**

### Titles

- Parent issues: a plain descriptive title.
- Child issues: prefix the title with the parent issue number in brackets.
  ```
  [#22] Add local LLM option for text post-processing to eliminate API latency
  ```

### Labels

Every issue gets `parent` or `child`, plus any topical labels that apply. Topical labels are not mutually exclusive with the hierarchy labels.

| Label | Purpose |
| --- | --- |
| `parent` | Parent/epic issue |
| `child` | Sub-issue of a parent task |
| `ux` | User experience improvements |
| `payments` | Payment gateway / monetization work |
| `performance` | Performance improvements — latency, speed, resource usage |

Create a new topical label only when the repository owner asks for one.

### Linking a child to its parent

Creating the issue with a `[#N]` prefix and a `child` label is not enough — also register it as a GitHub sub-issue so the parent shows the nested checklist:

```bash
gh api repos/prithvi-bommu/uttr/issues/<PARENT>/sub_issues --method POST -F sub_issue_id="$(gh api repos/prithvi-bommu/uttr/issues/<CHILD> --jq '.id')"
```

The endpoint requires the numeric `.id`, not the GraphQL `node_id`. Passing `node_id` returns a 422.

Note that GitHub's issue list is flat — sub-issues still appear alongside their parents. The `[#N]` title prefix and the `parent`/`child` labels are what make the hierarchy readable in that list, which is why both are required.

### Body structure

Create issues with `gh issue create --repo prithvi-bommu/uttr`, using a heredoc for the body. Typical sections:

- `## Summary` — what and why, in a couple of sentences.
- `## Current Behavior` / `## Problem` — for bugs and improvements.
- `## Requirements` or `## Areas to Investigate` — a `- [ ]` checklist so items can be added and reordered as priorities shift.
- `## Success Criteria` — how we know it is done, where measurable.
- `## Open Questions` — unresolved decisions, rather than guessing at them.

## Commits and pull requests

Do not add "Generated with" attribution, co-author trailers, or tool branding to commits, pull requests, or code.
