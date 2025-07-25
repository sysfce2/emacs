;;; view.el --- peruse file or buffer without editing  -*- lexical-binding: t -*-

;; Copyright (C) 1985-2025 Free Software Foundation, Inc.

;; Author: K. Shane Hartman
;; Maintainer: emacs-devel@gnu.org
;; Keywords: files

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

;; This package provides the `view' minor mode documented in the Emacs
;; user's manual.
;;
;; View mode entry and exit is done through the functions `view-mode-enter'
;; and `view-mode-exit'.  Use these functions to enter or exit `view-mode' from
;; Emacs Lisp programs.
;;
;; We use both view- and View- as prefix for symbols.  View- is used as
;; prefix for commands that have a key binding.  view- is used for commands
;; without key binding.  The purpose of this is to make it easier for a
;; user to use command name completion.

;;; Suggested key bindings:
;;
;; (keymap-set ctl-x-4-map "v" #'view-file-other-window)  ; C-x 4 v
;; (keymap-set ctl-x-5-map "v" #'view-file-other-frame)   ; C-x 5 v
;;
;; You could also bind `view-file', `view-buffer', `view-buffer-other-window' and
;; `view-buffer-other-frame' to keys.

;;; Code:

(defgroup view nil
  "Peruse file or buffer without editing."
  :link '(function-link view-mode)
  :link '(custom-manual "(emacs)Misc File Ops")
  :group 'text)

(defcustom view-highlight-face 'highlight
  "The face used for highlighting the match found by View mode search."
  :type 'face)

(defcustom view-scroll-auto-exit nil
  "Non-nil means scrolling past the end of buffer exits View mode.
A value of nil means attempting to scroll past the end of the buffer,
only rings the bell and gives a message on how to leave."
  :type 'boolean)

(defcustom view-try-extend-at-buffer-end nil
 "Non-nil means try to load more of file when reaching end of buffer.
This variable is mainly intended to be temporarily set to non-nil by
the F command in `view-mode', but you can set it to t if you want the action
for all scroll commands in view mode."
  :type 'boolean)

(defcustom view-exits-all-viewing-windows nil
  "Non-nil means restore all windows used to view buffer.
Commands that restore windows when finished viewing a buffer,
apply to all windows that display the buffer and have restore
information.  If `view-exits-all-viewing-windows' is nil, only
the selected window is considered for restoring."
  :type 'boolean)

(defcustom view-inhibit-help-message nil
  "Non-nil inhibits the help message shown upon entering View mode.
This setting takes effect only when View mode is entered via an
interactive command; otherwise the help message is not shown."
  :type 'boolean
  :version "22.1")

;;;###autoload
(defvar-local view-mode nil
  "Non-nil if View mode is enabled.
Don't change this variable directly, you must change it by one of the
functions that enable or disable view mode.")

(defcustom view-mode-hook nil
  "Normal hook run when starting to view a buffer or file."
  :type 'hook)

(defvar-local view-old-buffer-read-only nil)

(defvar-local view-page-size nil
  "Default number of lines to scroll by View page commands.
If nil that means use the window size.")

(defvar-local view-half-page-size nil
  "Default number of lines to scroll by View half page commands.
If nil that means use half the window size.")

(defvar-local view-last-regexp nil) ; Global is better???

(defvar-local view-exit-action nil
  "If non-nil, a function called when finished viewing.
The function should take one argument (a buffer).
Commands like \\[view-file] and \\[view-file-other-window] may
set this to bury or kill the viewed buffer.
Observe that the buffer viewed might not appear in any window at
the time this function is called.")

(defvar view-no-disable-on-exit nil
  "If non-nil, View mode \"exit\" commands don't actually disable View mode.
Instead, these commands just switch buffers or windows.
This is set in certain buffers by specialized features such as help commands
that use View mode automatically.")

(defvar-local view-overlay nil
  "Overlay used to display where a search operation found its match.
This is local in each buffer, once it is used.")


;; Some redundant "less"-like key bindings below have been commented out.
(defvar-keymap view-mode-map
  :doc "Keymap for `view-mode'."
  "C"     #'View-kill-and-leave
  "c"     #'View-leave
  "Q"     #'View-quit-all
  "E"     #'View-exit-and-edit
  ;; "v"  #'View-exit
  "e"     #'View-exit
  "q"     #'View-quit
  ;; "N"  #'View-search-last-regexp-backward
  "p"     #'View-search-last-regexp-backward
  "n"     #'View-search-last-regexp-forward
  ;; "?"  #'View-search-regexp-backward ; Less does this.
  "\\"    #'View-search-regexp-backward
  "/"     #'View-search-regexp-forward
  "r"     #'isearch-backward
  "s"     #'isearch-forward
  "m"     #'point-to-register
  "'"     #'register-to-point
  "x"     #'exchange-point-and-mark
  "@"     #'View-back-to-mark
  "."     #'set-mark-command
  "%"     #'View-goto-percent
  ;; "G"  #'View-goto-line-last
  "g"     #'View-goto-line
  "="     #'what-line
  "F"     #'View-revert-buffer-scroll-page-forward
  ;; "k"  #'View-scroll-line-backward
  "y"     #'View-scroll-line-backward
  ;; "j"  #'View-scroll-line-forward
  "C-j"   #'View-scroll-line-forward
  "RET"   #'View-scroll-line-forward
  "u"     #'View-scroll-half-page-backward
  "d"     #'View-scroll-half-page-forward
  "z"     #'View-scroll-page-forward-set-page-size
  "w"     #'View-scroll-page-backward-set-page-size
  ;; "b"  #'View-scroll-page-backward
  "DEL"   #'View-scroll-page-backward
  ;; "f"  #'View-scroll-page-forward
  "SPC"   #'View-scroll-page-forward
  "S-SPC" #'View-scroll-page-backward
  "o"     #'View-scroll-to-buffer-end
  ">"     #'end-of-buffer
  "<"     #'beginning-of-buffer
  "-"     #'negative-argument
  "9"     #'digit-argument
  "8"     #'digit-argument
  "7"     #'digit-argument
  "6"     #'digit-argument
  "5"     #'digit-argument
  "4"     #'digit-argument
  "3"     #'digit-argument
  "2"     #'digit-argument
  "1"     #'digit-argument
  "0"     #'digit-argument
  "H"     #'describe-mode
  "?"     #'describe-mode	; Maybe do as less instead? See above.
  "h"     #'describe-mode)


;;; Commands that enter or exit view mode.

;; This is used when view mode is exited, to make sure we don't try to
;; kill a buffer modified by the user.  A buffer in view mode can
;; become modified if the user types C-x C-q, edits the buffer, then
;; types C-x C-q again to return to view mode.
;;;###autoload
(defun kill-buffer-if-not-modified (buf)
  "Like `kill-buffer', but does nothing if buffer BUF is modified."
  (let ((buf (get-buffer buf)))
    (and buf (not (buffer-modified-p buf))
	 (kill-buffer buf))))

;;;###autoload
(defun view-file (file)
  "View FILE in View mode, returning to previous buffer when done.
Emacs commands editing the buffer contents are not available; instead, a
special set of commands (mostly letters and punctuation) are defined for
moving around in the buffer.
Space scrolls forward, Delete scrolls backward.
For a list of all View commands, type H or h while viewing.

This command runs the normal hook `view-mode-hook'."
  (interactive "fView file: ")
  (unless (file-exists-p file) (error "%s does not exist" file))
  (let ((had-a-buf (get-file-buffer file))
	(buffer (find-file-noselect file)))
    (view-buffer buffer (and (not had-a-buf) 'kill-buffer-if-not-modified))))

;;;###autoload
(defun view-file-other-window (file)
  "View FILE in View mode in another window.
When done, return that window to its previous buffer, and kill the
buffer visiting FILE if unmodified and if it wasn't visited before.

Emacs commands editing the buffer contents are not available; instead,
a special set of commands (mostly letters and punctuation)
are defined for moving around in the buffer.
Space scrolls forward, Delete scrolls backward.
For a list of all View commands, type H or h while viewing.

This command runs the normal hook `view-mode-hook'."
  (interactive "fIn other window view file: ")
  (unless (file-exists-p file) (error "%s does not exist" file))
  (let ((had-a-buf (get-file-buffer file))
	(buf-to-view (find-file-noselect file)))
    (view-buffer-other-window buf-to-view nil
			      (and (not had-a-buf)
				   'kill-buffer-if-not-modified))))

;;;###autoload
(defun view-file-other-frame (file)
  "View FILE in View mode in another frame.
When done, kill the buffer visiting FILE if unmodified and if it wasn't
visited before; also, maybe delete other frame and/or return to previous
buffer.

Emacs commands editing the buffer contents are not available; instead,
a special set of commands (mostly letters and punctuation)
are defined for moving around in the buffer.
Space scrolls forward, Delete scrolls backward.
For a list of all View commands, type H or h while viewing.

This command runs the normal hook `view-mode-hook'."
  (interactive "fIn other frame view file: ")
  (unless (file-exists-p file) (error "%s does not exist" file))
  (let ((had-a-buf (get-file-buffer file))
	(buf-to-view (find-file-noselect file)))
    (view-buffer-other-frame buf-to-view nil
			     (and (not had-a-buf)
				  'kill-buffer-if-not-modified))))


;;;###autoload
(defun view-buffer (buffer &optional exit-action)
  "View BUFFER in View mode, returning to previous buffer when done.
Emacs commands editing the buffer contents are not available; instead, a
special set of commands (mostly letters and punctuation) are defined for
moving around in the buffer.
Space scrolls forward, Delete scrolls backward.
For a list of all View commands, type H or h while viewing.

This command runs the normal hook `view-mode-hook'.

Optional argument EXIT-ACTION is either nil or a function with buffer as
argument.  This function is called when finished viewing buffer.  Use
this argument instead of explicitly setting `view-exit-action'.

Do not set EXIT-ACTION to `kill-buffer' when BUFFER visits a
file: Users may suspend viewing in order to modify the buffer.
Exiting View mode will then discard the user's edits.  Setting
EXIT-ACTION to `kill-buffer-if-not-modified' avoids this.

This function does not enable View mode if the buffer's major mode
has a `special' mode-class, because such modes usually have their
own View-like bindings."
  (interactive "bView buffer: ")
  (switch-to-buffer buffer)
  (if (eq (get major-mode 'mode-class) 'special)
      (message "Not using View mode because the major mode is special")
    (view-mode-enter nil exit-action)))

;;;###autoload
(defun view-buffer-other-window (buffer &optional _not-return exit-action)
  "View BUFFER in View mode in another window.
Emacs commands editing the buffer contents are not available;
instead, a special set of commands (mostly letters and
punctuation) are defined for moving around in the buffer.
Space scrolls forward, Delete scrolls backward.
For a list of all View commands, type H or h while viewing.

This command runs the normal hook `view-mode-hook'.

Optional argument NOT-RETURN is ignored.

Optional argument EXIT-ACTION is either nil or a function with buffer as
argument.  This function is called when finished viewing buffer.  Use
this argument instead of explicitly setting `view-exit-action'.

This function does not enable View mode if the buffer's major mode
has a `special' mode-class, because such modes usually have their
own View-like bindings."
  (interactive "bIn other window view buffer:\nP")
  (let ((pop-up-windows t))
    (pop-to-buffer buffer t))
  (if (eq (get major-mode 'mode-class) 'special)
      (message "Not using View mode because the major mode is special")
    (view-mode-enter nil exit-action)))

;;;###autoload
(defun view-buffer-other-frame (buffer &optional _not-return exit-action)
  "View BUFFER in View mode in another frame.
Emacs commands editing the buffer contents are not available;
instead, a special set of commands (mostly letters and
punctuation) are defined for moving around in the buffer.
Space scrolls forward, Delete scrolls backward.
For a list of all View commands, type H or h while viewing.

This command runs the normal hook `view-mode-hook'.

Optional argument NOT-RETURN is ignored.

Optional argument EXIT-ACTION is either nil or a function with buffer as
argument.  This function is called when finished viewing buffer.  Use
this argument instead of explicitly setting `view-exit-action'.

This function does not enable View mode if the buffer's major mode
has a `special' mode-class, because such modes usually have their
own View-like bindings."
  (interactive "bView buffer in other frame: \nP")
  (let ((pop-up-frames t))
    (pop-to-buffer buffer t))
  (if (eq (get major-mode 'mode-class) 'special)
      (message "Not using View mode because the major mode is special")
    (view-mode-enter nil exit-action)))

;;;###autoload
(define-minor-mode view-mode
  ;; In the following documentation string we have to use some explicit key
  ;; bindings instead of using the \\[] construction.  The reason for this
  ;; is that most commands have more than one key binding.
  "Toggle View mode, a minor mode for viewing text but not editing it.

When View mode is enabled, commands that do not change the buffer
contents are available as usual.  Kill commands save text but
do not delete it from the buffer.  Most other commands beep and
tell the user that the buffer is read-only.

\\<view-mode-map>

The following additional commands are provided.  Most commands
take prefix arguments.  Page commands default to \"page size\"
lines which is almost a whole window, or number of lines set by
\\[View-scroll-page-forward-set-page-size] or \\[View-scroll-page-backward-set-page-size].
Half page commands default to and set \"half page size\" lines
which initially is half a window full.  Search commands default
to a repeat count of one.

H, h, ?	 This message.
Digits	provide prefix arguments.
\\[negative-argument]	negative prefix argument.
\\[beginning-of-buffer]	move to the beginning of buffer.
>	move to the end of buffer.
\\[View-scroll-to-buffer-end]	scroll so that buffer end is at last line of window.
SPC	scroll forward \"page size\" lines.
	  With prefix scroll forward prefix lines.
DEL, S-SPC  scroll backward \"page size\" lines.
	      With prefix scroll backward prefix lines.
\\[View-scroll-page-forward-set-page-size]	like  \\[View-scroll-page-forward]  but with prefix sets \"page size\" to prefix.
\\[View-scroll-page-backward-set-page-size]	like  \\[View-scroll-page-backward]  but with prefix sets \"page size\" to prefix.
\\[View-scroll-half-page-forward]	scroll forward \"half page size\" lines.  With prefix, sets
	  \"half page size\" to prefix lines and scrolls forward that much.
\\[View-scroll-half-page-backward]	scroll backward \"half page size\" lines.  With prefix, sets
	  \"half page size\" to prefix lines and scrolls backward that much.
RET, LFD  scroll forward one line.  With prefix scroll forward prefix line(s).
y	scroll backward one line.  With prefix scroll backward prefix line(s).
\\[View-revert-buffer-scroll-page-forward]	revert-buffer if necessary and scroll forward.
	  Use this to view a changing file.
\\[what-line]	prints the current line number.
\\[View-goto-percent]	goes prefix argument (default 100) percent into buffer.
\\[View-goto-line]	goes to line given by prefix argument (default first line).
.	set the mark.
x	exchanges point and mark.
\\[View-back-to-mark]	return to mark and pops mark ring.
	  Mark ring is pushed at start of every successful search and when
	  jump to line occurs.  The mark is set on jump to buffer start or end.
\\[point-to-register]	save current position in character register.
\\='	go to position saved in character register.
s	do forward incremental search.
r	do reverse incremental search.
\\[View-search-regexp-forward]	searches forward for regular expression, starting after current page.
	  ! and @ have a special meaning at the beginning of the regexp.
	  ! means search for a line with no match for regexp.  @ means start
	  search at beginning (end for backward search) of buffer.
\\	searches backward for regular expression, starting before current page.
\\[View-search-last-regexp-forward]	searches forward for last regular expression.
p	searches backward for last regular expression.
\\[View-quit]	quit View mode, restoring this window and buffer to previous state.
	  \\[View-quit] is the normal way to leave view mode.
\\[View-exit]	exit View mode but stay in current buffer.  Use this if you started
	  viewing a buffer (file) and find out you want to edit it.
	  This command restores the previous read-only status of the buffer.
\\[View-exit-and-edit]	exit View mode, and make the current buffer editable
	  even if it was not editable before entry to View mode.
\\[View-quit-all]	quit View mode, restoring all windows to previous state.
\\[View-leave]	quit View mode and maybe switch buffers, but don't kill this buffer.
\\[View-kill-and-leave]	quit View mode, kill current buffer and go back to other buffer.

The effect of \\[View-leave], \\[View-quit] and \\[View-kill-and-leave] depends on how view-mode was entered.  If it was
entered by view-file, view-file-other-window, view-file-other-frame, or
\\[dired-view-file] \(\\[view-file], \\[view-file-other-window],
\\[view-file-other-frame], or the Dired mode v command),
then \\[View-quit] will try to kill the current buffer.
If view-mode was entered from another buffer, by \\[view-buffer],
\\[view-buffer-other-window], \\[view-buffer-other frame], \\[view-file],
\\[view-file-other-window], or \\[view-file-other-frame],
then \\[View-leave], \\[View-quit] and \\[View-kill-and-leave] will return to that buffer.

Entry to view-mode runs the normal hook `view-mode-hook'."
  :lighter " View" :keymap view-mode-map
  (if view-mode (view--enable) (view--disable)))

(defun view--enable ()
  ;; Always leave view mode before changing major mode.
  ;; This is to guarantee that the buffer-read-only variable is restored.
  (add-hook 'change-major-mode-hook 'view--disable nil t)
  (setq view-page-size nil
	view-half-page-size nil
	view-old-buffer-read-only buffer-read-only
        buffer-read-only t)
  ;; Make reverting the buffer preserve unreadableness.
  (setq-local read-only-mode--state t))


(define-obsolete-function-alias 'view-mode-enable 'view-mode "24.4")
(defun view-mode-disable ()
  "Turn off View mode."
  (declare (obsolete view-mode "24.4"))
  (view-mode -1))

(defun view--disable ()
  (remove-hook 'change-major-mode-hook 'view--disable t)
  (and view-overlay (delete-overlay view-overlay))
  ;; Calling read-only-mode while View mode is enabled
  ;; sets view-read-only to t as a buffer-local variable
  ;; after exiting View mode.  That arranges that the next read-only-mode
  ;; will reenable View mode.
  ;; Canceling View mode in any other way should cancel that, too,
  ;; so that View mode stays off if read-only-mode is called.
  (if (local-variable-p 'view-read-only)
      (kill-local-variable 'view-read-only))
  (if buffer-read-only
      (setq buffer-read-only view-old-buffer-read-only)))

;;;###autoload
(defun view-mode-enter (&optional quit-restore exit-action)
  "Enter View mode and set up exit from view mode depending on optional arguments.
Optional argument QUIT-RESTORE if non-nil must specify a valid
entry for quitting and restoring any window showing the current
buffer.  This entry replaces any parameter installed by
`display-buffer' and is used by `view-mode-exit'.

Optional argument EXIT-ACTION, if non-nil, must specify a
function that takes a buffer as argument.  This function will be
called by `view-mode-exit'.

For a list of all View commands, type H or h while viewing.

This function runs the normal hook `view-mode-hook'."
  (when quit-restore
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-parameter window 'quit-restore quit-restore)))

  (when exit-action
    (setq view-exit-action exit-action))

  (unless view-mode
    (view-mode 1)
    (when (and (not view-inhibit-help-message)
               ;; Avoid spamming the echo area if `view-mode' is entered
               ;; non-interactively, e.g., in a temporary buffer (bug#44629).
               this-command)
      (message "%s"
	       (substitute-command-keys "\
View mode: type \\[help-command] for help, \\[describe-mode] for commands, \\[View-quit] to quit.")))))

;; This is awful because it assumes that the selected window shows the
;; current buffer when this is called.
(defun view-mode-exit (&optional exit-only exit-action all-windows)
  "Exit View mode in various ways.
If all arguments are nil, remove the current buffer from the
selected window using the `quit-restore' information associated
with the selected window.  If optional argument ALL-WINDOWS or
`view-exits-all-viewing-windows' are non-nil, remove the current
buffer from all windows showing it.

Optional argument EXIT-ONLY non-nil means just exit `view-mode'
\(unless `view-no-disable-on-exit' is non-nil) but do not change
the associations of any windows with the current buffer.

EXIT-ACTION, if non-nil, must specify a function that is called
with the current buffer as argument and is called after disabling
`view-mode' and removing any associations of windows with the
current buffer."
  (when view-mode
    (let ((buffer (window-buffer)))
      (unless (or view-no-disable-on-exit
                  ;; When `view-read-only' is non-nil, we don't want to
                  ;; leave a buffer read-only but not in `view-mode'.
                  (and view-read-only view-old-buffer-read-only))
	(view-mode -1))

      (unless exit-only
	(cond
	 ((or all-windows view-exits-all-viewing-windows)
	  (dolist (window (get-buffer-window-list))
	    (quit-window nil window)))
	 ((eq (window-buffer) (current-buffer))
	  (quit-window)))

	(when exit-action
	  (funcall exit-action buffer))))))

(defun View-exit ()
  "Exit View mode but stay in current buffer."
  (interactive)
  (let ((view-read-only nil)
        (view-no-disable-on-exit nil))
   (view-mode-exit t)))

;;;###autoload
(defun View-exit-and-edit ()
  "Exit View mode and make the current buffer editable."
  (interactive)
  (let ((view-old-buffer-read-only nil)
	(view-no-disable-on-exit nil))
    (view-mode-exit t)))

(defun View-leave ()
  "Quit View mode and maybe switch buffers, but don't kill this buffer."
  (interactive)
  (view-mode-exit))

(defun View-quit ()
  "Quit View mode, trying to restore window and buffer to previous state.
Maybe kill this buffer.  Try to restore selected window to previous state
and go to previous buffer or window."
  (interactive)
  (view-mode-exit nil view-exit-action))

(defun View-quit-all ()
  "Quit View mode, trying to restore windows and buffers to previous state.
Maybe kill current buffer.  Try to restore all windows viewing buffer to
previous state and go to previous buffer or window."
  (interactive)
  (view-mode-exit nil view-exit-action t))

(defun View-kill-and-leave ()
  "Quit View mode, kill current buffer and return to previous buffer."
  (interactive)
  (view-mode-exit nil (or view-exit-action 'kill-buffer) t))


;;; Some help routines.

(defun view-window-size ()
  ;; Return the height of the current window, excluding the mode line.
  ;; Using `window-line-height' accounts for variable-height fonts.
  (let ((h (window-line-height -1)))
    (if h
	(1+ (nth 1 h))
      ;; This should not happen, but if `window-line-height' returns
      ;; nil, fall back on `window-height'.
      (1- (window-height)))))

;; (defun view-last-command (&optional who what)
;;  (setq view-last-command-entry this-command)
;;  (setq view-last-command who)
;;  (setq view-last-command-argument what))

;; (defun View-repeat-last-command ()
;;  "Repeat last command issued in View mode."
;;  (interactive)
;;  (if (and view-last-command
;; 	   (eq view-last-command-entry last-command))
;;      (funcall view-last-command view-last-command-argument))
;;  (setq this-command view-last-command-entry))

(defun view-recenter ()
  ;; Recenter point in window and redisplay normally.
  (recenter '(1)))

(defun view-page-size-default (lines)
  "If LINES is nil, 0, or larger than `view-window-size', return nil.
Otherwise, return LINES."
  (and lines
       (not (zerop (setq lines (prefix-numeric-value lines))))
       (<= (abs lines)
	   (abs (- (view-window-size) next-screen-context-lines)))
       (abs lines)))

(defun view-set-half-page-size-default (lines)
  "Get and maybe set half page size."
  (if (not lines) (or view-half-page-size
		      (/ (view-window-size) 2))
    (setq view-half-page-size
	  (if (zerop (setq lines (prefix-numeric-value lines)))
	      (/ (view-window-size) 2)
	    (view-page-size-default lines)))))


;;; Commands for moving around in the buffer.

(defun View-goto-percent (&optional percent)
  "Move to end (or prefix PERCENT) of buffer in View mode.
Display is centered at point.
Also set the mark at the position where point was."
  (interactive "P")
  (push-mark)
  (goto-char
   (if percent
       (+ (point-min)
	  (floor (* (- (point-max) (point-min)) 0.01
		    (max 0 (min 100 (prefix-numeric-value percent))))))
     (point-max)))
  (view-recenter))

;; (defun View-goto-line-last (&optional line)
;; "Move to last (or prefix LINE) line in View mode.
;; Display is centered at LINE.
;; Sets mark at starting position and pushes mark ring."
;;  (interactive "P")
;;  (push-mark)
;;  (if line (goto-line (prefix-numeric-value line))
;;    (goto-char (point-max))
;;    (beginning-of-line))
;;  (view-recenter))

(defun View-goto-line (&optional line)
  "Move to first (or prefix LINE) line in View mode.
Display is centered at LINE.
Also set the mark at the position where point was."
  (interactive "p")
  (push-mark)
  (goto-char (point-min))
  (forward-line (1- line))
  (view-recenter))

(defun View-back-to-mark (&optional _ignore)
  "Return to last mark set in View mode, else beginning of file.
Display that line at the center of the window.
This command pops the mark ring, so that successive
invocations return to earlier marks."
  (interactive)
  (goto-char (or (mark t) (point-min)))
  (pop-mark)
  (view-recenter))

(defun view-scroll-lines (lines backward default maxdefault)
  ;; This function does the job for all the scrolling commands.
  ;; Scroll forward LINES lines.  If BACKWARD is non-nil, scroll backwards.
  ;; If LINES is negative scroll in the other direction.
  ;; If LINES is 0 or nil, scroll DEFAULT lines (if DEFAULT is nil, scroll
  ;; by one page).  If MAXDEFAULT is non-nil, scroll no more than a window.
  (if (or (null lines) (zerop (setq lines (prefix-numeric-value lines))))
      (setq lines default))
  (when (and lines (< lines 0))
    (setq backward (not backward) lines (- lines)))
  (when (and maxdefault lines (> lines (view-window-size)))
    (setq lines nil))
  (cond (backward (scroll-down-command lines))
	((view-really-at-end)
	 (if view-scroll-auto-exit
	     (View-quit)
	   (ding)
	   (view-end-message)))
	(t (scroll-up-command lines)
	   (if (view-really-at-end) (view-end-message)))))

(defun view-really-at-end ()
  "Return non-nil if buffer end visible.  Maybe revert buffer and test."
  (and (or (null scroll-error-top-bottom) (eobp))
       (pos-visible-in-window-p (point-max))
       (let ((buf (current-buffer))
	     (bufname (buffer-name))
	     (file (buffer-file-name)))
	 (or (not view-try-extend-at-buffer-end)
	     (null file)
	     (verify-visited-file-modtime buf)
	     (not (file-exists-p file))
	     (when (buffer-modified-p buf)
	       (setq file (file-name-nondirectory file))
	       (not (yes-or-no-p
		     (format
		      "File %s changed on disk.  Discard your edits%s? "
		      file
		      (if (string= bufname file) ""
			(concat " in " bufname))))))
	     (progn
	       (revert-buffer t t t)
	       (pos-visible-in-window-p (point-max)))))))

(defun view-end-message ()
  "Tell that we are at end of buffer."
  (goto-char (point-max))
  (if (window-parameter nil 'quit-restore)
      (message "End of buffer.  Type %s to quit viewing."
	       (substitute-command-keys
		(if view-scroll-auto-exit "\\[View-scroll-page-forward]"
		  "\\[View-quit]")))
    (message "End of buffer")))

(defun View-scroll-to-buffer-end ()
  "Scroll backward or forward so that buffer end is at last line of window."
  (interactive)
  (let ((p (if (pos-visible-in-window-p (point-max)) (point))))
    (goto-char (point-max))
    (recenter -1)
    (and p (goto-char p))))

(defun View-scroll-page-forward (&optional lines)
  "Scroll \"page size\" or prefix LINES lines forward in View mode.
Exit if end of text is visible and `view-scroll-auto-exit' is non-nil.
\"page size\" is whole window full, or number of lines set by
\\[View-scroll-page-forward-set-page-size] or
\\[View-scroll-page-backward-set-page-size].
If LINES is more than a window-full, only the last window-full is shown."
  (interactive "P")
  (view-scroll-lines lines nil (view-page-size-default view-page-size) nil))

(defun View-scroll-page-backward (&optional lines)
  "Scroll \"page size\" or prefix LINES lines backward in View mode.
See also `View-scroll-page-forward'."
  (interactive "P")
  (view-scroll-lines lines t (view-page-size-default view-page-size) nil))

(defun View-scroll-page-forward-set-page-size (&optional lines)
  "Scroll forward LINES lines in View mode, setting the \"page size\".
This is the number of lines which \\[View-scroll-page-forward] and
\\[View-scroll-page-backward] scroll by default.
If LINES is omitted or = 0, sets \"page size\" to window height and
scrolls forward that much, otherwise scrolls forward LINES lines and sets
\"page size\" to the minimum of window height and the absolute value of LINES.
See also `View-scroll-page-forward'."
  (interactive "P")
  (view-scroll-lines lines nil
		     (setq view-page-size (view-page-size-default lines))
		     nil))

(defun View-scroll-page-backward-set-page-size (&optional lines)
  "Scroll backward prefix LINES lines in View mode, setting the \"page size\".
See also `View-scroll-page-forward-set-page-size'."
  (interactive "P")
  (view-scroll-lines lines t
		     (setq view-page-size (view-page-size-default lines))
		     nil))

(defun View-scroll-line-forward (&optional lines)
  "Scroll forward one line (or prefix LINES lines) in View mode.
See also `View-scroll-page-forward', but note that scrolling is limited
to minimum of LINES and one window-full."
  (interactive "P")
  (view-scroll-lines lines nil 1 t))

(defun View-scroll-line-backward (&optional lines)
  "Scroll backward one line (or prefix LINES lines) in View mode.
See also `View-scroll-line-forward'."
  (interactive "P")
  (view-scroll-lines lines t 1 t))

(defun View-scroll-half-page-forward (&optional lines)
  "Scroll forward a \"half page\" (or prefix LINES) lines in View mode.
If LINES is not omitted, the \"half page size\" is set to the minimum of
window height and the absolute value of LINES.
LINES=0 resets \"half page size\" to half window height."
  (interactive "P")
  (view-scroll-lines lines nil (view-set-half-page-size-default lines) t))

(defun View-scroll-half-page-backward (&optional lines)
  "Scroll backward a \"half page\" (or prefix LINES) lines in View mode.
See also `View-scroll-half-page-forward'."
  (interactive "P")
  (view-scroll-lines lines t (view-set-half-page-size-default lines) t))

(defun View-revert-buffer-scroll-page-forward (&optional lines)
  "Scroll forward, reverting buffer if needed, in View mode.
If buffer has not been changed and the corresponding file is newer, first
revert the buffer, then scroll.
This command is useful if you are viewing a changing file.

The prefix argument LINES says how many lines to scroll.
If you don't specify a prefix argument, it uses the number of lines set by
\\[View-scroll-page-forward-set-page-size] or
\\[View-scroll-page-backward-set-page-size].
If LINES is more than a window-full, only the last window-full is shown."
  (interactive "P")
  (let ((view-scroll-auto-exit nil)
	(view-try-extend-at-buffer-end t))
    (view-scroll-lines lines nil (view-page-size-default view-page-size) nil)))

(defun View-search-regexp-forward (n regexp)
  "Search forward for first (or prefix Nth) occurrence of REGEXP in View mode.

Displays line found at center of window.  Sets mark at starting position and
pushes mark ring.

Characters @ and ! are special at the beginning of REGEXP.  They modify
the search rather than become part of the pattern searched for.
@ means search all the buffer i.e. start search at the beginning of buffer.
! means search for a line that contains no match for the pattern.
If REGEXP is empty or only consist of these control characters, then
an earlier remembered REGEXP is used, otherwise REGEXP is remembered
for use by later search commands.

The variable `view-highlight-face' controls the face that is used
for highlighting the match that is found."
  (interactive "p\nsSearch forward (regexp): ")
  (view-search n regexp))

(defun View-search-regexp-backward (n regexp)
  "Search backward for first (or prefix Nth) occurrence of REGEXP in View mode.

Displays line found at center of window.  Sets mark at starting position and
pushes mark ring.

Characters @ and ! are special at the beginning of REGEXP.  They modify
the search rather than become part of the pattern searched for.
@ means search all the buffer i.e. start search at the end of buffer.
! means search for a line that contains no match for the pattern.
If REGEXP is empty or only consist of these control characters, then
an earlier remembered REGEXP is used, otherwise REGEXP is remembered
for use by later search commands.

The variable `view-highlight-face' controls the face that is used
for highlighting the match that is found."
  (interactive "p\nsSearch backward (regexp): ")
  (view-search (- n) regexp))

(defun View-search-last-regexp-forward (n) "\
Search forward for first (or prefix Nth) instance of last regexp in View mode.
Displays line found at center of window.  Sets mark at starting position and
pushes mark ring.

The variable `view-highlight-face' controls the face that is used
for highlighting the match that is found."
  (interactive "p")
  (view-search n nil))

(defun View-search-last-regexp-backward (n) "\
Search backward for first (or prefix Nth) instance of last regexp in View mode.
Displays line found at center of window.  Sets mark at starting position and
pushes mark ring.

The variable `view-highlight-face' controls the face that is used
for highlighting the match that is found."
  (interactive "p")
  (view-search (- n) nil))

(defun view-search (times regexp)
  ;; This function does the job for all the View-search- commands.
  ;; Search for the TIMESth match for REGEXP.  If TIMES is negative
  ;; search backwards.  If REGEXP is nil use `view-last-regexp'.
  ;; Characters "!" and "@" have a special meaning at the beginning of
  ;; REGEXP and are removed from REGEXP before the search "!" means
  ;; search for lines with no match for REGEXP.  "@" means search in
  ;; the whole buffer, don't start searching from the present point.
  (let (where no end ln)
    (cond
     ((and regexp (> (length regexp) 0)
	   (or (not (memq (string-to-char regexp) '(?! ?@)))
	       (progn
		 (if (member (substring regexp 0 2) '("!@" "@!"))
		     (setq end t no t ln 2)
		   (setq no (not (setq end (eq ?@ (string-to-char regexp))))
			 ln 1))
		 (> (length (setq regexp (substring regexp ln))) 0))))
      (setq view-last-regexp (if no (list regexp) regexp)))
     ((consp view-last-regexp)
      (setq regexp (car view-last-regexp))
      (unless (setq no (not no)) (setq view-last-regexp regexp)))
     (view-last-regexp (setq regexp view-last-regexp)
		       (if no (setq view-last-regexp (list regexp))))
     (t (error "No previous View-mode search")))
    (save-excursion
      (if end (goto-char (if (< times 0) (point-max) (point-min)))
        (if (< times 0)
            (beginning-of-line)
          (end-of-line)))
      (if (if no (view-search-no-match-lines times regexp)
	    (re-search-forward regexp nil t times))
	  (setq where (point))))
    (if where
	(progn
	  (push-mark)
	  (goto-char where)
	  (if view-overlay
	      (move-overlay view-overlay (match-beginning 0) (match-end 0))
	    (setq view-overlay
		  (make-overlay (match-beginning 0) (match-end 0))))
	  (overlay-put view-overlay 'face view-highlight-face)
	  (beginning-of-line)
	  (view-recenter))
      (message "Can't find occurrence %d of %s%s"
	       times (if no "no " "") regexp)
      (sit-for 4))))

;; This is the dumb approach, looking at each line.  The original
;; version of this function looked like it might have been trying to
;; do something clever, but not succeeding:
;; https://lists.gnu.org/r/bug-gnu-emacs/2007-09/msg00073.html
(defun view-search-no-match-lines (times regexp)
  "Search for the TIMESth occurrence of a line with no match for REGEXP.
If such a line is found, return non-nil and set the match data to that line.
If TIMES is negative, search backwards."
  (let ((step (if (>= times 0) 1
                (setq times (- times))
                -1)))
    ;; Note that we do not check the current line.
    (while (and (> times 0)
                (zerop (forward-line step)))
      ;; (forward-line 1) returns 0 on moving within the last line.
      (if (eobp)
          (setq times -1)
        (or (re-search-forward regexp (line-end-position) t)
            (setq times (1- times))))))
  (and (zerop times)
       (looking-at ".*")))

(defvar-local view-old-Helper-return-blurb nil)
(make-obsolete 'view-old-Helper-return-blurb nil "29.1")

(provide 'view)

;;; view.el ends here
