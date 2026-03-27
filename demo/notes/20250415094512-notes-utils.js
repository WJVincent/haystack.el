// title: Notes Utilities
// date: 2025-04-15
// %%% haystack-end-frontmatter %%%

/**
 * Utility functions for working with a plain-text notes (zettel) corpus.
 *
 * These helpers cover common operations: generating timestamped filenames,
 * writing frontmatter, extracting titles, and computing basic corpus statistics.
 * The patterns here mirror what Haystack implements in Emacs Lisp for note
 * creation and management.
 */

import { readFile, writeFile, readdir, stat } from "node:fs/promises"; import {
join, extname, basename } from "node:path";

const SENTINEL = "%%% haystack-end-frontmatter %%%";

/**
 * Generate a zettelkasten-style timestamped filename.
 * Format: YYYYMMDDHHMMSS-slugified-title.ext
 *
 * @param {string} title - The note title
 * @param {string} ext - File extension without dot, defaults to "org"
 * @returns {string} - Generated filename
 */
export function generateFilename(title, ext = "org") {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  const timestamp =
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
    `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `${timestamp}-${slug}.${ext}`;
}

/**
 * Generate org-mode frontmatter for a new note.
 *
 * @param {string} title
 * @param {string} date - ISO date string, defaults to today
 * @returns {string} - Frontmatter block including the sentinel line
 */
export function orgFrontmatter(title, date = new Date().toISOString().slice(0, 10)) {
  return `#+TITLE: ${title}\n#+DATE: ${date}\n# ${SENTINEL}\n\n`;
}

/**
 * Generate YAML frontmatter for a Markdown note.
 *
 * @param {string} title
 * @param {string} date
 * @returns {string}
 */
export function markdownFrontmatter(title, date = new Date().toISOString().slice(0, 10)) {
  return `---\ntitle: ${title}\ndate: ${date}\n---\n<!-- ${SENTINEL} -->\n\n`;
}

/**
 * Create a new note file with appropriate frontmatter.
 *
 * @param {string} notesDir - Directory to write the note into
 * @param {string} title - Note title
 * @param {"org"|"md"} format - Note format
 * @returns {Promise<string>} - Resolves to the created file path
 */
export async function createNote(notesDir, title, format = "org") {
  const filename = generateFilename(title, format);
  const filePath = join(notesDir, filename);
  const frontmatter =
    format === "org" ? orgFrontmatter(title) : markdownFrontmatter(title);
  await writeFile(filePath, frontmatter, "utf8");
  return filePath;
}

/**
 * Count total notes and words across a notes directory.
 * Useful for corpus statistics and health monitoring.
 *
 * @param {string} notesDir
 * @param {string[]} extensions
 * @returns {Promise<{noteCount: number, wordCount: number, byExtension: object}>}
 */
export async function corpusStats(notesDir, extensions = ["org", "md"]) {
  const entries = await readdir(notesDir);
  const extSet = new Set(extensions.map((e) => `.${e}`));
  const stats = { noteCount: 0, wordCount: 0, byExtension: {} };

  for (const entry of entries) {
    const ext = extname(entry);
    if (!extSet.has(ext)) continue;
    stats.noteCount++;
    stats.byExtension[ext] = (stats.byExtension[ext] ?? 0) + 1;

    try {
      const content = await readFile(join(notesDir, entry), "utf8");
      // Count words in body only (after sentinel)
      const sentinelIdx = content.indexOf(SENTINEL);
      const body = sentinelIdx >= 0 ? content.slice(sentinelIdx) : content;
      stats.wordCount += body.split(/\s+/).filter(Boolean).length;
    } catch {
      // Skip unreadable files silently
    }
  }

  return stats;
}

/**
 * Extract all titles from a notes directory for use in a quick-switcher or MOC.
 *
 * @param {string} notesDir
 * @param {string[]} extensions
 * @returns {Promise<Array<{filename: string, title: string}>>}
 */
export async function listNoteTitles(notesDir, extensions = ["org", "md"]) {
  const entries = await readdir(notesDir);
  const extSet = new Set(extensions.map((e) => `.${e}`));
  const results = [];

  for (const entry of entries) {
    if (!extSet.has(extname(entry))) continue;
    try {
      const content = await readFile(join(notesDir, entry), "utf8");
      const titleMatch = content.match(/^(?:#\+)?title:\s*(.+)/im);
      results.push({
        filename: entry,
        title: titleMatch ? titleMatch[1].trim() : basename(entry, extname(entry)),
      });
    } catch {
      results.push({ filename: entry, title: basename(entry, extname(entry)) });
    }
  }

  return results.sort((a, b) => a.title.localeCompare(b.title));
}
