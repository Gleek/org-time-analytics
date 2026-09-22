;;; org-time-analytics.el --- Time reports for Org timestamps -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Umar Ahmad

;; Author: Umar Ahmad <Gleek@users.noreply.github.com>
;; Maintainer: Umar Ahmad <Gleek@users.noreply.github.com>
;; Version: 0.1.1
;; Package-Requires: ((emacs "29.1") (org "9.6") (org-ql "0.8"))
;; Keywords: calendar, outlines, convenience
;; URL: https://github.com/Gleek/org-time-analytics

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Explore time recorded as active Org timestamp ranges.  Reports can group
;; entries by tag, TODO state, CATEGORY, or an Org property, compare adjacent
;; periods, and link every result back to its source heading.

;;; Code:

(require 'org)
(require 'org-ql)
(require 'calendar)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup org-time-analytics nil
  "Reports for time recorded in Org timestamps."
  :group 'org
  :prefix "org-time-analytics-")

(defcustom org-time-analytics-files #'org-agenda-files
  "Files searched by `org-time-analytics-report'.
May be a list of files or a function returning one."
  :type '(choice function (repeat file))
  :group 'org-time-analytics)

(defcustom org-time-analytics-tags nil
  "Tags included in reports.
When nil, include every tag.  A timestamp with several included tags is
credited to each tag."
  :type '(repeat string)
  :group 'org-time-analytics)

(defcustom org-time-analytics-untagged-label "untagged"
  "Label used for headings with no included tags."
  :type 'string
  :group 'org-time-analytics)

(defcustom org-time-analytics-group-by 'tag
  "Default criterion used to group report entries.
The value may be nil, `tag', `todo', `category', or a cons whose car
is `property' and whose cdr is a property-name string.  A nil value
shows a flat task list."
  :type '(choice (const :tag "No grouping" nil)
                 (const tag) (const todo) (const category)
                 (cons (const property) string))
  :group 'org-time-analytics)

(defcustom org-time-analytics-hours-per-day 24
  "Hours per day counted as the accounted-time denominator.
The default of 24 measures accounted time against the full wall-clock
span.  Set it to a smaller number, such as a working day's length, to
measure accounted time against realistically available hours instead."
  :type 'number
  :group 'org-time-analytics)

(defcustom org-time-analytics-show-task-changes t
  "Whether expanded task rows show changes from the preceding period.
Tasks with no time in the preceding period have a blank Change column."
  :type 'boolean
  :group 'org-time-analytics)

(defvar org-time-analytics-buffer-name "*Org time report*")
(defvar-local org-time-analytics--from nil)
(defvar-local org-time-analytics--to nil)
(defvar-local org-time-analytics--initial-from nil)
(defvar-local org-time-analytics--initial-to nil)
(defvar-local org-time-analytics--expanded-tags nil)
(defvar-local org-time-analytics--groups nil)
(defvar-local org-time-analytics--group-by nil)
(defvar-local org-time-analytics--accounted-minutes 0)
(defvar-local org-time-analytics--previous-accounted-minutes 0)

(defun org-time-analytics--absolute-time (day)
  "Return midnight on absolute calendar DAY."
  (pcase-let ((`(,month ,date ,year)
               (calendar-gregorian-from-absolute day)))
    (encode-time 0 0 0 date month year)))

(defun org-time-analytics--time (timestamp suffix)
  "Return time value for TIMESTAMP endpoint SUFFIX."
  (let ((property (lambda (name)
                    (org-element-property
                     (intern (format ":%s-%s" name suffix)) timestamp))))
    (encode-time 0 (or (funcall property "minute") 0)
                 (or (funcall property "hour") 0)
                 (funcall property "day") (funcall property "month")
                 (funcall property "year"))))

(defun org-time-analytics--timestamp-minutes (timestamp from to)
  "Return minutes in TIMESTAMP overlapping the half-open interval FROM to TO."
  (when (and (eq (org-element-property :type timestamp) 'active-range)
             (integerp (org-element-property :hour-start timestamp)))
    (let* ((start (org-time-analytics--time timestamp "start"))
           (end (org-time-analytics--time timestamp "end"))
           (clipped-start (if (time-less-p start from) from start))
           (clipped-end (if (time-less-p to end) to end)))
      (when (time-less-p clipped-start clipped-end)
        (/ (float-time (time-subtract clipped-end clipped-start)) 60.0)))))

(defun org-time-analytics--entry-minutes (from to)
  "Return timed active-range minutes in the current entry between FROM and TO."
  (save-excursion
    (org-back-to-heading t)
    (let ((begin (point))
          (end (save-excursion
                 (outline-next-heading)
                 (point)))
          (minutes 0))
      (save-restriction
        (narrow-to-region begin end)
        (org-element-map (org-element-parse-buffer) 'timestamp
          (lambda (timestamp)
            (cl-incf minutes
                     (or (org-time-analytics--timestamp-minutes timestamp from to)
                         0)))))
      minutes)))

(defun org-time-analytics--entry-groups (group-by)
  "Return group names for the current entry according to GROUP-BY."
  (pcase group-by
    ('nil (list nil))
    ('tag
     (let ((tags (org-get-tags nil nil)))
       (when org-time-analytics-tags
         (setq tags (seq-intersection tags org-time-analytics-tags #'string=)))
       (or tags (list org-time-analytics-untagged-label))))
    ('todo (list (or (org-get-todo-state) "none")))
    ('category (list (or (org-get-category) "none")))
    (`(property . ,property)
     (list (or (org-entry-get nil property t) "none")))
    (_ (error "Invalid grouping criterion: %S" group-by))))

(cl-defun org-time-analytics-entries
    (from to &optional files (group-by org-time-analytics-group-by))
  "Return time-report groups for Org timestamps from FROM to TO.
FROM is inclusive and TO is exclusive.  FILES defaults to
`org-time-analytics-files'."
  (let ((group-by (or group-by org-time-analytics-group-by))
        (groups (make-hash-table :test #'equal))
        (files (or files (if (functionp org-time-analytics-files)
                            (funcall org-time-analytics-files)
                          org-time-analytics-files)))
        (from-date (format-time-string "%F" from))
        ;; org-ql's :to date is inclusive; querying one day before our exclusive
        ;; boundary avoids selecting an extra day.
        (to-date (format-time-string "%F" (time-subtract to (seconds-to-time 1)))))
    (org-ql-select files
      `(ts-active :from ,from-date :to ,to-date :with-time t)
      :action (lambda ()
                (let ((minutes (org-time-analytics--entry-minutes from to)))
                  (when (> minutes 0)
                    (let ((entry (list :minutes minutes
                                       :marker (copy-marker (point))
                                       :path (string-join
                                              (org-get-outline-path t) " / "))))
                      (dolist (group (org-time-analytics--entry-groups group-by))
                        (puthash group (cons entry (gethash group groups))
                                 groups)))))))
    (let (rows)
      (maphash
       (lambda (tag entries)
         (push (list :tag tag
                     :minutes (apply #'+ (mapcar (lambda (entry)
                                                   (plist-get entry :minutes))
                                                 entries))
                     :entries (sort entries
                                    (lambda (a b) (> (plist-get a :minutes)
                                                     (plist-get b :minutes)))))
               rows))
       groups)
      (sort rows (lambda (a b) (> (plist-get a :minutes)
                                  (plist-get b :minutes)))))))

(defun org-time-analytics-data (from to &optional files)
  "Return an alist of group name to minutes between FROM and TO in FILES."
  (mapcar (lambda (group) (cons (plist-get group :tag)
                                (plist-get group :minutes)))
          (org-time-analytics-entries from to files)))

(defun org-time-analytics--accounted-minutes (groups)
  "Return total minutes covered by GROUPS, counting each entry once.
An entry credited to several groups (for instance a heading with more
than one included tag) is not double-counted."
  (let ((seen (make-hash-table :test #'equal))
        (total 0))
    (dolist (group groups)
      (dolist (entry (plist-get group :entries))
        (let ((key (org-time-analytics--entry-key entry)))
          (unless (gethash key seen)
            (puthash key t seen)
            (cl-incf total (plist-get entry :minutes))))))
    total))

(defun org-time-analytics--report-groups (from to &optional group-by)
  "Return a cons (GROUPS . ACCOUNTED) for FROM to TO.
GROUPS carries changes from the preceding period.  ACCOUNTED is a cons
of accounted minutes for this period and for the preceding period of
the same length."
  (let* ((groups (org-time-analytics-entries from to nil group-by))
         (previous-from (time-subtract from (time-subtract to from)))
         (previous (org-time-analytics-entries previous-from from nil group-by))
         (previous-by-tag (make-hash-table :test #'equal))
         (previous-by-task (make-hash-table :test #'equal)))
    (dolist (group previous)
      (puthash (plist-get group :tag) (plist-get group :minutes)
               previous-by-tag)
      (when org-time-analytics-show-task-changes
        (dolist (entry (plist-get group :entries))
          (puthash (org-time-analytics--entry-key entry)
                   (plist-get entry :minutes) previous-by-task))))
    (dolist (group groups)
      (plist-put group :previous-minutes
                 (gethash (plist-get group :tag) previous-by-tag 0))
      (when org-time-analytics-show-task-changes
        (dolist (entry (plist-get group :entries))
          (plist-put entry :previous-minutes
                     (gethash (org-time-analytics--entry-key entry)
                              previous-by-task)))))
    (cons groups
          (cons (org-time-analytics--accounted-minutes groups)
                (org-time-analytics--accounted-minutes previous)))))

(defun org-time-analytics--entry-key (entry)
  "Return a stable source-heading key for ENTRY."
  (let ((marker (plist-get entry :marker)))
    (cons (marker-buffer marker) (marker-position marker))))

(defun org-time-analytics--duration (minutes)
  "Format MINUTES as a compact duration."
  (let* ((minutes (round minutes))
         (hours (/ minutes 60))
         (remainder (% minutes 60)))
    (cond ((zerop hours) (format "%dm" remainder))
          ((zerop remainder) (format "%dh" hours))
          (t (format "%dh%02dm" hours remainder)))))

(defun org-time-analytics--change (minutes previous)
  "Format the change from PREVIOUS minutes to MINUTES."
  (cond ((zerop previous) (propertize "-" 'face 'shadow))
        ((= minutes previous) "0%")
        (t (let ((change (round (/ (* 100.0 (- minutes previous)) previous))))
             (propertize (format "%+d%%" change)
                         'face (if (> change 0) 'success 'error))))))

(defun org-time-analytics--insert-row
    (text minutes properties &optional previous show-change)
  "Insert a report row containing TEXT, MINUTES and PROPERTIES.
When SHOW-CHANGE is non-nil, show the change from PREVIOUS or `-' when
there is no prior duration."
  (let ((start (point))
        (duration (org-time-analytics--duration minutes))
        (change (cond ((not show-change) "")
                      (previous (org-time-analytics--change minutes previous))
                      (t (propertize "-" 'face 'shadow)))))
    (insert (truncate-string-to-width text 58 nil nil "…")
            (propertize " " 'display
                        `(space :align-to ,(- 68 (string-width duration))))
            duration
            (propertize " " 'display '(space :align-to 70))
            change "\n")
    (add-text-properties start (point) properties)
    (add-face-text-property start (point) 'fixed-pitch t)))

(defun org-time-analytics--insert-task-row (entry)
  "Insert a task row for ENTRY."
  (org-time-analytics--insert-row
   (concat "    " (plist-get entry :path))
   (plist-get entry :minutes)
   `(org-time-analytics-kind task
     org-time-analytics-marker ,(plist-get entry :marker))
   (plist-get entry :previous-minutes)
   org-time-analytics-show-task-changes))

(defun org-time-analytics--accounted-share (minutes span-minutes)
  "Format MINUTES accounted for out of SPAN-MINUTES as a duration and share."
  (format "%s of %s (%s)"
          (propertize (org-time-analytics--duration minutes) 'face 'bold)
          (org-time-analytics--duration span-minutes)
          (propertize (format "%d%%"
                              (if (zerop span-minutes) 0
                                (round (/ (* 100.0 minutes) span-minutes))))
                      'face 'bold)))

(defun org-time-analytics--render ()
  "Render the current time report."
  (let* ((inhibit-read-only t)
         (line (line-number-at-pos))
         (span-minutes (* (/ (float-time (time-subtract org-time-analytics--to
                                                         org-time-analytics--from))
                             86400.0)
                          org-time-analytics-hours-per-day 60))
         (previous-from
          (time-subtract org-time-analytics--from
                         (time-subtract org-time-analytics--to
                                        org-time-analytics--from))))
    (erase-buffer)
    (insert (format "Time by %s: %s to %s\nCompared with: %s to %s\n"
                    (org-time-analytics--group-description)
                    (format-time-string "%F" org-time-analytics--from)
                    (format-time-string "%F" org-time-analytics--to)
                    (format-time-string "%F" previous-from)
                    (format-time-string "%F" org-time-analytics--from)))
    (insert (format "Accounted: %s vs previous %s (%s)\n\n"
                    (org-time-analytics--accounted-share
                     org-time-analytics--accounted-minutes span-minutes)
                    (org-time-analytics--accounted-share
                     org-time-analytics--previous-accounted-minutes span-minutes)
                    (org-time-analytics--change
                     org-time-analytics--accounted-minutes
                     org-time-analytics--previous-accounted-minutes)))
    (insert (propertize
             "TAB/RET expand · RET visit · t add tag · G group · g refresh · b/f period · . reset\n\n"
             'face 'shadow))
    (let ((start (point)))
      (insert (if org-time-analytics--group-by "Group / task" "Task")
              (propertize " " 'display '(space :align-to 64))
              "Time"
              (propertize " " 'display '(space :align-to 70))
              "Change\n")
      (add-face-text-property start (point) '(bold fixed-pitch)))
    (insert (make-string 80 ?-) "\n")
    (if org-time-analytics--groups
        (if (null org-time-analytics--group-by)
            (dolist (entry (plist-get (car org-time-analytics--groups) :entries))
              (org-time-analytics--insert-task-row entry))
          (dolist (group org-time-analytics--groups)
            (let* ((tag (plist-get group :tag))
                   (expanded (member tag org-time-analytics--expanded-tags)))
              (org-time-analytics--insert-row
               (format "%s%s (%d)" (if expanded "▼ " "▶ ") tag
                       (length (plist-get group :entries)))
               (plist-get group :minutes)
               `(org-time-analytics-kind tag org-time-analytics-tag ,tag)
               (plist-get group :previous-minutes)
               t)
              (when expanded
                (dolist (entry (plist-get group :entries))
                  (org-time-analytics--insert-task-row entry))))))
      (insert "No timed entries.\n"))
    (goto-char (point-min))
    (forward-line (1- (min line (line-number-at-pos (point-max)))))
    (back-to-indentation)))

(defun org-time-analytics-toggle ()
  "Expand or collapse the tag at point, or visit a task."
  (interactive)
  (pcase (get-text-property (point) 'org-time-analytics-kind)
    ('tag
     (let ((tag (get-text-property (point) 'org-time-analytics-tag)))
       (if (member tag org-time-analytics--expanded-tags)
           (setq org-time-analytics--expanded-tags
                 (delete tag org-time-analytics--expanded-tags))
         (push tag org-time-analytics--expanded-tags))
       (org-time-analytics--render)))
    ('task (org-time-analytics-visit))))

(defun org-time-analytics-visit ()
  "Visit the Org task at point."
  (interactive)
  (if-let ((marker (get-text-property (point) 'org-time-analytics-marker)))
      (progn (pop-to-buffer (marker-buffer marker))
             (goto-char marker)
             (org-fold-show-context))
    (user-error "No task on this row")))

(defun org-time-analytics-refresh ()
  "Requery Org files and refresh the report."
  (interactive)
  (let ((result (org-time-analytics--report-groups org-time-analytics--from
                                                    org-time-analytics--to
                                                    org-time-analytics--group-by)))
    (setq org-time-analytics--groups (car result)
          org-time-analytics--accounted-minutes (car (cdr result))
          org-time-analytics--previous-accounted-minutes (cdr (cdr result))))
  (org-time-analytics--render))

(defun org-time-analytics--group-description ()
  "Return a display name for the current grouping criterion."
  (pcase org-time-analytics--group-by
    ('nil "task")
    ('tag "tag")
    ('todo "TODO state")
    ('category "CATEGORY")
    (`(property . ,property) (format "property %s" property))))

(defun org-time-analytics-change-group (criterion)
  "Change the report grouping CRITERION and refresh."
  (interactive
   (let* ((choice (completing-read "Group by: "
                                   '("none" "tag" "TODO state" "CATEGORY" "property")
                                   nil t))
          (criterion
           (pcase choice
             ("none" nil)
             ("tag" 'tag)
             ("TODO state" 'todo)
             ("CATEGORY" 'category)
             ("property"
              (cons 'property
                    (read-string
                     "Property: "
                     (when (eq (car-safe org-time-analytics--group-by) 'property)
                       (cdr org-time-analytics--group-by))))))))
     (list criterion)))
  (setq org-time-analytics--group-by criterion
        org-time-analytics--expanded-tags nil)
  (org-time-analytics-refresh))

(defun org-time-analytics-shift-period (direction)
  "Shift the report period by its duration in DIRECTION."
  (let ((duration (time-subtract org-time-analytics--to
                                 org-time-analytics--from)))
    (setq org-time-analytics--from
          (funcall direction org-time-analytics--from duration)
          org-time-analytics--to
          (funcall direction org-time-analytics--to duration))
    (org-time-analytics-refresh)))

(defun org-time-analytics-previous-period ()
  "Show the preceding period of the same duration."
  (interactive)
  (org-time-analytics-shift-period #'time-subtract))

(defun org-time-analytics-next-period ()
  "Show the following period of the same duration."
  (interactive)
  (org-time-analytics-shift-period #'time-add))

(defun org-time-analytics-reset-period ()
  "Return to the period originally selected for this report."
  (interactive)
  (setq org-time-analytics--from org-time-analytics--initial-from
        org-time-analytics--to org-time-analytics--initial-to)
  (org-time-analytics-refresh))

(defun org-time-analytics-tag-task (tag)
  "Add TAG to the task at point and refresh the report."
  (interactive
   (list (completing-read "Add tag: "
                          (org-global-tags-completion-table
                           (if (functionp org-time-analytics-files)
                               (funcall org-time-analytics-files)
                             org-time-analytics-files))
                          nil nil)))
  (if-let ((marker (get-text-property (point) 'org-time-analytics-marker)))
      (org-with-point-at marker
        (org-toggle-tag tag 'on)
        (save-buffer))
    (user-error "Expand a tag and select a task first"))
  (org-time-analytics-refresh))

(defvar org-time-analytics-mode-map
  (make-sparse-keymap))

(define-key org-time-analytics-mode-map (kbd "TAB") #'org-time-analytics-toggle)
(define-key org-time-analytics-mode-map (kbd "<tab>") #'org-time-analytics-toggle)
(define-key org-time-analytics-mode-map (kbd "RET") #'org-time-analytics-toggle)
(define-key org-time-analytics-mode-map (kbd "g") #'org-time-analytics-refresh)
(define-key org-time-analytics-mode-map (kbd "t") #'org-time-analytics-tag-task)
(define-key org-time-analytics-mode-map (kbd "G") #'org-time-analytics-change-group)
(define-key org-time-analytics-mode-map (kbd "b") #'org-time-analytics-previous-period)
(define-key org-time-analytics-mode-map (kbd "f") #'org-time-analytics-next-period)
(define-key org-time-analytics-mode-map (kbd ".") #'org-time-analytics-reset-period)

(define-derived-mode org-time-analytics-mode special-mode "Org-Time-Report"
  "Major mode for exploring time recorded in Org timestamps."
  (setq truncate-lines t))

(defun org-time-analytics-report (from to)
  "Show time grouped by `org-time-analytics-group-by' between FROM and TO.
Interactively, default to seven days ago through tomorrow."
  (interactive
   (let* ((today (org-today))
          (default-from (org-time-analytics--absolute-time (- today 7)))
          (default-to (org-time-analytics--absolute-time (1+ today))))
     (list (org-read-date nil t nil "From: " default-from)
           (org-read-date nil t nil "To (exclusive): " default-to))))
  (with-current-buffer (get-buffer-create org-time-analytics-buffer-name)
    (org-time-analytics-mode)
    (setq org-time-analytics--from from
          org-time-analytics--to to
          org-time-analytics--initial-from from
          org-time-analytics--initial-to to
          org-time-analytics--group-by org-time-analytics-group-by
          org-time-analytics--expanded-tags nil)
    (org-time-analytics-refresh)
    (pop-to-buffer (current-buffer))))

(provide 'org-time-analytics)
;;; org-time-analytics.el ends here
