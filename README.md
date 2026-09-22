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

Run `M-x org-time-analytics-report`, then choose the start and exclusive end
dates. By default the prompt suggests seven days ago through tomorrow.

## Report controls

| Key | Action |
|---|---|
| `TAB`, `RET` | Expand/collapse a group; `RET` on a task visits it |
| `G` | Group by tag, TODO state, CATEGORY, or a property |
| `t` | Add a tag to the task at point |
| `b`, `f` | Move backward or forward by one report period |
| `.` | Return to the initially selected period |
| `g` | Refresh |

The Change column compares each group with the immediately preceding period of
equal length. Positive percentages use the `success` face and negative ones use
the `error` face.

## Configuration

The report reads `org-agenda-files` by default. You can provide a list or a
function returning a list:

```elisp
(setq org-time-analytics-files #'org-agenda-files)
```

Grouping defaults to tags. Other defaults are:

```elisp
(setq org-time-analytics-group-by 'todo)
(setq org-time-analytics-group-by 'category)
(setq org-time-analytics-group-by '(property . "CLIENT"))
```

When grouping by tags, an entry with multiple tags contributes its full
duration to each tag. Limit eligible tags when you want mutually meaningful
categories:

```elisp
(setq org-time-analytics-tags '("work" "personal" "reading"))
```

The package is independent of `org-timegrid`; it works with ordinary Org files
containing timed active ranges.
