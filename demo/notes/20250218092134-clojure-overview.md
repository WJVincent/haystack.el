---
title: Clojure Overview
date: 2025-02-18
---
<!-- %%% pkm-end-frontmatter %%% -->
Clojure is a modern Lisp dialect created by Rich Hickey in 2007 that targets the
JVM, prioritizing immutability, concurrency, and practical interoperability with
the Java ecosystem. Unlike Common Lisp (cl) or emacs-lisp, Clojure makes
immutability the default: all built-in collections (lists, vectors, maps, sets)
are persistent and share structure between versions. The Clojure REPL is central
to development workflow — interactive development by evaluating forms and
observing results is even more emphasized than in other Lisp dialects.
ClojureScript compiles Clojure to JavaScript, and ClojureCLR targets the .NET
runtime, but the JVM version (clojure) remains the primary and most mature
implementation. Clojure's macro system follows the same principles as other Lisp
dialects: `defmacro`, backquote/unquote, and `macroexpand` work identically, but
syntax-quote automatically namespace-qualifies symbols. The `core.async` library
brings Go-style channels and goroutines to Clojure, providing a principled
approach to concurrent programming without shared mutable state. Clojure favors
small, composable functions over object hierarchies — namespaces group related
functions, and protocols provide polymorphism without inheritance. For
knowledge-management tooling, Clojure's powerful data manipulation capabilities
make it attractive for building corpus analysis tools, note indexing pipelines,
and search utilities. The Clojure community has produced excellent tooling:
Leiningen and deps.edn for dependency management, CIDER (an Emacs package) for
interactive development, and the nREPL protocol for editor integration. Learning
Clojure after emacs-lisp reveals how the same core Lisp ideas scale to a
production language with a rich library ecosystem and serious concurrency
support.