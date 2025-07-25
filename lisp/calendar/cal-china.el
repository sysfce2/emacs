;;; cal-china.el --- calendar functions for the Chinese calendar  -*- lexical-binding: t; -*-

;; Copyright (C) 1995, 1997, 2001-2025 Free Software Foundation, Inc.

;; Author: Edward M. Reingold <reingold@cs.uiuc.edu>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: calendar
;; Human-Keywords: Chinese calendar, calendar, holidays, diary
;; Package: calendar

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; See calendar.el.

;; The rules used for the Chinese calendar are those of Baolin Liu
;; (see L. E. Doggett's article "Calendars" in the Explanatory
;; Supplement to the Astronomical Almanac, second edition, 1992) for
;; the calendar as revised at the beginning of the Qing dynasty in
;; 1644.  The nature of the astronomical calculations is such that
;; precise calculations cannot be made without great expense in time,
;; so that the calendars produced may not agree perfectly with
;; published tables--but no two pairs of published tables agree
;; perfectly either!  Liu's rules produce a calendar for 2033 which is
;; not accepted by all authorities.  The date of Chinese New Year is
;; correct from 1644-2051.

;; Note to maintainers:
;; Use `chinese-year-cache-init' every few years to recenter the default
;; value of `chinese-year-cache'.

;;; Code:

(require 'calendar)
(require 'lunar)                        ; lunar-new-moon-on-or-after
;; solar-date-next-longitude brought in by lunar.
;;;(require 'solar)
;; calendar-astro-to-absolute and from-absolute are cal-autoloads.
;;;(require 'cal-julian)


(defgroup calendar-chinese nil
  "Chinese calendar support."
  :prefix "calendar-chinese-"
  :group 'calendar)

(defcustom calendar-chinese-time-zone
  '(if (< year 1928)
       (+ 465 (/ 40.0 60.0))
     480)
  "Minutes difference between local standard time for Chinese calendar and UTC.
Default is for Beijing.  This is an expression in `year' since it changed at
1928-01-01 00:00:00 from UT+7:45:40 to UT+8."
  :type 'sexp
  :group 'calendar-chinese)

;; It gets eval'd.
;;;###autoload
(put 'calendar-chinese-time-zone 'risky-local-variable t)

;; FIXME unused.
(defcustom calendar-chinese-location-name "Beijing"
  "Name of location used for calculation of Chinese calendar."
  :type 'string
  :group 'calendar-chinese)

(defcustom calendar-chinese-daylight-time-offset 0
;; The correct value is as follows, but the Chinese calendrical
;; authorities do NOT use DST in determining astronomical events:
;;  60
  "Minutes difference between daylight saving and standard time.
Default is for no daylight saving time."
  :type 'integer
  :group 'calendar-chinese)

(defcustom calendar-chinese-standard-time-zone-name
  '(if (< year 1928)
       "PMT"
     "CST")
  "Abbreviated name of standard time zone used for Chinese calendar.
This is an expression depending on `year' because it changed
at 1928-01-01 00:00:00 from `PMT' to `CST'."
  :type 'sexp
  :risky t
  :group 'calendar-chinese)

(defcustom calendar-chinese-daylight-time-zone-name "CDT"
  "Abbreviated name of daylight saving time zone used for Chinese calendar."
  :type 'string
  :group 'calendar-chinese)

(defcustom calendar-chinese-daylight-saving-start nil
;; The correct value is as follows, but the Chinese calendrical
;; authorities do NOT use DST in determining astronomical events:
;;  '(cond ((< 1986 year) (calendar-nth-named-day 1 0 4 year 10))
;;         ((= 1986 year) '(5 4 1986))
;;         (t nil))
  "Sexp giving the date on which daylight saving time starts.
Default is for no daylight saving time.  See documentation of
`calendar-daylight-savings-starts'."
  :type 'sexp
  :risky t
  :group 'calendar-chinese)

(defcustom calendar-chinese-daylight-saving-end nil
;; The correct value is as follows, but the Chinese calendrical
;; authorities do NOT use DST in determining astronomical events:
;;  '(if (<= 1986 year) (calendar-nth-named-day 1 0 9 year 11))
  "Sexp giving the date on which daylight saving time ends.
Default is for no daylight saving time.  See documentation of
`calendar-daylight-savings-ends'."
  :type 'sexp
  :risky t
  :group 'calendar-chinese)

(defcustom calendar-chinese-daylight-saving-start-time 0
  "Number of minutes after midnight that daylight saving time starts.
Default is for no daylight saving time."
  :type 'integer
  :group 'calendar-chinese)

(defcustom calendar-chinese-daylight-saving-end-time 0
  "Number of minutes after midnight that daylight saving time ends.
Default is for no daylight saving time."
  :type 'integer
  :group 'calendar-chinese)

(defcustom calendar-chinese-celestial-stem
  ["Jia" "Yi" "Bing" "Ding" "Wu" "Ji" "Geng" "Xin" "Ren" "Gui"]
  "Prefixes used by `calendar-chinese-sexagesimal-name'."
  :group 'calendar-chinese
  :type '(vector (string :tag "Jia")
                 (string :tag "Yi")
                 (string :tag "Bing")
                 (string :tag "Ding")
                 (string :tag "Wu")
                 (string :tag "Ji")
                 (string :tag "Geng")
                 (string :tag "Xin")
                 (string :tag "Ren")
                 (string :tag "Gui")))

(defcustom calendar-chinese-terrestrial-branch
  ["Zi" "Chou" "Yin" "Mao" "Chen" "Si" "Wu" "Wei" "Shen" "You" "Xu" "Hai"]
  "Suffixes used by `calendar-chinese-sexagesimal-name'."
  :group 'calendar-chinese
  :type '(vector (string :tag "Zi")
                 (string :tag "Chou")
                 (string :tag "Yin")
                 (string :tag "Mao")
                 (string :tag "Chen")
                 (string :tag "Si")
                 (string :tag "Wu")
                 (string :tag "Wei")
                 (string :tag "Shen")
                 (string :tag "You")
                 (string :tag "Xu")
                 (string :tag "Hai")))

;;; End of user options.


(defun calendar-chinese-sexagesimal-name (n)
  "The N-th name of the Chinese sexagesimal cycle.
N congruent to 1 gives the first name, N congruent to 2 gives the second name,
..., N congruent to 60 gives the sixtieth name."
  (format "%s-%s"
          (aref calendar-chinese-celestial-stem (% (1- n) 10))
          (aref calendar-chinese-terrestrial-branch (% (1- n) 12))))

(defun calendar-chinese-zodiac-sign-on-or-after (d)
  "Absolute date of first new Zodiac sign on or after absolute date D.
The Zodiac signs begin when the sun's longitude is a multiple of 30 degrees."
  (with-suppressed-warnings ((lexical year))
    (defvar year))
  (let* ((year (calendar-extract-year (calendar-gregorian-from-absolute d)))
         (calendar-time-zone (eval calendar-chinese-time-zone)) ; uses year
         (calendar-daylight-time-offset
          calendar-chinese-daylight-time-offset)
         (calendar-standard-time-zone-name
          calendar-chinese-standard-time-zone-name)
         (calendar-daylight-time-zone-name
          calendar-chinese-daylight-time-zone-name)
         (calendar-daylight-savings-starts
          calendar-chinese-daylight-saving-start)
         (calendar-daylight-savings-ends
          calendar-chinese-daylight-saving-end)
         (calendar-daylight-savings-starts-time
          calendar-chinese-daylight-saving-start-time)
         (calendar-daylight-savings-ends-time
          calendar-chinese-daylight-saving-end-time))
   (floor
    (calendar-astro-to-absolute
     (solar-date-next-longitude (calendar-astro-from-absolute d) 30)))))

(defun calendar-chinese-new-moon-on-or-after (d)
  "Absolute date of first new moon on or after absolute date D."
  (with-suppressed-warnings ((lexical year))
    (defvar year))
  (let* ((year (calendar-extract-year (calendar-gregorian-from-absolute d)))
         (calendar-time-zone (eval calendar-chinese-time-zone))
         (calendar-daylight-time-offset
          calendar-chinese-daylight-time-offset)
         (calendar-standard-time-zone-name
          calendar-chinese-standard-time-zone-name)
         (calendar-daylight-time-zone-name
          calendar-chinese-daylight-time-zone-name)
         (calendar-daylight-savings-starts
          calendar-chinese-daylight-saving-start)
         (calendar-daylight-savings-ends
          calendar-chinese-daylight-saving-end)
         (calendar-daylight-savings-starts-time
          calendar-chinese-daylight-saving-start-time)
         (calendar-daylight-savings-ends-time
          calendar-chinese-daylight-saving-end-time))
    (floor
     (calendar-astro-to-absolute
      (lunar-new-moon-on-or-after (calendar-astro-from-absolute d))))))

(defun calendar-chinese-month-list (start end)
  "List of starting dates of Chinese months from START to END."
  (if (<= start end)
      (let ((new-moon (calendar-chinese-new-moon-on-or-after start)))
        (if (<= new-moon end)
            (cons new-moon
                  (calendar-chinese-month-list (1+ new-moon) end))))))

(defun calendar-chinese-number-months (list start)
  "Assign month numbers to the lunar months in LIST, starting with START.
Numbers are assigned sequentially, START, START+1, ..., 11, with
half numbers used for leap months.  First and last months of list
are never leap months."
  (when list
    (cons (list start (car list))       ; first month
          ;; Remaining months.
          (if (zerop (- 12 start (length list)))
              ;; List is too short for a leap month.
              (calendar-chinese-number-months (cdr list) (1+ start))
            (if (and (cddr list)        ; at least two more months...
                     (<= (nth 2 list)
                         (calendar-chinese-zodiac-sign-on-or-after
                          (cadr list))))
                ;; Next month is a leap month.
                (cons (list (+ start 0.5) (cadr list))
                      (calendar-chinese-number-months (cddr list) (1+ start)))
              ;; Next month is not a leap month.
              (calendar-chinese-number-months (cdr list) (1+ start)))))))

(defun calendar-chinese-compute-year (y)
  "Compute the structure of the Chinese year for Gregorian year Y.
The result is a list of pairs (i d), where month i begins on absolute date d,
of the Chinese months from the Chinese month following the solstice in
Gregorian year Y-1 to the Chinese month of the solstice of Gregorian year Y."
  (let* ((next-solstice (calendar-chinese-zodiac-sign-on-or-after
                         (calendar-absolute-from-gregorian
                          (list 12 15 y))))
         (list (calendar-chinese-month-list
                (1+ (calendar-chinese-zodiac-sign-on-or-after
                     (calendar-absolute-from-gregorian
                      (list 12 15 (1- y)))))
                next-solstice))
         (next-sign (calendar-chinese-zodiac-sign-on-or-after (car list))))
    (if (= (length list) 12)
        ;; No room for a leap month, just number them 12, 1, 2, ..., 11.
        (cons (list 12 (car list))
              (calendar-chinese-number-months (cdr list) 1))
      ;; Now we can assign numbers to the list for y.
      ;; The first month or two are special.
      (if (or (> (car list) next-sign) (>= next-sign (cadr list)))
          ;; First month on list is a leap month, second is not.
          (append (list (list 11.5 (car list))
                        (list 12 (cadr list)))
                  (calendar-chinese-number-months (cddr list) 1))
        ;; First month on list is not a leap month.
        (append (list (list 12 (car list)))
                (if (>= (calendar-chinese-zodiac-sign-on-or-after (cadr list))
                        (nth 2 list))
                    ;; Second month on list is a leap month.
                    (cons (list 12.5 (cadr list))
                          (calendar-chinese-number-months (cddr list) 1))
                  ;; Second month on list is not a leap month.
                  (calendar-chinese-number-months (cdr list) 1)))))))

(defvar calendar-chinese-year-cache
  ;; Maintainers: delete existing value, position point at start of
  ;; empty line, then call  M-: (calendar-chinese-year-cache-init N)
  '((2018 (12 736711) (1 736741) (2 736770) (3 736800) (4 736829) (5 736859)
          (6 736888) (7 736917) (8 736947) (9 736976) (10 737006) (11 737035))
    (2019 (12 737065) (1 737095) (2 737125) (3 737154) (4 737184) (5 737213)
          (6 737243) (7 737272) (8 737301) (9 737331) (10 737360) (11 737389))
    (2020 (12 737419) (1 737449) (2 737478) (3 737508) (4 737538) (4.5 737568)
          (5 737597) (6 737627) (7 737656) (8 737685) (9 737715) (10 737744)
          (11 737774))
    (2021 (12 737803) (1 737833) (2 737862) (3 737892) (4 737922) (5 737951)
          (6 737981) (7 738010) (8 738040) (9 738069) (10 738099) (11 738128))
    (2022 (12 738158) (1 738187) (2 738217) (3 738246) (4 738276) (5 738305)
          (6 738335) (7 738365) (8 738394) (9 738424) (10 738453) (11 738483))
    (2023 (12 738512) (1 738542) (2 738571) (2.5 738601) (3 738630) (4 738659)
          (5 738689) (6 738719) (7 738748) (8 738778) (9 738808) (10 738837)
          (11 738867))
    (2024 (12 738896) (1 738926) (2 738955) (3 738985) (4 739014) (5 739043)
          (6 739073) (7 739102) (8 739132) (9 739162) (10 739191) (11 739221))
    (2025 (12 739251) (1 739280) (2 739310) (3 739339) (4 739369) (5 739398)
          (6 739427) (6.5 739457) (7 739486) (8 739516) (9 739545) (10 739575)
          (11 739605))
    (2026 (12 739635) (1 739664) (2 739694) (3 739723) (4 739753) (5 739782)
          (6 739811) (7 739841) (8 739870) (9 739899) (10 739929) (11 739959))
    (2027 (12 739989) (1 740018) (2 740048) (3 740078) (4 740107) (5 740137)
          (6 740166) (7 740195) (8 740225) (9 740254) (10 740283) (11 740313))
    (2028 (12 740343) (1 740372) (2 740402) (3 740432) (4 740462) (5 740491)
          (5.5 740521) (6 740550) (7 740579) (8 740609) (9 740638) (10 740667)
          (11 740697))
    (2029 (12 740727) (1 740756) (2 740786) (3 740816) (4 740845) (5 740875)
          (6 740904) (7 740934) (8 740963) (9 740993) (10 741022) (11 741051))
    (2030 (12 741081) (1 741111) (2 741140) (3 741170) (4 741199) (5 741229)
          (6 741259) (7 741288) (8 741318) (9 741347) (10 741377) (11 741406))
    (2031 (12 741436) (1 741465) (2 741494) (3 741524) (3.5 741554) (4 741583)
          (5 741613) (6 741642) (7 741672) (8 741702) (9 741731) (10 741761)
          (11 741790))
    (2032 (12 741820) (1 741849) (2 741879) (3 741908) (4 741937) (5 741967)
          (6 741996) (7 742026) (8 742056) (9 742085) (10 742115) (11 742145))
    (2033 (12 742174) (1 742204) (2 742233) (3 742263) (4 742292) (5 742321)
          (6 742351) (7 742380) (8 742410) (9 742439) (10 742469) (11 742499))
    (2034 (11.5 742529) (12 742558) (1 742588) (2 742617) (3 742647) (4 742676)
          (5 742705) (6 742735) (7 742764) (8 742794) (9 742823) (10 742853)
          (11 742883))
    (2035 (12 742912) (1 742942) (2 742972) (3 743001) (4 743031) (5 743060)
          (6 743089) (7 743119) (8 743148) (9 743177) (10 743207) (11 743237))
    (2036 (12 743266) (1 743296) (2 743326) (3 743356) (4 743385) (5 743415)
          (6 743444) (6.5 743473) (7 743503) (8 743532) (9 743561) (10 743591)
          (11 743620))
    (2037 (12 743650) (1 743680) (2 743710) (3 743740) (4 743769) (5 743799)
          (6 743828) (7 743857) (8 743887) (9 743916) (10 743945) (11 743975))
    (2038 (12 744004) (1 744034) (2 744064) (3 744094) (4 744123) (5 744153)
          (6 744182) (7 744212) (8 744241) (9 744271) (10 744300) (11 744329)))
  "Alist of Chinese year structures as determined by `chinese-year'.
The default can be nil, but some values are precomputed for efficiency.")

(defun calendar-chinese-year (y)
  "The structure of the Chinese year for Gregorian year Y.
The result is a list of pairs (i d), where month i begins on absolute date d,
of the Chinese months from the Chinese month following the solstice in
Gregorian year Y-1 to the Chinese month of the solstice of Gregorian year Y.
The list is cached in `calendar-chinese-year-cache' for further use."
  (let ((list (cdr (assoc y calendar-chinese-year-cache))))
    (or list
        (setq list (calendar-chinese-compute-year y)
              calendar-chinese-year-cache (append calendar-chinese-year-cache
                                         (list (cons y list)))))
    list))

;; Maintainer use.
(defun calendar-chinese-year-cache-init (year)
  "Insert an initialization value for `calendar-chinese-year-cache' after point.
Computes values for 10 years either side of YEAR."
  (setq year (- year 10))
  (let (calendar-chinese-year-cache end)
    (save-excursion
      (insert "'(")
      (dotimes (n 21)
        (princ (cons year (calendar-chinese-compute-year year))
               (current-buffer))
        (insert (if (= n 20) ")" "\n"))
        (setq year (1+ year)))
      (setq end (point)))
    (save-excursion
      ;; fill-column -/+ 5.
      (while (and (< (point) end)
                  (re-search-forward "^.\\{65,75\\})" end t))
        (delete-char 1)
        (insert "\n")))
    (indent-region (point) end)))

(defun calendar-chinese-to-absolute (date)
  "The number of days elapsed between the Gregorian date 12/31/1 BC and DATE.
DATE is a Chinese date (cycle year month day).  The Gregorian date
Sunday, December 31, 1 BC is imaginary."
  (let* ((cycle (car date))
         (year (cadr date))
         (month (nth 2 date))
         (day (nth 3 date))
         (g-year (+ (* (1- cycle) 60)  ; years in prior cycles
                    (1- year)          ; prior years this cycle
                    -2636)))           ; years before absolute date 0
    (+ (1- day)                        ; prior days this month
       (cadr                    ; absolute date of start of this month
        (assoc month (append (memq (assoc 1 (calendar-chinese-year g-year))
                                   (calendar-chinese-year g-year))
                             (calendar-chinese-year (1+ g-year))))))))

(defun calendar-chinese-from-absolute (date)
  "Compute Chinese date (cycle year month day) corresponding to absolute DATE.
The absolute date is the number of days elapsed since the (imaginary)
Gregorian date Sunday, December 31, 1 BC."
  (let* ((g-year (calendar-extract-year
                  (calendar-gregorian-from-absolute date)))
         (c-year (+ g-year 2695))
         (list (append (calendar-chinese-year (1- g-year))
                       (calendar-chinese-year g-year)
                       (calendar-chinese-year (1+ g-year)))))
    (while (<= (cadr (cadr list)) date)
      ;; The first month on the list is in Chinese year c-year.
      ;; Date is on or after start of second month on list...
      (if (= 1 (caar (cdr list)))
          ;; Second month on list is a new Chinese year...
          (setq c-year (1+ c-year)))
      ;; ...so first month on list is of no interest.
      (setq list (cdr list)))
    (list (/ (1- c-year) 60)
          ;; Remainder of c-year/60 with 60 instead of 0.
          (1+ (mod (1- c-year) 60))
          (caar list)
          (1+ (- date (cadr (car list)))))))

;; Bound in calendar-generate.
(defvar displayed-month)
(defvar displayed-year)

;;;###holiday-autoload
(defun holiday-chinese-new-year ()
  "Date of Chinese New Year, if visible in calendar.
Returns (((MONTH DAY YEAR) TEXT)), where the date is Gregorian."
  (let ((m displayed-month)
        (y displayed-year)
        chinese-new-year)
    ;; In the Gregorian calendar, CNY falls between Jan 21 and Feb 20.
    ;; Jan is visible if displayed-month = 12, 1, 2; Feb if d-m = 1, 2, 3.
    ;; If we shift the calendar forward one month, we can do a
    ;; one-sided test, namely: d-m <= 4 means CNY might be visible.
    (calendar-increment-month m y 1)    ; shift forward a month
    (and (< m 5)
         (calendar-date-is-visible-p
          (setq chinese-new-year
                (calendar-gregorian-from-absolute
                 (cadr (assoc 1 (calendar-chinese-year y))))))
         (list
          (list chinese-new-year
                (format "Chinese New Year (%s)"
                        (calendar-chinese-sexagesimal-name (+ y 57))))))))

;;;###holiday-autoload
(defun holiday-chinese-qingming ()
  "Date of Chinese Qingming Festival, if visible in calendar.
Returns (((MONTH DAY YEAR) TEXT)), where the date is Gregorian."
  (when (memq displayed-month '(3 4 5)) ; is April visible?
    (list (list (calendar-gregorian-from-absolute
                 ;; 15 days after Vernal Equinox.
                 (+ 15
                    (calendar-chinese-zodiac-sign-on-or-after
                     (calendar-absolute-from-gregorian
                      (list 3 15 displayed-year)))))
                "Qingming Festival"))))

;;;###holiday-autoload
(defun holiday-chinese-winter-solstice ()
  "Date of Chinese winter solstice, if visible in calendar.
Returns (((MONTH DAY YEAR) TEXT)), where the date is Gregorian."
  (when (memq displayed-month '(11 12 1)) ; is December visible?
    (list (list (calendar-gregorian-from-absolute
                 (calendar-chinese-zodiac-sign-on-or-after
                  (calendar-absolute-from-gregorian
                   (list 12 15 (if (eq displayed-month 1)
                                   (1- displayed-year)
                                 displayed-year)))))
                "Winter Solstice Festival"))))

;;;###holiday-autoload
(defun holiday-chinese (month day string)
  "Holiday on Chinese MONTH, DAY called STRING.
If MONTH, DAY (Chinese) is visible, returns the corresponding
Gregorian date as the list (((month day year) STRING)).
Returns nil if it is not visible in the current calendar window."
  (let ((date
         (calendar-gregorian-from-absolute
          ;; A basic optimization.  Chinese year can only change if
          ;; Jan or Feb are visible.  FIXME can we do more?
          (if (memq displayed-month '(12 1 2 3))
              ;; This is calendar-nongregorian-visible-p adapted for
              ;; the form of chinese dates: (cycle year month day) as
              ;; opposed to (month day year).
              (let* ((m1 displayed-month)
                     (y1 displayed-year)
                     (m2 displayed-month)
                     (y2 displayed-year)
                     ;; Absolute date of first/last dates in calendar window.
                     (start-date (progn
                                   (calendar-increment-month m1 y1 -1)
                                   (calendar-absolute-from-gregorian
                                    (list m1 1 y1))))
                     (end-date (progn
                                 (calendar-increment-month m2 y2 1)
                                 (calendar-absolute-from-gregorian
                                  (list m2 (calendar-last-day-of-month m2 y2)
                                        y2))))
                     ;; Local date of first/last date in calendar window.
                     (local-start (calendar-chinese-from-absolute start-date))
                     (local-end (calendar-chinese-from-absolute end-date))
                     ;; When Chinese New Year is visible on the far
                     ;; right of the calendar, what is the earliest
                     ;; Chinese month in the previous year that might
                     ;; still visible?  This test doesn't have to be precise.
                     (local (if (< month 10) local-end local-start))
                     (cycle (car local))
                     (year (cadr local)))
                (calendar-chinese-to-absolute (list cycle year month day)))
            ;; Simple form for when new years are not visible.
            (+ (cadr (assoc month (calendar-chinese-year displayed-year)))
               (1- day))))))
    (if (calendar-date-is-visible-p date)
        (list (list date string)))))

;;;###cal-autoload
(defun calendar-chinese-date-string (&optional date)
  "String of Chinese date of Gregorian DATE.
Defaults to today's date if DATE is not given."
  (let* ((a-date (calendar-absolute-from-gregorian
                  (or date (calendar-current-date))))
         (c-date (calendar-chinese-from-absolute a-date))
         (cycle (car c-date))
         (year (cadr c-date))
         (month (nth 2 c-date))
         (day (nth 3 c-date))
         (this-month (calendar-chinese-to-absolute
                      (list cycle year month 1)))
         (next-month (calendar-chinese-to-absolute
                      (list (if (= year 60) (1+ cycle) cycle)
                            (if (= (floor month) 12) (1+ year) year)
                            ;; Remainder of (1+(floor month))/12, with
                            ;; 12 instead of 0.
                            (1+ (mod (floor month) 12))
                            1))))
    (format "Cycle %s, year %s (%s), %smonth %s%s, day %s (%s)"
            cycle
            year (calendar-chinese-sexagesimal-name year)
            (if (not (integerp month))
                "second "
              (if (< 30 (- next-month this-month))
                  "first "
                ""))
            (floor month)
            (if (integerp month)
                (format " (%s)" (calendar-chinese-sexagesimal-name
                                 (+ (* 12 year) month 50)))
              "")
            day (calendar-chinese-sexagesimal-name (+ a-date 15)))))

;;;###cal-autoload
(defun calendar-chinese-print-date ()
  "Show the Chinese date equivalents of date."
  (interactive)
  (message "Computing Chinese date...")
  (message "Chinese date: %s"
           (calendar-chinese-date-string (calendar-cursor-to-date t))))

(defun calendar-chinese-months-to-alist (l)
  "Make list of months L into an assoc list."
  (and l (car l)
       (if (and (cdr l) (cadr l))
           (if (= (car l) (floor (cadr l)))
               (append
                (list (cons (format "%s (first)" (car l)) (car l))
                      (cons (format "%s (second)" (car l)) (cadr l)))
                (calendar-chinese-months-to-alist (cddr l)))
             (append
              (list (cons (number-to-string (car l)) (car l)))
              (calendar-chinese-months-to-alist (cdr l))))
         (list (cons (number-to-string (car l)) (car l))))))

(defun calendar-chinese-months (c y)
  "A list of the months in cycle C, year Y of the Chinese calendar."
  (memq 1 (append
           (mapcar (lambda (x)
                     (car x))
                   (calendar-chinese-year (calendar-extract-year
                                           (calendar-gregorian-from-absolute
                                            (calendar-chinese-to-absolute
                                             (list c y 1 1))))))
           (mapcar (lambda (x)
                     (if (> (car x) 11) (car x)))
                   (calendar-chinese-year (calendar-extract-year
                                           (calendar-gregorian-from-absolute
                                            (calendar-chinese-to-absolute
                                             (list (if (= y 60) (1+ c) c)
                                                   (if (= y 60) 1 y)
                                                   1 1)))))))))

;;;###cal-autoload
(defun calendar-chinese-goto-date (date &optional noecho)
  "Move cursor to Chinese date DATE.
Echo Chinese date unless NOECHO is non-nil."
  (interactive
   (let* ((c (calendar-chinese-from-absolute
              (calendar-absolute-from-gregorian (calendar-current-date))))
          (cycle (calendar-read-sexp
                  "Chinese calendar cycle number (>44)"
                  (lambda (x) (> x 44))
                  (car c)))
          (year (calendar-read-sexp
                 "Year in Chinese cycle (1..60)"
                 (lambda (x) (and (<= 1 x) (<= x 60)))
                 (cadr c)))
          (month-list (calendar-chinese-months-to-alist
                       (calendar-chinese-months cycle year)))
          (month (cdr (assoc
                       (completing-read "Chinese calendar month: "
                                        month-list nil t)
                       month-list)))
          (last (if (= month
                       (nth 2
                            (calendar-chinese-from-absolute
                             (+ 29
                                (calendar-chinese-to-absolute
                                 (list cycle year month 1))))))
                    30
                  29))
          (day (calendar-read-sexp
                "Chinese calendar day (1-%d)"
                (lambda (x) (and (<= 1 x) (<= x last)))
                1
                last)))
     (list (list cycle year month day))))
  (calendar-goto-date (calendar-gregorian-from-absolute
                       (calendar-chinese-to-absolute date)))
  (or noecho (calendar-chinese-print-date)))

;; The function below is designed to be used in sexp diary entries,
;; and may be present in users' diary files, so suppress the warning
;; about this prefix-less dynamic variable.  It's called from
;; `diary-list-sexp-entries', which binds the variable.
(with-suppressed-warnings ((lexical date))
  (defvar date))

;;;###diary-autoload
(defun diary-chinese-date ()
  "Chinese calendar equivalent of date diary entry."
  (format "Chinese date: %s" (calendar-chinese-date-string date)))

;;;; diary support

(autoload 'calendar-mark-1         "diary-lib")
(autoload 'diary-mark-entries-1    "diary-lib")
(autoload 'diary-list-entries-1    "diary-lib")
(autoload 'diary-insert-entry-1    "diary-lib")
(autoload 'diary-date-display-form "diary-lib")
(autoload 'diary-make-date         "diary-lib")
(autoload 'diary-ordinal-suffix    "diary-lib")
(defvar diary-sexp-entry-symbol)
;; `diary-chinese-anniversary' can be used in users' diary files, and
;; `entry' har to be dynamically bound when that is called.
(with-suppressed-warnings ((lexical entry))
  (defvar entry))                    ;used by `diary-chinese-anniversary'

(defvar calendar-chinese-month-name-array
  ["正月" "二月" "三月" "四月" "五月" "六月"
   "七月" "八月" "九月" "十月" "冬月" "臘月"])

;; NOTE: In the diary the cycle and year of a Chinese date is
;; combined using this formula: (+ (* cycle 100) year).
;;;
;; These two functions convert to and back from this representation.
(defun calendar-chinese-from-absolute-for-diary (thedate)
  (pcase-let ((`(,c ,y ,m ,d) (calendar-chinese-from-absolute thedate)))
    ;; Note: For leap months M is a float.
    (list (floor m) d (+ (* c 100) y))))

(defun calendar-chinese-to-absolute-for-diary (thedate &optional prefer-leap)
  (pcase-let* ((`(,m ,d ,y) thedate)
               (cycle (floor y 100))
               (year (mod y 100))
               (months (calendar-chinese-months cycle year))
               (lm (+ (floor m) 0.5)))
    (calendar-chinese-to-absolute
     (if (and prefer-leap (memql lm months))
         (list cycle year lm d)
       (list cycle year m d)))))

(defun calendar-chinese-mark-date-pattern (month day year &optional color)
  (calendar-mark-1 month day year
                   #'calendar-chinese-from-absolute-for-diary
                   #'calendar-chinese-to-absolute-for-diary
                   color)
  (unless (zerop month)
    (calendar-mark-1 month day year
                     #'calendar-chinese-from-absolute-for-diary
                     (lambda (thedate)
                       (calendar-chinese-to-absolute-for-diary thedate t))
                     color)))

;;;###cal-autoload
(defun diary-chinese-mark-entries ()
  "Mark days in the calendar window that have Chinese date diary entries.
Marks each entry in `diary-file' (or included files) visible in the calendar
window.  See `diary-chinese-list-entries' for more information.

This function is provided for use with `diary-nongregorian-marking-hook'."
  (diary-mark-entries-1 #'calendar-chinese-mark-date-pattern
                        calendar-chinese-month-name-array
                        diary-chinese-entry-symbol
                        #'calendar-chinese-from-absolute-for-diary))

;;;###cal-autoload
(defun diary-chinese-list-entries ()
  "Add any Chinese date entries from the diary file to `diary-entries-list'.
Chinese date diary entries must be prefixed by `diary-chinese-entry-symbol'
\(normally a `C').  The same `diary-date-forms' govern the style
of the Chinese calendar entries.  If a Chinese date diary entry begins with
`diary-nonmarking-symbol', the entry will appear in the diary listing,
but will not be marked in the calendar.

This function is provided for use with `diary-nongregorian-listing-hook'."
  (diary-list-entries-1 calendar-chinese-month-name-array
                        diary-chinese-entry-symbol
                        #'calendar-chinese-from-absolute-for-diary))

;;;###cal-autoload
(defun diary-chinese-anniversary (month day &optional year mark)
  "Like `diary-anniversary' (which see) but accepts Chinese date."
  (pcase-let* ((ddate (diary-make-date month day year))
               (`(,dc ,dy ,dm ,dd)      ;diary chinese date
                (if year
                    (calendar-chinese-from-absolute
                     (calendar-chinese-to-absolute-for-diary ddate))
                  (list nil nil (calendar-extract-month ddate)
                        (calendar-extract-day ddate))))
               (`(,cc ,cy ,cm ,cd)      ;current chinese date
                (calendar-chinese-from-absolute
                 (calendar-absolute-from-gregorian date)))
               (diff (if (and dc dy)
                         (+ (* 60 (- cc dc)) (- cy dy))
                       100)))
    (and (> diff 0)
         ;; The Chinese month can differ by 0.5 in a leap month.
         (or (= dm cm) (= (+ 0.5 dm) cm))
         (= dd cd)
         (cons mark (format entry diff (diary-ordinal-suffix diff))))))

;;;###cal-autoload
(defun diary-chinese-insert-anniversary-entry (&optional arg)
  "Insert an anniversary diary entry for the Chinese date at point.
Prefix argument ARG makes the entry nonmarking."
  (interactive "P")
  (let ((calendar-date-display-form (diary-date-display-form)))
    (diary-make-entry
     (format "%s(diary-chinese-anniversary %s)"
             diary-sexp-entry-symbol
             (calendar-date-string
              (calendar-chinese-from-absolute-for-diary
               (calendar-absolute-from-gregorian (calendar-cursor-to-date t)))))
     arg)))

;;;###cal-autoload
(defun diary-chinese-insert-entry (&optional arg)
  "Insert a diary entry for the Chinese date at point."
  (interactive "P")
  (diary-insert-entry-1 nil arg calendar-chinese-month-name-array
                        diary-chinese-entry-symbol
                        #'calendar-chinese-from-absolute-for-diary))

;;;###cal-autoload
(defun diary-chinese-insert-monthly-entry (&optional arg)
  "Insert a monthly diary entry for the Chinese date at point."
  (interactive "P")
  (diary-insert-entry-1 'monthly arg calendar-chinese-month-name-array
                        diary-chinese-entry-symbol
                        #'calendar-chinese-from-absolute-for-diary))

;;;###cal-autoload
(defun diary-chinese-insert-yearly-entry (&optional arg)
  "Insert a yearly diary entry for the Chinese date at point."
  (interactive "P")
  (diary-insert-entry-1 'yearly arg calendar-chinese-month-name-array
                        diary-chinese-entry-symbol
                        #'calendar-chinese-from-absolute-for-diary))

(provide 'cal-china)

;;; cal-china.el ends here
