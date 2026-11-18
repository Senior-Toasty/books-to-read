//! BookHunter shared Rust core.
//!
//! Stage 1 establishes a stable, platform-independent crate. Search providers,
//! persistence, and the Flutter bridge will be added in later milestones.

/// App version displayed in diagnostics and test output.
pub const APP_VERSION: &str = "0.1.0";

/// A normalized search request shared by UI and provider adapters.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchRequest {
    pub query: String,
    pub include_ebooks: bool,
    pub include_audiobooks: bool,
}

impl SearchRequest {
    /// Construct a search request, trimming accidental whitespace.
    pub fn new(query: impl Into<String>) -> Self {
        Self {
            query: query.into().trim().to_owned(),
            include_ebooks: true,
            include_audiobooks: true,
        }
    }

    /// Reject an empty query before a provider request is attempted.
    pub fn is_valid(&self) -> bool {
        !self.query.is_empty()
            && (self.include_ebooks || self.include_audiobooks)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_trims_whitespace() {
        assert_eq!(SearchRequest::new("  Dune  ").query, "Dune");
    }

    #[test]
    fn empty_query_is_invalid() {
        assert!(!SearchRequest::new("  ").is_valid());
    }

    #[test]
    fn defaults_to_both_formats() {
        let request = SearchRequest::new("The Hobbit");
        assert!(request.include_ebooks);
        assert!(request.include_audiobooks);
        assert!(request.is_valid());
    }
}
