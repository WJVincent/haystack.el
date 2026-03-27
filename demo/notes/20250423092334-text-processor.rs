// title: Text Processor for Notes Corpus
// date: 2025-04-23
// %%% haystack-end-frontmatter %%%

//! Text processing utilities for a plain-text notes (zettel) corpus.
//!
//! Provides functions for normalizing note text, extracting meaningful
//! vocabulary, computing term frequency, and generating summary statistics
//! useful for understanding corpus composition and search quality.
//!
//! These utilities complement rg-based search by enabling pre-processing
//! and analysis steps that ripgrep does not provide natively.

use std::collections::HashMap; use std::path::Path;

const FRONTMATTER_SENTINEL: &str = "%%% haystack-end-frontmatter %%%";

/// Common English stopwords to exclude from vocabulary analysis.
const STOPWORDS: &[&str] = &[
    "the", "and", "for", "are", "was", "were", "with", "this", "that", "from",
    "have", "not", "but", "they", "you", "your", "its", "all", "any", "can",
    "will", "been", "also", "into", "more", "over", "each", "when", "than",
    "some", "use", "one", "two", "three", "their", "there", "these", "those",
];

/// Term frequency map: word -> count.
pub type TermFrequency = HashMap<String, usize>;

/// Split note content at the frontmatter sentinel.
/// Returns (frontmatter, body) as string slices.
pub fn split_at_sentinel(content: &str) -> (&str, &str) {
    if let Some(pos) = content.find(FRONTMATTER_SENTINEL) {
        let after = &content[pos + FRONTMATTER_SENTINEL.len()..];
        let body_start = after.find('\n').map(|i| i + 1).unwrap_or(0);
        (&content[..pos], &after[body_start..])
    } else {
        ("", content)
    }
}

/// Normalize text for analysis: lowercase, remove punctuation, split on whitespace.
pub fn normalize(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphabetic() && c != '-')
        .filter(|t| t.len() >= 3)
        .map(|t| t.to_lowercase())
        .filter(|t| !STOPWORDS.contains(&t.as_str()))
        .collect()
}

/// Compute term frequency for a note body.
pub fn term_frequency(body: &str) -> TermFrequency {
    let mut tf = TermFrequency::new();
    for term in normalize(body) {
        *tf.entry(term).or_insert(0) += 1;
    }
    tf
}

/// Return the top N most frequent terms from a term frequency map.
pub fn top_terms(tf: &TermFrequency, n: usize) -> Vec<(&str, usize)> {
    let mut pairs: Vec<(&str, usize)> = tf
        .iter()
        .map(|(k, &v)| (k.as_str(), v))
        .collect();
    pairs.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    pairs.truncate(n);
    pairs
}

/// Compute a vocabulary richness score: unique terms / total terms.
/// A higher score indicates a more diverse vocabulary.
pub fn vocabulary_richness(body: &str) -> f64 {
    let tokens = normalize(body);
    if tokens.is_empty() {
        return 0.0;
    }
    let unique: std::collections::HashSet<&str> =
        tokens.iter().map(|s| s.as_str()).collect();
    unique.len() as f64 / tokens.len() as f64
}

/// Sentence count heuristic: count sentence-ending punctuation.
pub fn sentence_count(text: &str) -> usize {
    text.chars().filter(|&c| c == '.' || c == '!' || c == '?').count()
}

/// Extract all capitalized multi-word phrases as potential proper nouns or
/// named concepts — useful for identifying key terms that bypass stopword filtering.
pub fn extract_capitalized_terms(text: &str) -> Vec<String> {
    let mut terms = Vec::new();
    let mut current: Vec<&str> = Vec::new();

    for word in text.split_whitespace() {
        let clean: String = word.chars()
            .filter(|c| c.is_alphanumeric() || *c == '-')
            .collect();
        if clean.chars().next().map_or(false, |c| c.is_uppercase()) {
            current.push(word);
        } else {
            if current.len() >= 2 {
                terms.push(current.join(" "));
            }
            current.clear();
        }
    }
    if current.len() >= 2 {
        terms.push(current.join(" "));
    }
    terms
}

/// Compute a basic readability estimate: average sentence length in words.
pub fn avg_sentence_length(body: &str) -> f64 {
    let sentences = sentence_count(body).max(1);
    let words = body.split_whitespace().count();
    words as f64 / sentences as f64
}

/// Summary statistics for a single note.
#[derive(Debug)]
pub struct NoteStats {
    pub path: String,
    pub word_count: usize,
    pub unique_terms: usize,
    pub vocabulary_richness: f64,
    pub sentence_count: usize,
    pub avg_sentence_length: f64,
    pub top_terms: Vec<String>,
}

impl NoteStats {
    /// Compute statistics from note body text.
    pub fn from_body(path: &Path, body: &str) -> Self {
        let tf = term_frequency(body);
        let unique_terms = tf.len();
        let top = top_terms(&tf, 5);

        NoteStats {
            path: path.to_string_lossy().into_owned(),
            word_count: body.split_whitespace().count(),
            unique_terms,
            vocabulary_richness: vocabulary_richness(body),
            sentence_count: sentence_count(body),
            avg_sentence_length: avg_sentence_length(body),
            top_terms: top.into_iter().map(|(t, _)| t.to_string()).collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_at_sentinel() {
        let content = "#+TITLE: Test\n# %%% haystack-end-frontmatter %%%\nBody text here.";
        let (front, body) = split_at_sentinel(content);
        assert!(front.contains("#+TITLE"));
        assert!(body.contains("Body text"));
    }

    #[test]
    fn test_term_frequency() {
        let body = "ripgrep rg search rg notes notes notes";
        let tf = term_frequency(body);
        assert_eq!(*tf.get("ripgrep").unwrap_or(&0), 1);
        assert_eq!(*tf.get("notes").unwrap_or(&0), 3);
    }

    #[test]
    fn test_vocabulary_richness() {
        let diverse = "emacs lisp search notes pkm ripgrep zettelkasten";
        let repetitive = "notes notes notes notes notes notes notes";
        assert!(vocabulary_richness(diverse) > vocabulary_richness(repetitive));
    }
}
