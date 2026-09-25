# org-time-analytics



`org-time-analytics` is an interactive time report for Org mode. It totals
active timestamp ranges such as:

```org
* Design review :work:
<2026-09-20 Sun 15:00-16:30>
```

<img width="693" height="598" alt="image" src="https://github.com/user-attachments/assets/f7abf4c5-3f44-489d-aa5f-625de539d9d4" />


Reports can group entries by tag, TODO state, CATEGORY, or any Org property.
Each group expands to its source headings, and the report compares the selected
period with the preceding period of the same length.

## Requirements

- Emacs 29.1 or later
- Org 9.6 or later
- [org-ql](https://github.com/alphapapa/org-ql) 0.8 or later

## Installation

With [Elpaca](https://github.com/progfolio/elpaca):

```elisp
(use-package org-time-analytics
  :ensure (:host github :repo "Gleek/org-time-analytics")
  :after org-ql
  :commands (org-time-analytics-report))
```

With the built-in `package-vc` via `use-package` (Emacs 30 or later):

```elisp
(use-package org-time-analytics
  :vc (:url "https://github.com/Gleek/org-time-analytics.git")
  :after org-ql
  :commands (org-time-analytics-report))
```

Run `M-x org-time-analytics-report` to see the past seven days compared with
the seven days before them. Press `r` to choose one day, seven days, thirty days,
or custom. The preset ranges end at the current time. Custom prompts for start
and exclusive end dates.

## Report controls

| Key | Action |
|---|---|
| `TAB`, `RET` | Expand/collapse a group; `RET` on a task visits it |
| `G` | Group by tag, TODO state, CATEGORY, or a property |
| `r` | Choose one day, seven days, thirty days, or custom dates |
| `t` | Add a tag to the task at point |
| `b`, `f` | Move backward or forward by one report period |
| `.` | Return to the initially selected period |
| `g` | Refresh |

The Change column compares each group with the immediately preceding period of
equal length. Positive percentages use the `success` face and negative ones use
the `error` face. Expanded tasks also show their change when the same task has
time in the preceding period. A `-` marks groups and tasks with no duration in
that period.

## Configuration

The report reads `org-agenda-files` by default. You can provide a list or a
function returning a list:

```elisp
(setq org-time-analytics-files #'org-agenda-files)
```

The default period is `seven-days`. Set it to `one-day`, `thirty-days`, or
`custom` if preferred:

```elisp
(setq org-time-analytics-default-period 'thirty-days)
```

Grouping defaults to tags. Other defaults are:

```elisp
(setq org-time-analytics-group-by 'todo)
(setq org-time-analytics-group-by 'category)
(setq org-time-analytics-group-by '(property . "CLIENT"))
```

Set the grouping to nil for a flat task list. This is also available as
`none` from the report's `G` menu:

```elisp
(setq org-time-analytics-group-by nil)
```

Task-level changes are enabled by default. To show changes only for groups:

```elisp
(setq org-time-analytics-show-task-changes nil)
```

When grouping by tags, an entry with multiple tags contributes its full
duration to each tag. Limit eligible tags when you want mutually meaningful
categories:

```elisp
(setq org-time-analytics-tags '("work" "personal" "reading"))
```

The package is independent of `org-timegrid`; it works with ordinary Org files
containing timed active ranges.
