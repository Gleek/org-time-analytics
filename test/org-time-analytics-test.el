;;; org-time-analytics-test.el --- Tests for org-time-analytics -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-time-analytics)

(ert-deftest org-time-analytics-format-duration ()
  (should (equal "30m" (org-time-analytics--duration 30)))
  (should (equal "1h" (org-time-analytics--duration 60)))
  (should (equal "3h20m" (org-time-analytics--duration 200))))

(ert-deftest org-time-analytics-format-integer-change ()
  (should (equal "+19%" (substring-no-properties
                         (org-time-analytics--change 1320 1110))))
  (should (equal "-11%" (substring-no-properties
                         (org-time-analytics--change 615 690))))
  (let ((change (org-time-analytics--change 30 0)))
    (should (equal "-" change))
    (should (eq 'shadow (get-text-property 0 'face change)))))

(ert-deftest org-time-analytics-marks-missing-task-comparison ()
  (with-temp-buffer
    (org-time-analytics--insert-row "New task" 30 nil nil t)
    (should (string-match-p "30m +-" (buffer-string)))
    (should (memq 'fixed-pitch (ensure-list (get-text-property 1 'face))))))

(ert-deftest org-time-analytics-left-aligns-changes ()
  (with-temp-buffer
    (org-time-analytics--insert-row "Group" 60 nil 46 t)
    (org-time-analytics--insert-row "Task" 60 nil 15 t)
    (goto-char (point-min))
    (search-forward "+30%")
    (let ((first-anchor (get-text-property (- (point) 5) 'display)))
      (forward-line 1)
      (search-forward "+300%")
      (should (equal '(space :align-to 70) first-anchor))
      (should (equal first-anchor
                     (get-text-property (- (point) 6) 'display))))))

(ert-deftest org-time-analytics-task-change-only-for-prior-occurrence ()
  (with-temp-buffer
    (insert "x")
    (let* ((marker (copy-marker (point-min)))
           (current-entry (list :marker marker :minutes 60))
           (new-entry (list :marker (copy-marker (point-max)) :minutes 30))
           (previous-entry (list :marker marker :minutes 40))
           (current (list (list :tag "errands" :minutes 90
                                :entries (list current-entry new-entry))))
           (previous (list (list :tag "errands" :minutes 40
                                 :entries (list previous-entry))))
           (calls 0))
      (cl-letf (((symbol-function 'org-time-analytics-entries)
                 (lambda (&rest _)
                   (prog1 (if (zerop calls) current previous)
                     (cl-incf calls)))))
        (let ((org-time-analytics-show-task-changes t))
          (org-time-analytics--report-groups (seconds-to-time 100) (seconds-to-time 200))))
      (should (= 40 (plist-get current-entry :previous-minutes)))
      (should-not (plist-get new-entry :previous-minutes)))))

(ert-deftest org-time-analytics-can-disable-task-changes ()
  (let ((current-entry (list :marker (make-marker) :minutes 60))
        (calls 0))
    (cl-letf (((symbol-function 'org-time-analytics-entries)
               (lambda (&rest _)
                 (prog1 (if (zerop calls)
                            (list (list :tag "errands" :minutes 60
                                        :entries (list current-entry)))
                          nil)
                   (cl-incf calls)))))
      (let ((org-time-analytics-show-task-changes nil))
        (org-time-analytics--report-groups (seconds-to-time 100) (seconds-to-time 200))))
    (should-not (plist-member current-entry :previous-minutes))))

(ert-deftest org-time-analytics-groups-entry ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Example :work:\n:PROPERTIES:\n:CLIENT: Acme\n:END:\n")
    (goto-char (point-min))
    (should (equal '(nil) (org-time-analytics--entry-groups nil)))
    (should (equal '("work") (org-time-analytics--entry-groups 'tag)))
    (should (equal '("TODO") (org-time-analytics--entry-groups 'todo)))
    (should (equal '("Acme")
                   (org-time-analytics--entry-groups
                    '(property . "CLIENT"))))))

(ert-deftest org-time-analytics-nil-grouping-is-flat ()
  (let (groupings)
    (cl-letf (((symbol-function 'org-time-analytics-entries)
               (lambda (_from _to &optional _files group-by)
                 (push group-by groupings)
                 nil)))
      (org-time-analytics--report-groups (seconds-to-time 100)
                                         (seconds-to-time 200)
                                         nil))
    (should (equal '(nil nil) groupings))))

(ert-deftest org-time-analytics-renders-flat-task-change ()
  (with-temp-buffer
    (org-time-analytics-mode)
    (let ((org-time-analytics--from (seconds-to-time 100))
          (org-time-analytics--to (seconds-to-time 200))
          (org-time-analytics--group-by nil)
          (org-time-analytics--groups
           (list (list :tag nil :minutes 60
                       :entries (list (list :path "Shopping"
                                            :marker (make-marker)
                                            :minutes 60
                                            :previous-minutes 30))))))
      (org-time-analytics--render)
      (should (string-match-p "Shopping.*+100%" (buffer-string)))
      (should-not (string-match-p "[▶▼]" (buffer-string))))))

(ert-deftest org-time-analytics-counts-timestamp-range ()
  (with-temp-buffer
    (org-mode)
    (insert "* Example\n<2026-09-20 Sun 15:00-16:30>\n")
    (goto-char (point-min))
    (should (= 90 (org-time-analytics--entry-minutes
                   (encode-time 0 0 0 20 9 2026)
                   (encode-time 0 0 0 21 9 2026))))))

(provide 'org-time-analytics-test)
;;; org-time-analytics-test.el ends here
