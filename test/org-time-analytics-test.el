;;; org-time-analytics-test.el --- Tests for org-time-analytics -*- lexical-binding: t; -*-

(require 'ert)
(require 'org-time-analytics)

(ert-deftest org-time-analytics-format-duration ()
  (should (equal "30m" (org-time-analytics--duration 30)))
  (should (equal "1h" (org-time-analytics--duration 60)))
  (should (equal "3h20m" (org-time-analytics--duration 200))))

(ert-deftest org-time-analytics-groups-entry ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Example :work:\n:PROPERTIES:\n:CLIENT: Acme\n:END:\n")
    (goto-char (point-min))
    (should (equal '("work") (org-time-analytics--entry-groups 'tag)))
    (should (equal '("TODO") (org-time-analytics--entry-groups 'todo)))
    (should (equal '("Acme")
                   (org-time-analytics--entry-groups
                    '(property . "CLIENT"))))))

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
