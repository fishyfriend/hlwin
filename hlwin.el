;;; hlwin --- Highlight the active window -*- lexical-binding: t -*-

;; Copyright (C) 2020 Jacob First

;; Author: Jacob First <jacob.first@member.fsf.org>
;; Version: 0.1
;; Package-Requires: ((emacs "26.3"))
;; Keywords: convenience
;; URL: https://github.com/fishyfriend/hlwin

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This package is not maintained.  Please see DEPRECATION NOTICE in the readme!
;;
;; hlwin provides a global minor mode for highlighting the active window.
;;
;; Quickstart:
;;
;; Download hlwin.el and place it somewhere in your Emacs load path.  Then
;; run:
;;
;;     (hlwin-mode 1)
;;
;; Alternately, with use-package:
;;
;;     (use-package hlwin :config (hlwin-mode 1))
;;
;; Configuration:
;;
;; By default, hlwin leaves the active window unchanged and lightens the
;; background of inactive windows by 5%.  Alternatively, you might prefer:
;;
;;     (setq hlwin-overlay-face (hlwin-darken 5))
;;
;; `hlwin-overlay-face' can be used for customization of the background color
;; generally, including selectively excluding some windows from alteration.
;;
;; If you frequently change themes, you may wish to install `hlwin-reset' as a
;; hook or advice that runs after loading a new theme.  This will regenerate
;; window modifications in accordance with theme colors.
;;
;; hlwin has two modes of operation.  It can highlight the active window by
;; applying an overlay to it directly, or it can apply overlays to all visible
;; inactive windows to effectively "highlight" the active one.  This choice is
;; configured via `hlwin-overlay-active-window'.  The latter method is the
;; default.  Several widely-used Emacs packages, such as hl-line and Company,
;; also use overlays, and hlwin's overlays don't always play well with them.
;; For example, the background highlight of `hl-line-mode' is totally obscured
;; by hlwin.  These interactions are less disruptive when they occur in inactive
;; windows, so it is recommended to stick with the default setting for
;; `hlwin-overlay-active-window'.
;;
;; Known issues:
;;
;; Minor visual artifacts are sometimes visible at the end of buffers, e.g. the
;; *Messages* buffer.
;;
;; Sometimes a window may scroll unexpectedly after becoming unselected.  The
;; amount of scrolling is usually not enough to matter.  If you see otherwise,
;; please report an issue (or send a patch!).
;;
;; As mentioned above, you may encounter visual or other issues with other
;; packages that use overlays.  Keep `hlwin-overlay-active-window' set to nil
;; to mitigate these problems.
;;
;; Goodies:
;;
;; If you use header lines, you've probably discovered that Emacs doesn't
;; provide separate header line faces for active and inactive windows the way it
;; does for the mode line.  You can display your header line using the
;; appropriate mode line face -- `mode-line' or `mode-line-inactive' -- by
;; wrapping your `header-line-format' with `hlwin-with-mode-line-face'.  It
;; should not be difficult to customize this function to use other faces if
;; desired.
;;
;; Credits:
;;
;; The idea for how to implement active window tracking comes from
;; telephone-line (https://github.com/dbordak/telephone-line).

;;; Code:

(require 'color)
(require 'subr-x)

(defgroup hlwin nil
  "Highlight the active window."
  :group 'convenience
  :prefix "hlwin-")

(define-minor-mode hlwin-mode
  "Global minor mode for highlighting the active window."
  nil nil nil :global t
  (if hlwin-mode
      (hlwin-reset)
    (hlwin--remove-overlays t)))

(defvar hlwin--active-window nil)
(defvar hlwin--previous-active-window nil)

(defun hlwin--set-active-window (_window)
  "Update the active window if needed.  Call from `pre-redisplay-functions'."
  (let ((window (frame-selected-window)))
    (unless (or (minibuffer-window-active-p window)
                (eq window hlwin--active-window))
      (setq hlwin--previous-active-window hlwin--active-window
            hlwin--active-window window)
      (run-hooks 'hlwin-active-window-update-hook))))

(add-hook 'pre-redisplay-functions 'hlwin--set-active-window)

(defun hlwin-active-window ()
  "Return the active non-minibuffer window as seen by the user.
This can be used to get the \"real\" selected window during redisplay."
  hlwin--active-window)

(defun hlwin-window-active-p (&optional window)
  "Return non-nil if WINDOW is the active non-minibuffer window.
WINDOW defaults to the selected window.
This function is equivalent to (eq WINDOW (hlwin-active-window))."
  (eq (or window (selected-window)) (hlwin-active-window)))

(defun hlwin-previous-active-window ()
  "Return the prior active window as given by `hlwin-active-window'."
  hlwin--previous-active-window)

(defun hlwin-active-window-update-hook nil
  "Hook run just after the active window is changed.")

(defcustom hlwin-overlay-active-windows nil
  "Whether to apply overlays to active or inactive windows.

If non-nil, an overlay will be applied to the active window.  If
nil (the default), overlays will be applied to all visible
inactive windows instead.

It is recommended to keep the default setting in order to avoid compatibility
issues with other packages that use overlays."
  :group 'hlwin
  :type 'boolean)

(defcustom hlwin-overlay-face (hlwin-lighten 5)
  "Face property used in text overlays, or a function to generate this.

If the value of this setting is a function, it will be called for
each window that should receive an overlay, with that window
selected and with that window's buffer set as the current buffer.
The return value of this function invocation will be used as the
`face' property of the overlay for that window.  If the function
returns nil, no overlay will be applied to that window.

Any other value for `hlwin-overlay-face' will be used verbatim as
the `face' property for all hlwin overlays.

Face properties, whether generated by a function or specified
verbatim, should conform to the specification of `face' property
at Info node `(elisp)Overlay Properties'."
  :group 'hlwin
  :type '(choice function sexp))

(defun hlwin-lighten (percent)
  "Return a function for `hlwin-overlay-face' that lightens the window.
The generated function returns a face property that applies a
background color PERCENT lighter than the default."
  (lambda ()
    `(:background
      ,(color-lighten-name (face-background 'default nil t) percent))))

(defun hlwin-darken (percent)
  "Return a function for `hlwin-overlay-face' that darkens the window.
The generated function returns a face property that applies a
background color PERCENT darker than the default."
  (lambda ()
    `(:background
      ,(color-darken-name (face-background 'default nil t) percent))))

(defun hlwin--active-highlight ()
  "Return the color or function for highlighting the active window."
  (when hlwin-overlay-active-windows
    hlwin-overlay-face))

(defun hlwin--inactive-highlight ()
  "Return the color or function for highlighting inactive windows."
  (unless hlwin-overlay-active-windows
    hlwin-overlay-face))

(defun hlwin--get-face (window)
  "Return the face property for WINDOW's overlay, or nil for no overlay."
  (when (and hlwin-mode
             (window-live-p window)
             (frame-visible-p (window-frame window)))
    (let ((color-or-function
           (if (hlwin-window-active-p window)
               (hlwin--active-highlight)
             (hlwin--inactive-highlight))))
      (cond ((stringp color-or-function)
             `(:background ,color-or-function))
            ((functionp color-or-function)
             (with-selected-window window
               (with-current-buffer (window-buffer)
                 (funcall color-or-function))))
            (t nil)))))

(defvar hlwin--overlays-table (make-hash-table)
  "Hash table mapping windows to text overlays.")

(defun hlwin--update-window (window)
  "Create, modify, or delete the overlay for WINDOW as appropriate."
  (let ((buffer (window-buffer window))
        (face (hlwin--get-face window))
        (overlay (gethash window hlwin--overlays-table)))
    (if face
        (with-current-buffer buffer
          (if overlay
              (move-overlay overlay (point-min) (point-max) buffer)
            (setq overlay (make-overlay (point-min) (point-max) buffer nil t))
            (overlay-put overlay 'window window)
            (puthash window overlay hlwin--overlays-table))
          (overlay-put overlay 'face face)
          (let* ((display '(space . (:width 200 :height 200)))
                 (after-string (propertize " " 'face face 'display display)))
            (overlay-put overlay 'after-string after-string)))
      (when overlay
        (delete-overlay overlay)
        (remhash window hlwin--overlays-table))))
  nil)

(defun hlwin--evict-cursor (_window oldpos status)
  "Hook function to move the cursor out of the after-string.
When STATUS is `entered', move point back to OLDPOS.
Use this function with the `cursor-sensor-functions' text property."
  (message "SENSE!")
  (when (eq status 'entered)
    (message "EVICT!")
    (goto-char oldpos)))

(defun hlwin--remove-overlays (&optional remove-all)
  "Remove overlays whose window is no longer live.
If REMOVE-ALL is non-nil, instead remove all overlays."
  (let (items)
    (maphash (lambda (window overlay)
               (when (or (not (window-live-p window))
                         remove-all)
                 (push (cons window overlay) items)))
             hlwin--overlays-table)
    (dolist (item items)
      (remhash (car item) hlwin--overlays-table)
      (delete-overlay (cdr item)))))

(defun hlwin--update-overlays ()
  "Update text overlays to highlight the active window."
  (walk-windows 'hlwin--update-window 'no-minibuf t)
  (hlwin--remove-overlays))

(add-hook 'hlwin-active-window-update-hook 'hlwin--update-overlays)

(defun hlwin-reset ()
  "Reset the hlwin overlays for all windows."
  (interactive)
  (hlwin--remove-overlays t)
  (hlwin--update-overlays))

(defun hlwin-with-mode-line-face (elt &rest attrs)
  "Return a mode line construct that renders ELT in the mode line face.
ELT must be a mode line construct.  It will be rendered using the
face `mode-line' in the active window, and `mode-line-inactive'
in all others.  ATTRS is a list of additional face attributes to
be applied to ELT in both active and inactive windows."
  `(:eval
    (let ((face (if (hlwin-window-active-p) 'mode-line 'mode-line-inactive)))
      (list :propertize ',elt 'face (list ,@attrs :inherit face)))))

(provide 'hlwin)

;;; hlwin.el ends here
