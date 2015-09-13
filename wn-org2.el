;; wn-org2.el -- Major mode interface to WordNet -*- lexical-binding: t -*-

(require 'cl)

(defconst wn-org2-meta-name "wm-org2")
(defconst wn-org2-meta-version "0.0.1")

(defconst wn-org2-bufname "*WordNet*")
(defconst wn-org2-cmd "wn")
(defconst wn-org2-cmd-options
  '("-over"
    "-antsn" "-antsv" "-antsa" "-antsr"
    "-hypen" "-hypev"
    "-hypon" "-hypov"
    "-entav"
    "-synsn" "-synsv" "-synsa" "-synsr"
    "-smemn"
    "-ssubn"
    "-sprtn"
    "-membn"
    "-subsn"
    "-partn"
    "-meron"
    "-holon"
    "-causv"
    "-perta" "-pertr"
    "-attrn" "-attra"
    "-derin" "-deriv"
    "-domnn" "-domnv" "-domna" "-domnr"
    "-domtn" "-domtv" "-domta" "-domtr"
    "-famln" "-famlv" "-famla" "-famlr"
    "-framv"
    "-coorn" "-coorv"
    "-simsv"
    "-hmern"
    "-hholn"))

(defconst wn-org2-section-headings
  '("Antonyms" "Synonyms" "Hyponyms" "Troponyms"
    "Meronyms" "Holonyms" "Pertainyms"
    "Member" "Substance" "Part"
    "Attributes" "Derived" "Domain" "Familiarity"
    "Coordinate" "Grep" "Similarity"
    "Entailment" "'Cause To'" "Sample" "Overview of"))

(defconst wn-org2-hist-max 20)
(defvar wn-org2-hist-back '())
(defvar wn-org2-hist-forw '())
(defvar wn-org2-hist-cur nil)



(define-derived-mode wn-org2-mode outline-mode "WordNet"
  "Major mode interface to WordNet lexical database.
Turning on WordNet mode runs the normal hook `wn-org2-mode-hook'.

\\{wn-org2-mode-map}"

  (setq buffer-read-only t)
  (setq truncate-lines nil))

(define-key wn-org2-mode-map (kbd "q") 'delete-window)
(define-key wn-org2-mode-map (kbd "RET") 'wn-org2-lookup-current-word)
(define-key wn-org2-mode-map (kbd "l") 'wn-org2-history-backward)
(define-key wn-org2-mode-map (kbd "r") 'wn-org2-history-forward)
(define-key wn-org2-mode-map (kbd "h") 'wn-org2-lookup-history)
(define-key wn-org2-mode-map (kbd "/") 'wn-org2-search)

;; this mode is suitable only for specially formatted data
(put 'wn-org2-mode 'mode-class 'special)

(defun wn-org2-suggest (word)
  "ido suggestions"
  (if (string-match "^\s*$" word) (error "a non-empty string arg required"))
  (setq word (wn-org2-chomp word))

  (let ((result (wn-org2-exec word "-grepn" "-grepv" "-grepa" "-grepr"))
	suggestions)
    (if (equal "" result) (user-error "Refine your query"))

    (setq result (split-string result "\n"))
    (setq suggestions (wn-org2-filter (lambda (idx)
				       (and
					(not (string-prefix-p "Grep of " idx))
					(not (equal idx ""))))
				     result))
    (ido-completing-read "WordNet: " suggestions)
    ))

(defun wn-org2-exec (word &rest args)
  "Like `system(3)' but only for wn(1)."
  (with-output-to-string
    (with-current-buffer
	standard-output
      (apply 'call-process wn-org2-cmd nil t nil word args)
      )))

(defun wn-org2-search (word)
  "Search WordNet for WORD if provided otherwise prompt for it.
The word at the point is suggested which can be replaced."
  (interactive (list (read-string "WordNet: " (current-word))))
  (wn-org2-lookup word)
  )

(defun wn-org2-fix-name (str)
  (let ((max 10))
    (if (> (length str) max)
	(concat (substring str 0 max) "...")
      str)
    ))

;; If wm prints something to stdout it means the word is
;; found. Otherwise we run wn again but with its -grepX options. If
;; that returns nothing, bail out. If we get a list of words, show
;; them to the user, then rerun `wn-org2-lookup' with the selected
;; word.
(defun wn-org2-lookup (word &optional dont-modify-history)
  (if (or (null word) (string-match "^\s*$" word)) (user-error "Invalid query"))

  (setq word (wn-org2-chomp word))
  (let ((progress-reporter
	 (make-progress-reporter
	  (format "WordNet lookup for `%s'... " (wn-org2-fix-name word)) 0 2))
	result buf)

    (setq result (apply 'wn-org2-exec word wn-org2-cmd-options))
    (progress-reporter-update progress-reporter 1)

    (if (equal "" result)
	;; recursion!
	(wn-org2-lookup (wn-org2-suggest word))
      ;; else
      (if (not dont-modify-history)
	  (setq wn-org2-hist-back (wn-org2-hist-add word wn-org2-hist-back)))
      (setq wn-org2-hist-cur word)

      (setq buf (get-buffer-create wn-org2-bufname))
      (with-current-buffer buf
	(let ((inhibit-read-only t))
	  (erase-buffer)
	  (insert result))
	(wn-org2-format-buffer)
	(show-all)
	(unless (eq major-mode 'wn-org2-mode) (wn-org2-mode))
	(wm-org2-headerline))

      (progress-reporter-update progress-reporter 2)
      (progress-reporter-done progress-reporter)
      (wn-org2-switch-to-buffer buf))
    ))

(defun wn-org2-lookup-current-word ()
  (interactive)
  (wn-org2-lookup (current-word)))

(defun wn-org2-switch-to-buffer (buf)
  (unless (eq (current-buffer) buf)
    (unless (cdr (window-list))
      (split-window-vertically))
    (other-window 1)
    (switch-to-buffer buf)))

(defun wm-org2-headerline ()
  (let (get-hist-item get-len)
    (setq get-hist-item (lambda (list)
			  (or (if (equal (car list) wn-org2-hist-cur)
				  (nth 1 list) (car list)) "∅")))
    (setq get-len (lambda (list)
		    (if (equal (car list) wn-org2-hist-cur)
			(1- (length list))
		      (length list))))

    (setq header-line-format
	  (format "C: %s, ← %s (%d), → %s (%d)"
		  (wn-org2-fix-name wn-org2-hist-cur)
		  (wn-org2-fix-name (funcall get-hist-item wn-org2-hist-back))
		  (funcall get-len wn-org2-hist-back)
		  (wn-org2-fix-name (funcall get-hist-item wn-org2-hist-forw))
		  (funcall get-len wn-org2-hist-forw)
		  )
	  )))

(defun wn-org2-hist-slice (list)
  (remove nil (cl-subseq list 0 wn-org2-hist-max)))

(defun wn-org2-hist-add (val list)
  "Return a new list."
  (wn-org2-hist-slice (if (member val list)
			  (cons val (remove val list))
			(cons val list)
			)))

(defun wn-org2-history-clean ()
  (interactive)
  (setq wn-org2-hist-back '())
  (setq wn-org2-hist-forw '())
  (setq wn-org2-hist-cur nil)
  )

(defun wn-org2-lookup-history ()
  (interactive)
  (let ((items (append wn-org2-hist-back wn-org2-hist-forw)))
    (unless items (user-error "History is empty"))
    (wn-org2-lookup (ido-completing-read "wm-org2 history: " items) t)
    ))

(defun wn-org2-history-backward ()
  (interactive)
  (unless wn-org2-hist-back (user-error "No items in the back history"))

  (let ((word (pop wn-org2-hist-back)))
    (setq wn-org2-hist-forw (wn-org2-hist-add word wn-org2-hist-forw))
    (if (equal word wn-org2-hist-cur) (setq word (car wn-org2-hist-back)))
    (if (not word) (user-error "No more backward history"))
    (wn-org2-lookup word t)))

;; well...
(defun wn-org2-history-forward ()
  (interactive)
  (unless wn-org2-hist-forw (user-error "No items in the forward history"))

  (let ((word (pop wn-org2-hist-forw)))
    (setq wn-org2-hist-back (wn-org2-hist-add word wn-org2-hist-back))
    (if (equal word wn-org2-hist-cur) (setq word (car wn-org2-hist-forw)))
    (if (not word) (user-error "No more forward history"))
    (wn-org2-lookup word t)))

;; FIXME: it should operate on a string, not on a buffer content
(defun wn-org2-format-buffer ()
  (let ((inhibit-read-only t))
    ;; delete the 1st empty line
    (goto-char (point-min))
    (delete-char 1)

    ;; make headlines
    (delete-matching-lines "^ +$" (point-min) (point-max))
    (while (re-search-forward
	    (concat "^" (regexp-opt wn-org2-section-headings t)) nil t)
      (replace-match "* \\1"))

    ;; remove empty entries
    (goto-char (point-min))
    (while (re-search-forward "^\\* .+\n\n\\*" nil t)
      (replace-match "*" t t)
      ;; back over the '*' to remove next matching lines
      (backward-char))

    (goto-char (point-min))
    ))



;; emacswiki.org
(defun wn-org2-filter (condp lst)
  (delq nil
	(mapcar (lambda (x) (and (funcall condp x) x)) lst)))

;; emacswiki.org
(defun wn-org2-chomp (str)
  "Chomp leading and tailing whitespace from STR."
  (replace-regexp-in-string (rx (or (: bos (* (any " \t\n")))
				    (: (* (any " \t\n")) eos)))
			    ""
			    str))

(provide 'wn-org2)
