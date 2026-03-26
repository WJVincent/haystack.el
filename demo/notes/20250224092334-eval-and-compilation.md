---
title: Eval and Compilation in Lisp
date: 2025-02-24
---
<!-- %%% pkm-end-frontmatter %%% -->
The `eval` function is a defining feature of Lisp: it takes a data structure (an
s-expression) and evaluates it as code, erasing the boundary between program and
data at runtime. In emacs-lisp, `eval` accepts a form and an optional lexical
environment parameter; calling `(eval '(+ 1 2))` returns 3 by executing the list
as a function call. Emacs Lisp has three execution modes: interpreted (source
read and evaluated directly), byte-compiled (source compiled to Emacs bytecode),
and natively compiled (bytecode further compiled to machine code via libgccjit).
Byte compilation with `byte-compile-file` or `emacs-lisp-byte-compile-and-load`
produces `.elc` files that load faster and execute significantly faster than
source interpretation. Native compilation (introduced in Emacs 28 with `--with-
native-compilation`) compiles elisp to native machine code, providing another
substantial speedup for CPU-intensive elisp. Common Lisp (cl) has a
sophisticated compile-time/load-time/runtime distinction: `eval-when` controls
precisely when forms are evaluated during compilation, loading, and execution.
In Clojure (clojure), all code is compiled to JVM bytecode before execution —
there is no pure interpreter; `eval` re-enters the compiler at runtime, which is
powerful but slower than pre-compiled paths. Scheme's `eval` takes an expression
and an environment object, enabling evaluation in different namespaces — a clean
model that emacs-lisp approximates with the optional environment argument. The
`load` and `require` functions in emacs-lisp control when files are evaluated:
`require` loads a library only once (tracking it in `features`), while `load`
always evaluates the file. Understanding the compilation pipeline in emacs-lisp
— source → byte code → native code — is important for performance-sensitive
elisp and for debugging subtle differences in behavior between compilation
levels.