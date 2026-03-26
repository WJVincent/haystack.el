---
title: Common Lisp vs Emacs Lisp
date: 2025-02-17
---
<!-- %%% pkm-end-frontmatter %%% -->
Common Lisp (cl) and Emacs Lisp (emacs-lisp, elisp) share a common ancestor in
Maclisp but have diverged significantly in scope, design philosophy, and typical
use cases. Common Lisp is a large, standardized language (ANSI X3.226) with a
rich object system (CLOS), multiple return values, conditions and restarts, and
a sophisticated type system; emacs-lisp is a smaller dialect tightly coupled to
the Emacs editor. The most practical difference for everyday coding: emacs-lisp
defaults to dynamic binding, while Common Lisp always uses lexical binding —
closures in elisp require `;;-*- lexical-binding: t -*-` at the file header.
Common Lisp's package system provides true namespacing with `defpackage` and
`in-package`, whereas emacs-lisp has no namespacing beyond a convention of
prefixing all symbols with the package name (e.g., `haystack-`). The `cl-lib`
package in emacs-lisp imports a substantial subset of Common Lisp's standard
library functions and macros, bridging the gap for list processing, type
predicates, and generics. Common Lisp has a condition system (not just
exceptions) with restarts that allow recovery at the call site — this is more
powerful than emacs-lisp's `condition-case` / `unwind-protect` error handling.
Both languages use the same s-expression syntax and share core forms like `let`,
`lambda`, `defun`, `defmacro`, `car`, `cdr`, `mapcar`, and `funcall`.
Performance differs substantially: Common Lisp implementations like SBCL compile
to efficient native code, while emacs-lisp is primarily interpreted (though
byte-compilation and native compilation via libgccjit are available). Clojure
(clojure) and Scheme offer yet different trade-offs — clojure for the JVM
ecosystem and immutable data, scheme for academic minimalism and guaranteed TCO.
For Emacs users, the practical choice is moot — emacs-lisp is the only option
for extending Emacs — but understanding Common Lisp enriches elisp practice by
showing what the full Lisp design space looks like.