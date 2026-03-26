---
title: Haystack Composites Roadmap
date: 2025-04-04
---
<!-- %%% pkm-end-frontmatter %%% -->
Haystack composites are a planned feature that will allow combining multiple
search queries, filters, and expansion groups into named, reusable search
profiles for common retrieval patterns. A composite might define "my emacs pkm
notes" as a saved combination of the query "emacs OR org-mode OR elisp" filtered
to .org files, ranked by frecency, and expanded with the emacs-lisp synonym
group. The motivation for composites is workflow acceleration: a user who
frequently searches within a specific domain should be able to invoke a single
command rather than reconstructing the same multi-part query repeatedly.
Composites would be stored in a configuration variable similar to ~haystack-
expansion-groups~, as a list of named plist records each containing query,
filter, extension, and expansion-override keys. The roadmap also includes
composite views: a buffer that shows the top-N results from multiple composites
simultaneously, providing a dashboard-style overview of activity across
different note domains. Integration with org-agenda is a related roadmap item: a
composite for "active projects" could feed into an org-agenda view that collects
TODO items from notes matching the composite query. Composites compose with
expansion groups: the expansion groups defined globally apply to all composites,
but a composite can also define its own local overrides for domain-specific
vocabulary. The performance constraint on composites is that each composite
search must still complete within Haystack's two-tier benchmark ceiling: 500ms
for 10k notes and 2s for 100k notes. Naming conventions for composites are
intentionally user-defined: there is no enforced taxonomy, reflecting Haystack's
philosophy of providing mechanisms rather than prescribing methodology. User
feedback and real-world corpus testing will determine the final composites API;
the current roadmap reflects the most commonly requested enhancements from early
Haystack adopters.