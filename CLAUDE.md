# Haystack — Claude Notes

This file is Claude-specific glue for working in this repository.

Shared project rules, review defaults, invariants, and test expectations live in `AGENTS.md`. Treat that file as canonical for repository policy.

## Purpose

Use this file for:

- Claude-oriented shortcuts
- lightweight implementation reference
- notes that are useful in Claude sessions but should not become repository-wide policy

Do not duplicate durable project rules here unless there is a Claude-specific reason.

## Repository Context

Haystack is a search-first, filesystem-native knowledge management package for Emacs. Its core workflow is progressive filtering over ripgrep-backed results buffers.

Primary files:

- `haystack.el`
- `test/haystack-test.el`
- `test/haystack-io-test.el`
- `test/haystack-bench.el`
- `README.md`
- `docs/ROADMAP.org`

## Claude Working Style In This Repo

When Claude is asked to implement changes:

- read `AGENTS.md` first
- keep edits small and behavior-focused
- prefer preserving existing conventions over refactoring opportunistically
- run the appropriate tests after changes
- update documentation when implementation changes affect users or planning artifacts

When Claude is asked to review:

- follow the review-first posture from `AGENTS.md`
- keep findings concrete and prioritized
- avoid turning stylistic preferences into major findings unless they have clear maintenance cost

## Useful Command Reference

Unit tests:

```sh
emacs --batch -l haystack.el -l test/haystack-test.el --eval '(ert-run-tests-batch-and-exit t)'
```

IO tests:

```sh
emacs --batch -l haystack.el -l test/haystack-io-test.el --eval '(ert-run-tests-batch-and-exit t)'
```

Benchmarks:

```sh
emacs --batch -l haystack.el -l test/haystack-bench.el --eval '(ert-run-tests-batch-and-exit t)'
```

## Lightweight Implementation Notes

- Public symbols use the `haystack-` prefix.
- Private helpers use the `haystack--` prefix.
- Results-buffer behavior depends heavily on buffer-local state.
- grep-format output is a hard requirement for navigation compatibility.
- Search and filter behavior is synchronous by design unless the repository policy changes.

If any of these notes ever conflict with `AGENTS.md`, follow `AGENTS.md` and update this file.
