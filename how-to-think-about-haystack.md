# How to Think About Haystack in 5 Minutes

## The Problem

You have hundreds of notes. You know the one you want exists. You can
half-remember what it said — something about ECS patterns, maybe Bevy,
definitely Rust. You don't remember what you titled it, what folder
it's in, or what tags you gave it. You might not have given it tags.

Most PKM tools ask you to solve this problem *before* it happens:
build a link graph, maintain a tagging taxonomy, file things in the
right folder. The cost is paid at capture time, and if you don't pay
it, retrieval fails.

Haystack asks you to solve it *when* it happens: search for what you
remember, narrow from there.

## The Mental Model

Think of your notes directory as a physical filing cabinet with no
folders — just a stack of papers. You need to find something. Your
strategy:

1. **Pull everything that mentions "Rust."** You get a pile of 40
   pages.
2. **From that pile, pull everything that also mentions "Bevy."** Now
   you're down to 8.
3. **From those 8, pull everything that also mentions "ECS."** Three
   pages. One of them is the note you wanted.

That's the entire workflow. Haystack does this with Ripgrep on your
filesystem, and each step — each pile — is a real Emacs buffer you can
read, search inside, branch from, or return to later.

The key insight: **every intermediate pile is preserved.** Step 2
didn't destroy your Rust pile. You can go back to it and pull a
different subset — everything mentioning "wasm" instead of "Bevy."
Both branches coexist. This is the progressive filter tree.

```
Search: "rust"              → 40 notes
├── Filter: "bevy"          →  8 notes
│   └── Filter: "ecs"       →  3 notes
└── Filter: "wasm"          → 12 notes
```

## What a Session Actually Looks Like

1. You call `haystack-search`. A prompt asks for a term. You type
   `rust`.
2. A buffer appears with every file in your notes directory containing
   "rust," formatted as clickable grep results. The header says
   something like `42 files, 187 matches`.
3. You realize 42 files is too many. You call `haystack-filter` and
   type `bevy`. A *new* buffer appears showing only the files from
   step 2 that *also* contain "bevy." The original buffer is still
   there, untouched.
4. You see the note you want in the results. You jump to it with
   `compile-goto-error` (the same key you'd use in any grep buffer).
5. Later, you go back to the "rust" buffer and filter for `wasm`
   instead. A third buffer appears. All three coexist.

That's it. There is no special mode to learn, no custom keybindings to
memorize for basic use. The results are standard grep-mode buffers —
if you know how to use `*grep*`, you know how to use Haystack.

## The Three Things Haystack Adds Beyond Grep

Raw `rg` in a shell could do step 1 above. Haystack earns its
existence with three additions:

**Progressive state.** Each filter remembers its parent. You can
narrow in any direction, backtrack, branch, and explore — all without
re-running searches. The buffer tree *is* your exploration history.

**Synonym expansion.** You can tell Haystack that "programming,"
"coding," and "scripting" are the same concept. Search for any one and
it automatically searches for all three. This bridges the vocabulary
problem: different notes using different words for the same idea all
surface together.

**Frecency memory.** Haystack learns which search paths you use
most. The chain `rust → bevy → ecs` rises to the top of your
completion list if you run it often. You can replay common paths in a
few keystrokes instead of typing them out each time.

## Who This Is For

Haystack is built for the *piler*: someone who captures notes quickly
and finds them by searching, not by following pre-built organizational
structures.

If you think in terms of "I'll recognize it when I find it" rather
than "I need to file this correctly so I can navigate to it later,"
you're the target user.

If you maintain a careful link graph, enjoy tending a tag taxonomy, or
want your PKM to surprise you with connections you didn't know existed
— you want Obsidian, Org-roam, or Logseq. Those are great tools for a
different cognitive style.

## The Cost

Every approach has a cost. Link-based tools cost you maintenance
overhead — links rot, tags sprawl, the graph needs pruning. Haystack's
cost is the **vocabulary burden**: your notes must contain the words
you'll search for later.

A note titled "Bevy ECS Patterns" that only uses Bevy-specific jargon
is invisible to a search for "Entity Component System." You need to
write (or generate) a few extra terms — a vocabulary section, some
loose tags, broader category words — so that search can reach the note
from multiple angles.

Haystack provides diagnostic tools to surface these gaps. But filling
them is your responsibility. This cost is permanent and by design.

## The Payoff

Nothing to maintain. Nothing to break. Nothing between you and your
files.

Your notes are plain text on disk. Haystack doesn't own them, doesn't
require a specific format, and doesn't store anything about them in a
database. If you delete Haystack tomorrow, your notes are exactly
where you left them, readable by every other tool on earth.

The tradeoff is simple: you give up surprise connections and
structural navigation. You get a system with zero infrastructure, zero
maintenance, and a retrieval model that scales with your Emacs fluency
rather than fighting it.
