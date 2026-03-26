// title: Search Index in Rust
// date: 2025-04-22
// %%% pkm-end-frontmatter %%%

//! A lightweight in-memory search index for a plain-text notes corpus.
//!
//! This demonstrates how to build a simple inverted index over a zettelkasten
//! directory without relying on ripgrep (rg) as a subprocess. For production
//! use, rg is faster and more featureful; this index is useful for environments
//! where spawning processes is not available (WebAssembly, embedded, tests).
//!
//! The design mirrors Haystack's rg-backed search but replaces the rg subprocess
//! with a Rust-native index that supports synonym expansion via term groups.

use std::collections::{HashMap, HashSet}; use std::fs; use std::path::{Path,
PathBuf};

const FRONTMATTER_SENTINEL: &str = "%%% pkm-end-frontmatter %%%";

/// Metadata parsed from a note's frontmatter.
#[derive(Debug, Clone)]
pub struct NoteMeta {
    pub path: PathBuf,
    pub filename: String,
    pub title: String,
    pub date: String,
}

/// An inverted index mapping terms to the set of note paths containing them.
pub struct SearchIndex {
    /// term -> set of note paths
    index: HashMap<String, HashSet<PathBuf>>,
    /// All note metadata, keyed by path
    notes: HashMap<PathBuf, NoteMeta>,
    /// Expansion groups: each is a set of synonym terms
    expansion_groups: Vec<Vec<String>>,
}

impl SearchIndex {
    pub fn new(expansion_groups: Vec<Vec<String>>) -> Self {
        SearchIndex {
            index: HashMap::new(),
            notes: HashMap::new(),
            expansion_groups,
        }
    }

    /// Index a single note file.
    pub fn index_file(&mut self, path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let content = fs::read_to_string(path)?;
        let (meta, body) = parse_note(path, &content);
        let path_buf = path.to_path_buf();

        // Index all words in the body text
        for word in tokenize(&body) {
            self.index
                .entry(word)
                .or_default()
                .insert(path_buf.clone());
        }

        self.notes.insert(path_buf, meta);
        Ok(())
    }

    /// Index all notes in a directory with the given extensions.
    pub fn index_directory(
        &mut self,
        dir: &Path,
        extensions: &[&str],
    ) -> Result<(), Box<dyn std::error::Error>> {
        let ext_set: HashSet<&str> = extensions.iter().copied().collect();
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if ext_set.contains(ext) {
                    if let Err(e) = self.index_file(&path) {
                        eprintln!("Warning: could not index {:?}: {}", path, e);
                    }
                }
            }
        }
        Ok(())
    }

    /// Expand a query term using configured synonym groups.
    /// Returns a list of all terms that should be searched.
    pub fn expand_term(&self, term: &str) -> Vec<String> {
        let lower = term.to_lowercase();
        for group in &self.expansion_groups {
            if group.iter().any(|t| t.to_lowercase() == lower) {
                return group.clone();
            }
        }
        vec![term.to_string()]
    }

    /// Search the index for notes containing the query term (with expansion).
    /// Returns note metadata sorted by title.
    pub fn search(&self, query: &str) -> Vec<&NoteMeta> {
        let terms = self.expand_term(query);
        let mut matching_paths: HashSet<&PathBuf> = HashSet::new();

        for term in &terms {
            if let Some(paths) = self.index.get(&term.to_lowercase()) {
                for path in paths {
                    matching_paths.insert(path);
                }
            }
        }

        let mut results: Vec<&NoteMeta> = matching_paths
            .into_iter()
            .filter_map(|p| self.notes.get(p))
            .collect();

        results.sort_by(|a, b| a.title.cmp(&b.title));
        results
    }
}

/// Parse frontmatter and body from note content.
fn parse_note(path: &Path, content: &str) -> (NoteMeta, String) {
    let mut title = String::new();
    let mut date = String::new();
    let mut body_start = content.len();

    for (i, line) in content.lines().enumerate() {
        if line.contains(FRONTMATTER_SENTINEL) {
            // Body starts after this line
            body_start = content
                .lines()
                .take(i + 1)
                .map(|l| l.len() + 1)
                .sum();
            break;
        }
        // Parse #+TITLE: or title:
        if let Some(val) = parse_frontmatter_field(line, "title") {
            title = val;
        }
        if let Some(val) = parse_frontmatter_field(line, "date") {
            date = val;
        }
    }

    let filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_string();

    if title.is_empty() {
        title = filename.clone();
    }

    let body = content[body_start..].to_string();
    let meta = NoteMeta {
        path: path.to_path_buf(),
        filename,
        title,
        date,
    };
    (meta, body)
}

fn parse_frontmatter_field(line: &str, field: &str) -> Option<String> {
    let prefixes = [
        format!("#+{}:", field.to_uppercase()),
        format!("{}:", field.to_lowercase()),
    ];
    for prefix in &prefixes {
        if let Some(rest) = line.trim().to_lowercase().strip_prefix(&prefix.to_lowercase()) {
            return Some(rest.trim().to_string());
        }
    }
    None
}

/// Tokenize text into lowercase words (3+ characters, alphabetic only).
fn tokenize(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphabetic())
        .filter(|w| w.len() >= 3)
        .map(|w| w.to_lowercase())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_expand_term() {
        let index = SearchIndex::new(vec![
            vec!["pkm".into(), "zettelkasten".into(), "second-brain".into()],
            vec!["search".into(), "ripgrep".into(), "rg".into()],
        ]);
        let expanded = index.expand_term("pkm");
        assert!(expanded.contains(&"zettelkasten".to_string()));
        assert!(expanded.contains(&"second-brain".to_string()));
    }

    #[test]
    fn test_tokenize() {
        let tokens = tokenize("Emacs Lisp is an elisp dialect");
        assert!(tokens.contains(&"emacs".to_string()));
        assert!(tokens.contains(&"elisp".to_string()));
    }
}
