// title: Search API — Ripgrep-backed Note Search
// date: 2025-04-14
// %%% pkm-end-frontmatter %%%

/**
 * A Node.js module providing a search API backed by ripgrep (rg).
 *
 * This demonstrates how the same search model Haystack uses in Emacs Lisp
 * can be implemented in JavaScript for a web interface, CLI tool, or
 * integration with other note-taking environments.
 *
 * Requires ripgrep to be installed and available on PATH.
 */

import { spawn } from "node:child_process"; import { readFile } from
"node:fs/promises"; import { join, basename } from "node:path";

const FRONTMATTER_SENTINEL = "%%% pkm-end-frontmatter %%%";

/**
 * Run ripgrep (rg) against a notes directory and return matching file paths.
 *
 * @param {string} query - The search query, may be a regex alternation for expansion groups
 * @param {string} notesDir - Absolute path to the notes directory
 * @param {string[]} extensions - File extensions to include (e.g. ["org", "md"])
 * @returns {Promise<string[]>} - Resolves to an array of matching file paths
 */
export function runRipgrep(query, notesDir, extensions = ["org", "md"]) {
  return new Promise((resolve, reject) => {
    const globArgs = extensions.flatMap((ext) => ["--glob", `*.${ext}`]);
    const args = [
      "--files-with-matches",
      "--ignore-case",
      "--no-heading",
      query,
      notesDir,
      ...globArgs,
    ];

    const proc = spawn("rg", args);
    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (chunk) => (stdout += chunk));
    proc.stderr.on("data", (chunk) => (stderr += chunk));

    proc.on("close", (code) => {
      // rg exits with code 1 when no matches found; that is not an error
      if (code !== 0 && code !== 1) {
        reject(new Error(`rg exited with code ${code}: ${stderr}`));
      } else {
        resolve(stdout.trim().split("\n").filter(Boolean));
      }
    });
  });
}

/**
 * Expand a query using configured synonym groups.
 * Mirrors the expansion groups mechanism in Haystack.
 *
 * @param {string} query - The raw query string
 * @param {string[][]} expansionGroups - Array of synonym arrays
 * @returns {string} - Regex alternation string for rg
 */
export function expandQuery(query, expansionGroups) {
  const lower = query.toLowerCase();
  for (const group of expansionGroups) {
    if (group.some((term) => term.toLowerCase() === lower)) {
      // Return regex alternation of all synonyms in the group
      const escaped = group.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
      return `(${escaped.join("|")})`;
    }
  }
  return query; // No expansion found, return unchanged
}

/**
 * Parse frontmatter from a note file, stopping at the sentinel.
 *
 * @param {string} filePath - Absolute path to the note file
 * @returns {Promise<{title: string, date: string, path: string}>}
 */
export async function parseFrontmatter(filePath) {
  const content = await readFile(filePath, "utf8");
  const lines = content.split("\n");
  const meta = { path: filePath, filename: basename(filePath), title: "", date: "" };

  for (const line of lines) {
    if (line.includes(FRONTMATTER_SENTINEL)) break;
    const m = line.match(/^(?:#\+)?(\w+):\s*(.+)/i);
    if (m) meta[m[1].toLowerCase()] = m[2].trim();
  }

  if (!meta.title) meta.title = meta.filename;
  return meta;
}

/**
 * Full search pipeline: expand query -> rg search -> parse metadata.
 *
 * @param {string} query
 * @param {string} notesDir
 * @param {string[][]} expansionGroups
 * @returns {Promise<Array<{title: string, date: string, path: string}>>}
 */
export async function search(query, notesDir, expansionGroups = []) {
  const expandedQuery = expandQuery(query, expansionGroups);
  const paths = await runRipgrep(expandedQuery, notesDir);
  const metaList = await Promise.all(paths.map(parseFrontmatter));
  return metaList;
}

// Example usage:
// const results = await search("zettelkasten", "/home/user/notes", [
//   ["pkm", "zettelkasten", "knowledge-management", "second-brain"],
//   ["search", "ripgrep", "rg"],
// ]);
// results.forEach(r => console.log(r.title));
