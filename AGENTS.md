# AGENTS.md

## Purpose

This repository is set up for multi-agent review first, implementation
second.

The default flow is:

1. One or more agents inspect the current code and produce independent
   reviews.
2. Each review is broken into focused parts rather than a single
   blended opinion.
3. A synthesis pass merges, deduplicates, and prioritizes those
   findings.
4. Agents then read the other agents' reviews and revise their
   synthesis.
5. The user takes the final synthesis documents to Claude to produce
   the next implementation plan.

Do not assume the goal of a turn is to write code. In this repository,
the likely goal is to review, challenge assumptions, surface
regressions, and improve the quality of the next plan.

## Repository Shape

- `haystack.el`: main package implementation
- `test/haystack-test.el`: unit tests
- `test/haystack-io-test.el`: real-ripgrep integration tests against
  the demo corpus
- `test/haystack-bench.el`: performance checks
- `README.md`: user-facing documentation
- `CHANGELOG.md`: release-facing change log
- `docs/ROADMAP.org`: phased delivery plan and definition-of-done
  checklist
- `docs/how-to-think-about-haystack.md`: conceptual documentation
- `demo/`: demo corpus and walkthrough materials
- `review_docs/`: review outputs, synthesis notes, and planning
  artifacts

## Non-Negotiable Project Invariants

These are repository rules, not agent preferences:

- Preserve `grep-mode` compatibility. Results buffers must continue to
  emit `filename:line:content` so `compile-goto-error` works.
- Filters are file-level, not line-level. A filter means "notes
  containing X", not "matching lines only".
- Bare user input is literal by default. Only treat input as regex
  when the `~` prefix or a documented expansion path says so.
- Buffer-local state is canonical. Do not treat buffer names as the
  source of truth.
- Ripgrep execution should continue to follow the existing `xargs -0`
  filelist model where that path is already established.
- Data-file reads should degrade safely. On load failure: warn, fall
  back to an empty/default value, and continue where possible.
- Performance is a feature. Flag O(N) subprocess patterns, unnecessary
  reparsing, and avoidable repeated scans.

## Documentation Hygiene

If a task results in implementation changes, check all of the
following before considering the work complete:

- `docs/ROADMAP.org`
- docstrings in `haystack.el`
- `CLAUDE.md`
- `CHANGELOG.md`
- `README.md`
- `docs/how-to-think-about-haystack.md` when the feature changes the
  mental model, not just the commands

For review-only turns, use this list as a coverage guide. Missing doc
updates are review findings.

## Testing Commands

Run the unit suite after source edits:

```sh
emacs --batch -l haystack.el -l test/haystack-test.el --eval '(ert-run-tests-batch-and-exit t)'
```

Run the IO suite when touching search pipelines, frecency, compose,
discoverability, or stop words:

```sh
emacs --batch -l haystack.el -l test/haystack-io-test.el --eval '(ert-run-tests-batch-and-exit t)'
```

Use the benchmark suite when evaluating performance-sensitive changes:

```sh
emacs --batch -l haystack.el -l test/haystack-bench.el --eval '(ert-run-tests-batch-and-exit t)'
```

## Review Default

Unless the user explicitly asks for implementation, default to a
code-review mindset.

Prioritize:

1. correctness bugs
2. behavior regressions
3. invariant violations
4. performance risks
5. missing tests
6. documentation drift
7. maintainability issues with real downstream cost

Keep findings concrete. Prefer file and line references. Distinguish
observed bugs from design opinions.

If no significant issues are found, state that explicitly and note
residual risk or testing gaps.

## Multi-Agent Review Protocol

When participating in a review cycle, structure work so outputs can be
compared and merged across models.

Recommended review partitions:

1. Correctness and edge cases
2. Emacs idioms and API design
3. Structure, duplication, and maintainability
4. Documentation, UX, and conceptual consistency
5. Tests and performance coverage

An agent does not need to cover every partition deeply, but should
make its lens explicit.

### First-pass review

Produce an independent review without being anchored by the other
agents' conclusions.

For each finding:

- give severity
- cite the file and line
- explain why it matters
- state the likely user-visible or maintenance impact
- propose the smallest credible fix direction

### Synthesis pass

When asked to synthesize multiple reviews:

- deduplicate overlapping findings
- merge similar findings under the strongest framing
- separate confirmed issues from plausible but unverified concerns
- call out disagreements between agents
- rank by release risk, not by verbosity

### Revision pass

When revising after reading other agents' reviews:

- update confidence up or down
- keep independent judgment
- explicitly note which earlier findings you now reject, merge, or
  strengthen
- avoid cargo-cult consensus

The goal is not agreement for its own sake. The goal is a sharper
final synthesis document for planning.

## Output Expectations For Review Docs

Review documents under `review_docs/` should be useful as planning
inputs.

Preferred qualities:

- stable identifiers for findings
- severity ordering
- concise reproduction or reasoning
- explicit fix direction
- minimal fluff

Good review docs are closer to release triage than to general
commentary.
This repository also values polish for its own sake. Minor issues,
small UX rough edges, naming cleanup, docstring drift, and other nits
are valid findings when they are concrete and useful.

## Review Workflow Files

The canonical review workflow lives under `review_docs/`.

Use the standardized five-phase structure:

1. Phase 1: philosophy, identity, and documentation
2. Phase 2: code, bugs, tests, and performance
3. Phase 3: self-synthesis within one agent
4. Phase 4: cross-agent revision after reading other agents' Phase 3 outputs
5. Phase 5: final synthesis by one designated agent

Use the templates in `review_docs/` rather than inventing new shapes
for each cycle unless the user explicitly asks for a different format.

## Review Filename Convention

Review output filenames should make date, agent, and phase obvious.

Use these patterns:

- `YYYY-MM-DD-agent-pass-1-philosophy.md`
- `YYYY-MM-DD-agent-pass-2-code-review.md`
- `YYYY-MM-DD-agent-pass-3-self-synthesis.md`
- `YYYY-MM-DD-agent-pass-4-cross-agent-revision.md`
- `YYYY-MM-DD-agent-synthesis.md`

Examples of `agent`: `claude`, `codex`, `gemini`.

If a cycle needs additional topical labels, append them after the pass
label rather than replacing the standard prefix.

## Implementation Guidance

If the user does ask for code changes:

- make the smallest coherent change that resolves the issue
- preserve existing naming and architectural patterns unless there is
  a strong reason not to
- add or update tests for behavior changes
- do not silently weaken documented invariants

## Agent-Specific Files

`AGENTS.md` is the repository-neutral instruction file.

Keep agent-specific files such as `CLAUDE.md` focused on tool-specific
shortcuts, permissions, or workflow glue. Durable project rules should
live here so multiple agents can share the same baseline.
