use anyhow::{bail, Context, Result};
use chrono::{DateTime, Utc};
use clap::Parser;
use futures::{stream, StreamExt};
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tokio::time::sleep;

#[derive(Parser, Debug)]
#[command(name = "bookhunter", version, about = "Find legal free-reading and open-access routes for your reading list")]
struct Args {
    /// Search one numbered book instead of the entire reading list.
    #[arg(long)]
    book_id: Option<u16>,
    /// Path to the Markdown file containing the numbered book list.
    #[arg(long, default_value = "README2.md")]
    list: PathBuf,
    /// Directory where JSON, CSV, HTML and Markdown reports are written.
    #[arg(long, default_value = "reports")]
    output: PathBuf,
    /// Comma-separated providers: google-books,open-library,internet-archive,gutenberg,loc,wikisource,openalex.
    #[arg(long, default_value = "open-library,internet-archive,gutenberg,wikisource,openalex,oapen,openaire,crossref,wikidata")]
    sources: String,
    /// Number of provider requests allowed at once.
    #[arg(long, default_value_t = 8)]
    concurrency: usize,
    /// When a previous JSON report exists, only retry books with no recorded matches.
    #[arg(long)]
    retry_empty: bool,
    /// Use the longer retry policy for temporary network errors and rate limits.
    #[arg(long)]
    retry_failed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Book {
    id: u16,
    title: String,
    author: String,
    category: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Hit {
    book_id: u16,
    book_title: String,
    book_author: String,
    source: String,
    found_title: String,
    found_authors: String,
    year: String,
    url: String,
    access: String,
    confidence: f32,
    notes: String,
}

#[derive(Debug, Clone)]
struct HitCandidate {
    title: String,
    authors: String,
    year: String,
    url: String,
    access: String,
    notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SearchError {
    book_id: u16,
    book_title: String,
    source: String,
    message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SearchRun {
    generated_at: DateTime<Utc>,
    list_file: String,
    total_books: usize,
    searched_books: usize,
    #[serde(default)]
    searched_book_ids: Vec<u16>,
    hits: Vec<Hit>,
    errors: Vec<SearchError>,
}

#[derive(Clone)]
struct RequestGates {
    google_books: Arc<Semaphore>,
    open_library: Arc<Semaphore>,
    internet_archive: Arc<Semaphore>,
    gutenberg: Arc<Semaphore>,
    loc: Arc<Semaphore>,
    wikisource: Arc<Semaphore>,
    openalex: Arc<Semaphore>,
    oapen: Arc<Semaphore>,
    openaire: Arc<Semaphore>,
    crossref: Arc<Semaphore>,
    wikidata: Arc<Semaphore>,
}

impl RequestGates {
    fn new() -> Self {
        Self {
            google_books: Arc::new(Semaphore::new(1)),
            open_library: Arc::new(Semaphore::new(1)),
            internet_archive: Arc::new(Semaphore::new(1)),
            gutenberg: Arc::new(Semaphore::new(1)),
            loc: Arc::new(Semaphore::new(1)),
            wikisource: Arc::new(Semaphore::new(1)),
            openalex: Arc::new(Semaphore::new(1)),
            oapen: Arc::new(Semaphore::new(1)),
            openaire: Arc::new(Semaphore::new(1)),
            crossref: Arc::new(Semaphore::new(1)),
            wikidata: Arc::new(Semaphore::new(1)),
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum Source {
    GoogleBooks,
    OpenLibrary,
    InternetArchive,
    Gutenberg,
    Loc,
    Wikisource,
    OpenAlex,
    Oapen,
    OpenAire,
    Crossref,
    Wikidata,
}

impl Source {
    fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "google-books" | "googlebooks" => Some(Self::GoogleBooks),
            "open-library" | "openlibrary" => Some(Self::OpenLibrary),
            "internet-archive" | "archive" => Some(Self::InternetArchive),
            "gutenberg" | "gutendex" => Some(Self::Gutenberg),
            "loc" | "library-of-congress" => Some(Self::Loc),
            "wikisource" => Some(Self::Wikisource),
            "openalex" => Some(Self::OpenAlex),
            "oapen" => Some(Self::Oapen),
            "openaire" => Some(Self::OpenAire),
            "crossref" => Some(Self::Crossref),
            "wikidata" => Some(Self::Wikidata),
            _ => None,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::GoogleBooks => "Google Books",
            Self::OpenLibrary => "Open Library",
            Self::InternetArchive => "Internet Archive",
            Self::Gutenberg => "Project Gutenberg (Gutendex)",
            Self::Loc => "Library of Congress",
            Self::Wikisource => "Wikisource",
            Self::OpenAlex => "OpenAlex",
            Self::Oapen => "OAPEN Library",
            Self::OpenAire => "OpenAIRE Graph",
            Self::Crossref => "Crossref",
            Self::Wikidata => "Wikidata",
        }
    }

    fn id(self) -> &'static str {
        match self {
            Self::GoogleBooks => "google-books",
            Self::OpenLibrary => "open-library",
            Self::InternetArchive => "internet-archive",
            Self::Gutenberg => "gutenberg",
            Self::Loc => "loc",
            Self::Wikisource => "wikisource",
            Self::OpenAlex => "openalex",
            Self::Oapen => "oapen",
            Self::OpenAire => "openaire",
            Self::Crossref => "crossref",
            Self::Wikidata => "wikidata",
        }
    }

}

fn parse_books(markdown: &str) -> Vec<Book> {
    let mut books = Vec::new();
    let mut category = String::from("Uncategorised");

    for line in markdown.lines() {
        let line = line.trim();
        if let Some(heading) = line.strip_prefix("## ") {
            category = heading.trim().to_string();
            continue;
        }

        let Some((number, remainder)) = line.split_once(". ") else {
            continue;
        };
        let Ok(id) = number.trim().parse::<u16>() else {
            continue;
        };
        let Some((title, author)) = remainder.split_once(" — ") else {
            continue;
        };
        let title = title.trim();
        let author = author.trim();
        if title.is_empty() || author.is_empty() {
            continue;
        }
        books.push(Book {
            id,
            title: title.to_string(),
            author: author.to_string(),
            category: category.clone(),
        });
    }

    books.sort_by_key(|book| book.id);
    books
}

fn token_set(value: &str) -> HashSet<String> {
    value
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_alphanumeric() { ch } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .map(ToString::to_string)
        .collect()
}

fn overlap_score(left: &str, right: &str) -> f32 {
    let a = token_set(left);
    let b = token_set(right);
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    if a == b {
        return 1.0;
    }
    let intersection = a.intersection(&b).count() as f32;
    let union = a.union(&b).count() as f32;
    intersection / union
}

fn match_confidence(book: &Book, candidate_title: &str, candidate_authors: &str) -> Option<f32> {
    let book_tokens = token_set(&book.title);
    let candidate_tokens = token_set(candidate_title);
    let title_score = overlap_score(&book.title, candidate_title);
    let title_tokens = book_tokens.len();

    // Short titles such as "Flow" or "Quiet" need a near-exact title match.
    if title_tokens <= 2 && title_score < 0.82 {
        return None;
    }

    let title_coverage = if book_tokens.is_empty() {
        0.0
    } else {
        book_tokens.intersection(&candidate_tokens).count() as f32 / book_tokens.len() as f32
    };
    let has_author = !candidate_authors.trim().is_empty()
        && !book.author.eq_ignore_ascii_case("unknown");
    let author_score = if has_author {
        overlap_score(&book.author, candidate_authors)
    } else {
        0.0
    };

    // Require a close title, or the complete original title plus a strong author match.
    // This rejects near-misses like "The Lost Art of War" for "The Art of War".
    let close_title = title_score >= 0.85;
    let exact_title_with_author = has_author
        && title_score >= 0.55
        && title_coverage >= 0.75
        && author_score >= 0.80;
    if !close_title && !exact_title_with_author {
        return None;
    }

    let score = if has_author {
        (title_score * 0.72) + (author_score * 0.28)
    } else {
        title_score
    };

    if score < 0.60 {
        None
    } else {
        Some(score.clamp(0.0, 1.0))
    }
}

fn value_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Array(items) => items.iter().map(value_string).filter(|s| !s.is_empty()).collect::<Vec<_>>().join("; "),
        Value::Object(_) => String::new(),
        _ => String::new(),
    }
}

fn object_string(value: &Value, key: &str) -> String {
    value.get(key).map(value_string).unwrap_or_default()
}

fn add_hit(hits: &mut Vec<Hit>, book: &Book, source: Source, candidate: HitCandidate) {
    let Some(confidence) = match_confidence(book, &candidate.title, &candidate.authors) else {
        return;
    };
    if candidate.url.trim().is_empty() {
        return;
    }
    if hits.iter().any(|hit| {
        hit.book_id == book.id && hit.source == source.name() && hit.url == candidate.url
    }) {
        return;
    }
    hits.push(Hit {
        book_id: book.id,
        book_title: book.title.clone(),
        book_author: book.author.clone(),
        source: source.name().to_string(),
        found_title: candidate.title,
        found_authors: candidate.authors,
        year: candidate.year,
        url: candidate.url,
        access: candidate.access,
        confidence,
        notes: candidate.notes,
    });
}

async fn get_json(client: &Client, url: &str, retry_failed: bool) -> Result<Value> {
    let attempts = if retry_failed { 5 } else { 2 };
    let mut last_error = String::from("request failed");
    for attempt in 0..attempts {
        let mut retry_after = None;
        match client.get(url).header(reqwest::header::ACCEPT, "application/json").send().await {
            Ok(response) if response.status().is_success() => {
                return response.json::<Value>().await.context("The source returned invalid JSON");
            }
            Ok(response) if is_temporary_status(response.status()) => {
                retry_after = response.headers().get(reqwest::header::RETRY_AFTER)
                    .and_then(|value| value.to_str().ok())
                    .and_then(|value| value.parse::<u64>().ok())
                    .map(|seconds| seconds.min(60));
                last_error = format!("temporary HTTP status {}", response.status());
            }
            Ok(response) => bail!("HTTP {}", response.status()),
            Err(error) => last_error = format!("{error:#}"),
        }
        if attempt + 1 < attempts {
            let seconds = retry_after.unwrap_or_else(|| 1u64 << attempt.min(4));
            sleep(Duration::from_secs(seconds)).await;
        }
    }
    bail!("{last_error} after {attempts} attempts")
}

fn is_temporary_status(status: StatusCode) -> bool {
    status == StatusCode::TOO_MANY_REQUESTS
        || status == StatusCode::REQUEST_TIMEOUT
        || status.is_server_error()
}

fn search_query(book: &Book) -> String {
    if book.author.eq_ignore_ascii_case("unknown") {
        book.title.clone()
    } else {
        let primary_author = book.author.split('&').next().unwrap_or(&book.author).split(" and ").next().unwrap_or(&book.author).trim();
        format!("{} {}", book.title, primary_author)
    }
}

async fn search_google_books(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = if book.author.eq_ignore_ascii_case("unknown") {
        format!("intitle:{}", book.title)
    } else {
        format!("intitle:{} inauthor:{}", book.title, book.author)
    };
    let url = format!(
        "https://www.googleapis.com/books/v1/volumes?q={}&maxResults=10&printType=books",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.get("items").and_then(Value::as_array) {
        for item in items {
            let info = &item["volumeInfo"];
            let access_info = &item["accessInfo"];
            let title = object_string(info, "title");
            let authors = value_string(&info["authors"]);
            let year = object_string(info, "publishedDate");
            let link = object_string(access_info, "webReaderLink")
                .or_else_empty(object_string(info, "infoLink"))
                .or_else_empty(object_string(info, "previewLink"));
            if link.is_empty() {
                continue;
            }
            let view = object_string(access_info, "accessViewStatus");
            let pdf_available = access_info["pdf"]["isAvailable"].as_bool().unwrap_or(false);
            let epub_available = access_info["epub"]["isAvailable"].as_bool().unwrap_or(false);
            let (access, notes) = match view.as_str() {
                "FULL_PUBLIC_DOMAIN" => ("Public-domain full text", "Google Books marks this edition as full public-domain access."),
                "FULL_OPEN_ACCESS" => ("Full open access", "Google Books marks this edition as full open access."),
                "ALL_PAGES" => ("Full view reported", "Google Books reports full view; confirm the displayed terms and download options."),
                "PARTIAL" => ("Preview only", "Only a preview is indicated."),
                _ if pdf_available || epub_available => ("Free format reported", "Google Books reports an available PDF or EPUB format; confirm access on the edition page."),
                _ => ("Catalogue / access not verified", "A catalogue record is not proof of free full-text access."),
            };
            add_hit(
                &mut hits,
                book,
                Source::GoogleBooks,
                HitCandidate {
                    title,
                    authors,
                    year,
                    url: link,
                    access: access.to_string(),
                    notes: notes.to_string(),
                },
            );
        }
    }
    Ok(hits)
}

trait EmptyFallback {
    fn or_else_empty(self, fallback: String) -> String;
}
impl EmptyFallback for String {
    fn or_else_empty(self, fallback: String) -> String {
        if self.is_empty() { fallback } else { self }
    }
}

async fn search_open_library(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = search_query(book);
    let url = format!(
        "https://openlibrary.org/search.json?q={}&limit=10&fields=key,title,author_name,first_publish_year,ebook_access,ia",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(docs) = data.get("docs").and_then(Value::as_array) {
        for doc in docs {
            let title = object_string(doc, "title");
            let authors = value_string(&doc["author_name"]);
            let year = object_string(doc, "first_publish_year");
            let key = object_string(doc, "key");
            let access_code = object_string(doc, "ebook_access");
            let ia = value_string(&doc["ia"]);
            let url = if !ia.is_empty() {
                format!("https://archive.org/details/{}", ia.split(';').next().unwrap_or(&ia))
            } else if key.starts_with("/works/") {
                format!("https://openlibrary.org{key}")
            } else {
                continue;
            };
            let (access, notes) = match access_code.as_str() {
                "public" => ("Free online access", "Open Library marks this record as publicly accessible. Check the record for the actual edition and format."),
                "borrowable" => ("Free borrowing", "Borrowing may require a free account and availability can vary."),
                "printdisabled" => ("Accessible lending", "Access may be restricted to eligible print-disabled readers."),
                _ => ("Catalogue / no ebook access shown", "The record does not currently establish free full-text access."),
            };
            add_hit(
                &mut hits,
                book,
                Source::OpenLibrary,
                HitCandidate {
                    title,
                    authors,
                    year,
                    url,
                    access: access.to_string(),
                    notes: notes.to_string(),
                },
            );
        }
    }
    Ok(hits)
}

async fn search_internet_archive(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = format!("title:\"{}\" AND mediatype:texts", book.title.replace('"', " "));
    let url = format!(
        "https://archive.org/advancedsearch.php?q={}&fl[]=identifier,title,creator,year,licenseurl,access-restricted-item&rows=10&page=1&output=json",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(docs) = data.pointer("/response/docs").and_then(Value::as_array) {
        for doc in docs {
            let title = object_string(doc, "title");
            let authors = object_string(doc, "creator");
            let year = object_string(doc, "year");
            let identifier = object_string(doc, "identifier");
            if identifier.is_empty() { continue; }
            let license = object_string(doc, "licenseurl");
            let restricted = object_string(doc, "access-restricted-item");
            let (access, notes) = if !license.is_empty() {
                ("Openly licensed item", "The record has a licence URL. Read the licence before downloading or reusing the file.")
            } else if restricted == "true" {
                ("Borrowing / restricted access", "The record indicates restricted access; availability and account requirements may apply.")
            } else {
                ("Access not verified", "The item exists in the catalogue, but this record alone does not prove unrestricted full-text access.")
            };
            let note = if license.is_empty() { notes.to_string() } else { format!("{notes} Licence: {license}") };
            add_hit(
                &mut hits,
                book,
                Source::InternetArchive,
                HitCandidate {
                    title,
                    authors,
                    year,
                    url: format!("https://archive.org/details/{identifier}"),
                    access: access.to_string(),
                    notes: note,
                },
            );
        }
    }
    Ok(hits)
}

async fn search_gutenberg(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = search_query(book);
    let url = format!("https://gutendex.com/books/?search={}&languages=en", urlencoding::encode(&query));
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.get("results").and_then(Value::as_array) {
        for item in items {
            let title = object_string(item, "title");
            let authors = item.get("authors").and_then(Value::as_array).map(|a| {
                a.iter().map(|person| object_string(person, "name")).collect::<Vec<_>>().join("; ")
            }).unwrap_or_default();
            let id = object_string(item, "id");
            let formats = &item["formats"];
            let preferred = formats.get("application/epub+zip")
                .or_else(|| formats.get("application/pdf"))
                .or_else(|| formats.get("text/plain; charset=utf-8"))
                .or_else(|| formats.get("text/plain"))
                .or_else(|| formats.get("text/html"));
            let url = preferred.map(value_string).filter(|s| !s.is_empty())
                .unwrap_or_else(|| format!("https://www.gutenberg.org/ebooks/{id}"));
            let year = String::new();
            let author_death_years = item.get("authors").and_then(Value::as_array).map(|people| people.iter().map(|person| object_string(person, "death_year")).filter(|value| !value.is_empty()).collect::<Vec<_>>()).unwrap_or_default();
            let rights_note = author_death_years.first().map(|year| format!(" Author death year: {year}.")).unwrap_or_default();
            add_hit(
                &mut hits,
                book,
                Source::Gutenberg,
                HitCandidate {
                    title,
                    authors,
                    year,
                    url,
                    access: "Public-domain full text (Project Gutenberg)".to_string(),
                    notes: format!("Project Gutenberg states this ebook is public domain in the United States; verify local copyright status before redistribution.{rights_note}"),
                },
            );
        }
    }
    Ok(hits)
}

async fn search_loc(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = search_query(book);
    let url = format!(
        "https://www.loc.gov/books/?fo=json&q={}&c=10",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.get("results").and_then(Value::as_array) {
        for item in items {
            let title = object_string(item, "title");
            let authors = item.get("contributor").map(value_string).unwrap_or_default();
            let year = object_string(item, "date");
            let url = object_string(item, "url");
            let online = item.get("online_format").map(value_string).unwrap_or_default();
            let access = if online.to_lowercase().contains("pdf") || online.to_lowercase().contains("image") {
                "Digitised item (check download terms)"
            } else {
                "Catalogue / digital status unclear"
            };
            add_hit(
                &mut hits,
                book,
                Source::Loc,
                HitCandidate {
                    title,
                    authors,
                    year,
                    url,
                    access: access.to_string(),
                    notes: "Library of Congress catalogue result. Open the item to confirm whether a complete, downloadable text is available.".to_string(),
                },
            );
        }
    }
    Ok(hits)
}

async fn search_wikisource(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = format!("\"{}\" ", book.title);
    let url = format!(
        "https://en.wikisource.org/w/api.php?action=query&list=search&srsearch={}&srnamespace=0&srlimit=10&format=json&origin=*&maxlag=1",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.pointer("/query/search").and_then(Value::as_array) {
        for item in items {
            let title = object_string(item, "title");
            let page = urlencoding::encode(&title).replace("%2F", "/");
            add_hit(
                &mut hits,
                book,
                Source::Wikisource,
                HitCandidate {
                    title,
                    authors: String::new(),
                    year: String::new(),
                    url: format!("https://en.wikisource.org/wiki/{page}"),
                    access: "Free text candidate".to_string(),
                    notes: "Wikisource hosts public-domain and freely licensed source texts. Confirm that the page is the complete book, not a chapter, index or discussion page.".to_string(),
                },
            );
        }
    }
    Ok(hits)
}

async fn search_openalex(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = search_query(book);
    let url = format!(
        "https://api.openalex.org/works?search={}&per-page=10&select=id,display_name,publication_year,authorships,open_access,best_oa_location,primary_location",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.get("results").and_then(Value::as_array) {
        for item in items {
            let title = object_string(item, "display_name");
            let authors = item.get("authorships").and_then(Value::as_array).map(|items| {
                items.iter().filter_map(|a| a.pointer("/author/display_name").map(value_string)).collect::<Vec<_>>().join("; ")
            }).unwrap_or_default();
            let year = object_string(item, "publication_year");
            let oa = item.pointer("/open_access/is_oa").and_then(Value::as_bool).unwrap_or(false);
            if !oa { continue; }
            let url = item.pointer("/best_oa_location/pdf_url").map(value_string)
                .filter(|s| !s.is_empty())
                .or_else(|| item.pointer("/best_oa_location/landing_page_url").map(value_string).filter(|s| !s.is_empty()))
                .or_else(|| item.pointer("/primary_location/landing_page_url").map(value_string).filter(|s| !s.is_empty()))
                .unwrap_or_else(|| object_string(item, "id"));
            add_hit(
                &mut hits,
                book,
                Source::OpenAlex,
                HitCandidate {
                    title,
                    authors,
                    year,
                    url,
                    access: "Open-access scholarly document".to_string(),
                    notes: "OpenAlex marks this work as open access. It may be a paper, chapter or related scholarly work, not the requested book itself.".to_string(),
                },
            );
        }
    }
    Ok(hits)
}


fn metadata_values(value: &Value, key: &str) -> Vec<String> {
    let mut values = Vec::new();
    if let Some(metadata) = value.get("metadata") {
        if let Some(field) = metadata.get(key) {
            collect_text_values(field, &mut values);
        }
        if let Some(entries) = metadata.as_array() {
            for entry in entries {
                if entry.get("key").and_then(Value::as_str) == Some(key) {
                    if let Some(field_value) = entry.get("value") {
                        collect_text_values(field_value, &mut values);
                    }
                }
            }
        }
    }
    values.sort();
    values.dedup();
    values
}

fn collect_text_values(value: &Value, output: &mut Vec<String>) {
    match value {
        Value::String(text) if !text.trim().is_empty() => output.push(text.trim().to_string()),
        Value::Number(number) => output.push(number.to_string()),
        Value::Array(items) => {
            for item in items {
                if let Some(text) = item.get("value") {
                    collect_text_values(text, output);
                } else {
                    collect_text_values(item, output);
                }
            }
        }
        Value::Object(object) => {
            if let Some(text) = object.get("value") {
                collect_text_values(text, output);
            } else if let Some(text) = object.get("name") {
                collect_text_values(text, output);
            }
        }
        _ => {}
    }
}

fn collect_oapen_bitstreams(value: &Value, output: &mut Vec<(String, String)>) {
    match value {
        Value::Array(items) => {
            for item in items {
                collect_oapen_bitstreams(item, output);
            }
        }
        Value::Object(object) => {
            let name = object.get("name").map(value_string).unwrap_or_default();
            let format = object.get("format").map(value_string).unwrap_or_default().to_lowercase();
            let mime = object.get("mimeType").map(value_string).unwrap_or_default().to_lowercase();
            let is_book_file = name.to_lowercase().ends_with(".pdf")
                || name.to_lowercase().ends_with(".epub")
                || format.contains("pdf")
                || format.contains("epub")
                || mime.contains("pdf")
                || mime.contains("epub");
            if is_book_file {
                let link = object.get("retrieveLink")
                    .or_else(|| object.get("downloadUrl"))
                    .or_else(|| object.get("link"))
                    .map(value_string)
                    .unwrap_or_default();
                if !link.is_empty() {
                    output.push((name, link));
                }
            }
            for child in object.values() {
                collect_oapen_bitstreams(child, output);
            }
        }
        _ => {}
    }
}

fn oapen_download_url(item: &Value) -> Option<String> {
    let mut files = Vec::new();
    collect_oapen_bitstreams(item.get("bitstreams").unwrap_or(item), &mut files);
    files.into_iter().find_map(|(name, link)| {
        let link = if link.starts_with("http://") || link.starts_with("https://") {
            link
        } else if link.starts_with('/') {
            format!("https://library.oapen.org{link}")
        } else {
            format!("https://library.oapen.org/{link}")
        };
        let value = if name.is_empty() { &link } else { &name };
        let lower = value.to_lowercase();
        if lower.ends_with(".pdf") || lower.ends_with(".epub") {
            Some(link)
        } else {
            None
        }
    })
}

fn search_result_items(data: &Value) -> Vec<&Value> {
    data.pointer("/searchResult/searchResults/entry").and_then(Value::as_array)
        .or_else(|| data.pointer("/searchResult/searchResults").and_then(Value::as_array))
        .or_else(|| data.pointer("/results").and_then(Value::as_array))
        .or_else(|| data.pointer("/searchResult/results").and_then(Value::as_array))
        .map(|items| items.iter().collect())
        .unwrap_or_default()
}

async fn search_oapen(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = format!("dc.title:\"{}\"", book.title.replace('"', " "));
    let url = format!(
        "https://library.oapen.org/rest/search?query={}&expand=metadata,bitstreams&limit=10",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    for item in search_result_items(&data) {
        let title = metadata_values(item, "dc.title").first().cloned()
            .or_else(|| item.get("name").map(value_string)).unwrap_or_default();
        let authors = metadata_values(item, "dc.contributor.author").into_iter()
            .chain(metadata_values(item, "dc.contributor.editor")).collect::<Vec<_>>().join("; ");
        let year = metadata_values(item, "dc.date.issued").first().cloned().unwrap_or_default();
        let license = metadata_values(item, "dc.rights.uri").first().cloned()
            .or_else(|| metadata_values(item, "dc.rights").first().cloned()).unwrap_or_default();
        let handle = item.get("handle").map(value_string).unwrap_or_default();
        let landing = if handle.is_empty() {
            item.get("uuid").map(|id| format!("https://library.oapen.org/items/{}", value_string(id))).unwrap_or_default()
        } else {
            format!("https://library.oapen.org/handle/{handle}")
        };
        let direct = oapen_download_url(item);
        let url = direct.unwrap_or_else(|| landing.clone());
        let access = if license.to_lowercase().contains("creativecommons.org") || license.to_lowercase().contains("publicdomain") {
            "Open-access book (OAPEN; licence metadata listed)"
        } else {
            "OAPEN catalogue record (licence needs review)"
        };
        let notes = if license.is_empty() {
            format!("OAPEN catalogue record. Confirm the item licence and file availability on the publisher repository page: {landing}")
        } else {
            format!("OAPEN publisher repository record. Licence: {license}. Item page: {landing}. Downloads are packaged only when the licence explicitly permits redistribution.")
        };
        add_hit(&mut hits, book, Source::Oapen, HitCandidate {
            title, authors, year, url, access: access.to_string(), notes,
        });
    }
    Ok(hits)
}

async fn search_crossref(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let primary_author = book.author.split('&').next().unwrap_or(&book.author)
        .split(" and ").next().unwrap_or(&book.author).trim();
    let query = format!("{} {}", book.title, primary_author);
    let url = format!(
        "https://api.crossref.org/works?query.bibliographic={}&rows=20",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.pointer("/message/items").and_then(Value::as_array) {
        for item in items {
            let kind = object_string(item, "type").to_lowercase();
            if !["book", "monograph", "edited-book", "reference-book", "book-series", "book-set", "book-chapter"].contains(&kind.as_str()) {
                continue;
            }
            let title = item.get("title").and_then(Value::as_array)
                .and_then(|items| items.first()).map(value_string).unwrap_or_default();
            let authors = item.get("author").and_then(Value::as_array).map(|items| {
                items.iter().map(|person| {
                    format!("{} {}", object_string(person, "given"), object_string(person, "family")).trim().to_string()
                }).filter(|name| !name.is_empty()).collect::<Vec<_>>().join("; ")
            }).unwrap_or_default();
            let year = item.pointer("/published/date-parts/0/0").map(value_string).unwrap_or_default();
            let doi = object_string(item, "DOI");
            let landing = object_string(item, "URL");
            let url = if !landing.is_empty() { landing } else if !doi.is_empty() {
                format!("https://doi.org/{doi}")
            } else {
                continue;
            };
            add_hit(&mut hits, book, Source::Crossref, HitCandidate {
                title, authors, year, url,
                access: "Bibliographic metadata only (Crossref)".to_string(),
                notes: "Crossref verifies bibliographic metadata, not an ebook download or free full text. Follow the publisher or DOI link to check lawful access.".to_string(),
            });
        }
    }
    Ok(hits)
}

fn collect_named_people(value: &Value, output: &mut Vec<String>) {
    match value {
        Value::Array(items) => {
            for item in items { collect_named_people(item, output); }
        }
        Value::Object(object) => {
            for key in ["fullName", "displayName", "name"] {
                if let Some(name) = object.get(key).and_then(Value::as_str) {
                    if !name.trim().is_empty() { output.push(name.trim().to_string()); }
                }
            }
            if output.is_empty() {
                for child in object.values() { collect_named_people(child, output); }
            }
        }
        Value::String(name) if !name.trim().is_empty() => output.push(name.trim().to_string()),
        _ => {}
    }
}

async fn search_openaire(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = search_query(book);
    let url = format!(
        "https://api.openaire.eu/graph/v4/research-products?search={}&page=1&page_size=10",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.get("results").and_then(Value::as_array) {
        for item in items {
            let title = object_string(item, "mainTitle").or_else_empty(object_string(item, "title"));
            let mut names = Vec::new();
            if let Some(authors_value) = item.get("authors").or_else(|| item.get("author")) {
                collect_named_people(authors_value, &mut names);
            }
            let authors = names.join("; ");
            let year = object_string(item, "publicationDate");
            let id = object_string(item, "id");
            let url = item.pointer("/instances/0/webUrl").map(value_string)
                .or_else(|| item.pointer("/instances/0/url").map(value_string))
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| if id.starts_with("http") { id.clone() } else {
                    format!("https://explore.openaire.eu/search/publication?pid={}", urlencoding::encode(&id))
                });
            let oa_note = item.pointer("/bestAccessRight/label").map(value_string)
                .unwrap_or_else(|| "OpenAIRE research-product record".to_string());
            add_hit(&mut hits, book, Source::OpenAire, HitCandidate {
                title, authors, year, url,
                access: "OpenAIRE research record (verify book/full-text status)".to_string(),
                notes: format!("{oa_note}. OpenAIRE includes articles and other research products; this result is not automatically treated as a downloadable book."),
            });
        }
    }
    Ok(hits)
}

async fn search_wikidata(client: &Client, book: &Book, retry: bool) -> Result<Vec<Hit>> {
    let query = search_query(book);
    let url = format!(
        "https://www.wikidata.org/w/api.php?action=wbsearchentities&search={}&language=en&format=json&limit=10",
        urlencoding::encode(&query)
    );
    let data = get_json(client, &url, retry).await?;
    let mut hits = Vec::new();
    if let Some(items) = data.get("search").and_then(Value::as_array) {
        for item in items {
            let title = object_string(item, "label");
            let id = object_string(item, "id");
            if id.is_empty() { continue; }
            add_hit(&mut hits, book, Source::Wikidata, HitCandidate {
                title, authors: String::new(), year: String::new(),
                url: format!("https://www.wikidata.org/wiki/{id}"),
                access: "Bibliographic metadata only (Wikidata)".to_string(),
                notes: format!("Wikidata entity record. Description: {}. This is metadata, not a full-text download.", object_string(item, "description")),
            });
        }
    }
    Ok(hits)
}


async fn search_source(
    client: &Client,
    book: &Book,
    source: Source,
    retry: bool,
    gates: &RequestGates,
) -> Result<Vec<Hit>> {
    let _rate_guard = match source {
        Source::GoogleBooks => {
            let permit = gates.google_books.clone().acquire_owned().await?;
            sleep(Duration::from_millis(3500)).await;
            Some(permit)
        }
        Source::OpenLibrary => {
            let permit = gates.open_library.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1100)).await;
            Some(permit)
        }
        Source::InternetArchive => {
            let permit = gates.internet_archive.clone().acquire_owned().await?;
            sleep(Duration::from_millis(750)).await;
            Some(permit)
        }
        Source::Gutenberg => {
            let permit = gates.gutenberg.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1100)).await;
            Some(permit)
        }
        Source::Loc => {
            let permit = gates.loc.clone().acquire_owned().await?;
            sleep(Duration::from_millis(4500)).await;
            Some(permit)
        }
        Source::Wikisource => {
            let permit = gates.wikisource.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1100)).await;
            Some(permit)
        }
        Source::OpenAlex => {
            let permit = gates.openalex.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1200)).await;
            Some(permit)
        }
        Source::Oapen => {
            let permit = gates.oapen.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1200)).await;
            Some(permit)
        }
        Source::OpenAire => {
            let permit = gates.openaire.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1200)).await;
            Some(permit)
        }
        Source::Crossref => {
            let permit = gates.crossref.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1200)).await;
            Some(permit)
        }
        Source::Wikidata => {
            let permit = gates.wikidata.clone().acquire_owned().await?;
            sleep(Duration::from_millis(1200)).await;
            Some(permit)
        }
    };
    match source {
        Source::GoogleBooks => search_google_books(client, book, retry).await,
        Source::OpenLibrary => search_open_library(client, book, retry).await,
        Source::InternetArchive => search_internet_archive(client, book, retry).await,
        Source::Gutenberg => search_gutenberg(client, book, retry).await,
        Source::Loc => search_loc(client, book, retry).await,
        Source::Wikisource => search_wikisource(client, book, retry).await,
        Source::OpenAlex => search_openalex(client, book, retry).await,
        Source::Oapen => search_oapen(client, book, retry).await,
        Source::OpenAire => search_openaire(client, book, retry).await,
        Source::Crossref => search_crossref(client, book, retry).await,
        Source::Wikidata => search_wikidata(client, book, retry).await,
    }
}

fn html_escape(value: &str) -> String {
    value.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
        .replace('"', "&quot;").replace('\'', "&#39;")
}

fn manual_search_links(book: &Book) -> Vec<(&'static str, String)> {
    let query = format!("\"{}\" \"{}\" ebook", book.title, book.author);
    let encoded = urlencoding::encode(&query);
    vec![
        ("WorldCat", format!("https://search.worldcat.org/search?q={encoded}")),
        ("HathiTrust catalogue search", format!("https://www.google.com/search?q=site%3Acatalog.hathitrust.org+{encoded}")),
        ("Google Books", format!("https://books.google.com/books?q={encoded}")),
        ("Google web search", format!("https://www.google.com/search?q={encoded}")),
        ("Bing", format!("https://www.bing.com/search?q={encoded}")),
        ("DuckDuckGo", format!("https://duckduckgo.com/?q={encoded}")),
        ("Brave Search", format!("https://search.brave.com/search?q={encoded}")),
        ("Google Scholar", format!("https://scholar.google.com/scholar?q={encoded}")),
        ("Directory of Open Access Books (DOAB)", format!("https://directory.doabooks.org/discover?query={encoded}")),
        ("OAPEN Library", format!("https://library.oapen.org/discover?query={encoded}")),
        ("CORE open research", format!("https://core.ac.uk/search?q={encoded}")),
        ("Publisher and university websites", format!("https://www.google.com/search?q={}", urlencoding::encode(&format!("\"{}\" \"{}\" publisher university open access", book.title, book.author)))),
        ("Project Gutenberg", format!("https://www.gutenberg.org/ebooks/search/?query={}", urlencoding::encode(&book.title))),
        ("Standard Ebooks site search", format!("https://www.google.com/search?q=site%3Astandardebooks.org%2Febooks+{}", urlencoding::encode(&book.title))),
        ("Wikisource", format!("https://en.wikisource.org/w/index.php?search={}", urlencoding::encode(&book.title))),
        ("Europeana", format!("https://www.europeana.eu/en/search?query={}", urlencoding::encode(&book.title))),
    ]
}

fn book_report_status(book_id: u16, searched_ids: &HashSet<u16>) -> &'static str {
    if searched_ids.contains(&book_id) {
        "Searched, but no API match was confirmed. Check source errors below if providers failed."
    } else {
        "Not searched in this run. Run a full scan to check this title."
    }
}

async fn write_reports(output: &Path, run: &SearchRun, books: &[Book]) -> Result<()> {
    tokio::fs::create_dir_all(output).await?;
    let json = serde_json::to_string_pretty(run)?;
    tokio::fs::write(output.join("bookhunter-results.json"), json).await?;

    let csv_path = output.join("bookhunter-results.csv");
    let mut writer = csv::WriterBuilder::new().has_headers(false).from_path(&csv_path)?;
    writer.write_record([
        "book_id", "book_title", "book_author", "source", "found_title",
        "found_authors", "year", "url", "access", "confidence", "notes",
    ])?;
    for hit in &run.hits {
        writer.serialize(hit)?;
    }
    writer.flush()?;

    let mut markdown = String::new();
    markdown.push_str("# BookHunter results\n\n");
    markdown.push_str(&format!("- Generated: {}\n- Books in list: {}\n- Books searched: {}\n- Matches: {}\n- Source errors: {}\n\n",
        run.generated_at.to_rfc3339(), run.total_books, run.searched_books, run.hits.len(), run.errors.len()));
    markdown.push_str("> A catalogue record or search result is not proof of legal, unrestricted full-text access. Open each source and verify the edition, licence, territorial copyright status and borrowing conditions.\n\n");

    let mut by_book: BTreeMap<u16, Vec<&Hit>> = BTreeMap::new();
    for hit in &run.hits { by_book.entry(hit.book_id).or_default().push(hit); }
    let searched_ids = run.searched_book_ids.iter().copied().collect::<HashSet<_>>();
    for book in books {
        markdown.push_str(&format!("## {}. {} — {}\n\n*{}*\n\n", book.id, book.title, book.author, book.category));
        if let Some(items) = by_book.get(&book.id) {
            for hit in items {
                markdown.push_str(&format!("- **{}:** [{}]({}) · {} · confidence {:.0}%\n  - {}\n",
                    hit.source, hit.found_title, hit.url, hit.access, hit.confidence * 100.0, hit.notes));
            }
            markdown.push('\n');
        } else {
            markdown.push_str(book_report_status(book.id, &searched_ids));
            markdown.push_str(" Try the manual catalogue links below.\n\n");
        }
        markdown.push_str("Manual search shortcuts (not API-verified):\n");
        for (name, url) in manual_search_links(book) {
            markdown.push_str(&format!("- [{}]({})\n", name, url));
        }
        markdown.push('\n');
    }
    if !run.errors.is_empty() {
        markdown.push_str("## Source errors\n\n");
        for error in &run.errors {
            markdown.push_str(&format!("- Book {} ({}), {}: {}\n", error.book_id, error.book_title, error.source, error.message));
        }
    }
    tokio::fs::write(output.join("bookhunter-results.md"), markdown).await?;

    let mut html = String::from("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>BookHunter results</title><style>:root{color-scheme:light dark}body{font:16px/1.55 system-ui,sans-serif;max-width:1000px;margin:2rem auto;padding:0 1rem}header{border-bottom:1px solid #888;padding-bottom:1rem}.book{padding:1rem 0;border-bottom:1px solid #888}.hit{padding:.8rem;margin:.6rem 0;border:1px solid #888;border-radius:10px}.muted{opacity:.75}.links a{margin-right:.7rem;display:inline-block}a{overflow-wrap:anywhere}.tag{font-size:.85em}</style></head><body>");
    html.push_str(&format!("<header><h1>BookHunter results</h1><p>Generated {} · {} books searched · {} matches · {} source errors</p><p class=\"muted\">API-backed results are separated from manual search shortcuts. A listing is not proof of lawful unrestricted access.</p></header>",
        html_escape(&run.generated_at.to_rfc3339()), run.searched_books, run.hits.len(), run.errors.len()));
    for book in books {
        html.push_str(&format!("<section class=\"book\"><h2>{}. {} <small>— {}</small></h2><p class=\"muted\">{}</p>", book.id, html_escape(&book.title), html_escape(&book.author), html_escape(&book.category)));
        if let Some(items) = by_book.get(&book.id) {
            for hit in items {
                html.push_str(&format!("<article class=\"hit\"><strong>{}</strong> · <span class=\"tag\">{}</span> · match confidence {:.0}%<br><a href=\"{}\" target=\"_blank\" rel=\"noopener\">{}</a><p>{}</p><small>{} {}</small></article>",
                    html_escape(&hit.source), html_escape(&hit.access), hit.confidence * 100.0,
                    html_escape(&hit.url), html_escape(&hit.found_title), html_escape(&hit.notes),
                    html_escape(&hit.found_authors), html_escape(&hit.year)));
            }
        } else {
            html.push_str(&format!("<p class=\"muted\">{}</p>", html_escape(book_report_status(book.id, &searched_ids))));
        }
        html.push_str("<p><strong>Manual search shortcuts (not API-verified):</strong></p><div class=\"links\">");
        for (name, url) in manual_search_links(book) {
            html.push_str(&format!("<a href=\"{}\" target=\"_blank\" rel=\"noopener\">{}</a>", html_escape(&url), html_escape(name)));
        }
        html.push_str("</div></section>");
    }
    if !run.errors.is_empty() {
        html.push_str("<section><h2>Source errors</h2><ul>");
        for error in &run.errors {
            html.push_str(&format!("<li>Book {} · {} · {}: {}</li>", error.book_id, html_escape(&error.book_title), html_escape(&error.source), html_escape(&error.message)));
        }
        html.push_str("</ul></section>");
    }
    html.push_str("</body></html>");
    tokio::fs::write(output.join("bookhunter-results.html"), html).await?;
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    if args.concurrency == 0 || args.concurrency > 32 {
        bail!("--concurrency must be between 1 and 32");
    }
    let markdown = tokio::fs::read_to_string(&args.list).await
        .with_context(|| format!("Could not read book list: {}", args.list.display()))?;
    let mut books = parse_books(&markdown);
    if books.is_empty() {
        bail!("No numbered books found. Expected lines like: 1. Title — Author");
    }
    if let Some(id) = args.book_id {
        books.retain(|book| book.id == id);
        if books.is_empty() { bail!("Book ID {id} was not found in {}", args.list.display()); }
    }

    let mut sources = Vec::new();
    for item in args.sources.split(',').filter(|s| !s.trim().is_empty()) {
        let Some(source) = Source::parse(item) else {
            bail!("Unknown source '{item}'. Run with --help to see the supported IDs.");
        };
        if !sources.iter().any(|found: &Source| found.id() == source.id()) {
            sources.push(source);
        }
    }
    if sources.is_empty() { bail!("No sources selected."); }

    let mut previous_hit_books = HashSet::new();
    let mut carried_forward_hits = Vec::new();
    let mut carried_forward_errors = Vec::new();
    let prior_json = args.output.join("bookhunter-results.json");
    if args.retry_empty && prior_json.exists() {
        if let Ok(content) = tokio::fs::read_to_string(&prior_json).await {
            if let Ok(previous) = serde_json::from_str::<SearchRun>(&content) {
                let selected_ids = books.iter().map(|book| book.id).collect::<HashSet<_>>();
                carried_forward_hits = previous.hits.into_iter()
                    .filter(|hit| selected_ids.contains(&hit.book_id))
                    .collect();
                for hit in &carried_forward_hits {
                    previous_hit_books.insert(hit.book_id);
                }
                carried_forward_errors = previous.errors.into_iter()
                    .filter(|error| previous_hit_books.contains(&error.book_id))
                    .collect();
            }
        }
        books.retain(|book| !previous_hit_books.contains(&book.id));
        if books.is_empty() {
            println!("Every selected book already has at least one recorded API match. Nothing to retry.");
            return Ok(());
        }
    }

    let client = Client::builder()
        .user_agent("BookHunter/0.2 (+https://github.com/Senior-Toasty/books-to-read)")
        .timeout(Duration::from_secs(40))
        .connect_timeout(Duration::from_secs(12))
        .build()?;

    let total_list_books = parse_books(&markdown).len();
    let searched_books = books.len() + previous_hit_books.len();
    let mut searched_book_ids = books.iter().map(|book| book.id).collect::<Vec<_>>();
    searched_book_ids.extend(previous_hit_books.iter().copied());
    searched_book_ids.sort_unstable();
    searched_book_ids.dedup();
    let jobs: Vec<(Book, Source)> = books.iter().flat_map(|book| {
        sources.iter().map(move |source| (book.clone(), *source))
    }).collect();
    let total_jobs = jobs.len();
    println!("BookHunter: {} books × {} API sources = {} requests (max concurrency {}).",
        searched_books, sources.len(), total_jobs, args.concurrency);

    let gates = RequestGates::new();
    let mut hits = Vec::new();
    let mut errors = Vec::new();
    let mut completed = 0usize;
    let mut results = stream::iter(jobs)
        .map(|(book, source)| {
            let client = client.clone();
            let gates = gates.clone();
            async move {
                let result = search_source(&client, &book, source, args.retry_failed, &gates).await;
                (book, source, result)
            }
        })
        .buffer_unordered(args.concurrency);

    while let Some((book, source, result)) = results.next().await {
        completed += 1;
        match result {
            Ok(mut source_hits) => hits.append(&mut source_hits),
            Err(error) => errors.push(SearchError {
                book_id: book.id,
                book_title: book.title.clone(),
                source: source.name().to_string(),
                message: error.to_string(),
            }),
        }
        if completed.is_multiple_of(10) || completed == total_jobs {
            println!("Progress: {completed}/{total_jobs} provider requests · {} matches · {} errors",
                hits.len(), errors.len());
            let checkpoint = SearchRun {
                generated_at: Utc::now(),
                list_file: args.list.display().to_string(),
                total_books: total_list_books,
                searched_books,
                searched_book_ids: searched_book_ids.clone(),
                hits: carried_forward_hits.iter().cloned().chain(hits.iter().cloned()).collect(),
                errors: carried_forward_errors.iter().cloned().chain(errors.iter().cloned()).collect(),
            };
            tokio::fs::create_dir_all(&args.output).await?;
            tokio::fs::write(&prior_json, serde_json::to_vec_pretty(&checkpoint)?).await?;
        }
    }

    hits.extend(carried_forward_hits);
    errors.extend(carried_forward_errors);
    hits.sort_by(|a, b| a.book_id.cmp(&b.book_id).then_with(|| b.confidence.total_cmp(&a.confidence)).then_with(|| a.source.cmp(&b.source)));
    let run = SearchRun {
        generated_at: Utc::now(),
        list_file: args.list.display().to_string(),
        total_books: total_list_books,
        searched_books,
        searched_book_ids,
        hits,
        errors,
    };
    let all_books = parse_books(&markdown);
    write_reports(&args.output, &run, &all_books).await?;
    let matched = run.hits.iter().map(|hit| hit.book_id).collect::<HashSet<_>>().len();
    println!("Finished. {} matches across {} of {} books; {} provider errors.",
        run.hits.len(), matched, run.searched_books, run.errors.len());
    println!("Reports: {}", args.output.display());
    if !run.errors.is_empty() {
        println!("Some sources failed. See bookhunter-results.json and bookhunter-results.md for the error list.");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repository_list_contains_exactly_164_numbered_books() {
        let books = parse_books(include_str!("../README2.md"));
        assert_eq!(books.len(), 164, "README2.md is the source of truth");
        assert_eq!(books.first().unwrap().id, 1);
        assert_eq!(books.last().unwrap().id, 164);
        for (index, book) in books.iter().enumerate() {
            assert_eq!(book.id as usize, index + 1, "book numbering must be continuous");
        }
    }

    #[test]
    fn parser_keeps_category_and_authors() {
        let books = parse_books("# List\n## Psychology\n1. Quiet — Susan Cain\n2. Flow — Mihaly Csikszentmihalyi\n");
        assert_eq!(books.len(), 2);
        assert_eq!(books[0].category, "Psychology");
        assert_eq!(books[0].author, "Susan Cain");
    }

    #[test]
    fn exact_title_and_author_scores_high() {
        let book = Book { id: 1, title: "The Art of War".into(), author: "Sun Tzu".into(), category: "Test".into() };
        assert!(match_confidence(&book, "The Art of War", "Sun Tzu").unwrap() > 0.99);
        assert!(match_confidence(&book, "The Art of Gardening", "Unknown").is_none());
    }

    #[test]
    fn short_titles_need_a_close_match() {
        let book = Book { id: 1, title: "Flow".into(), author: "Mihaly Csikszentmihalyi".into(), category: "Test".into() };
        assert!(match_confidence(&book, "Flow", "").is_some());
        assert!(match_confidence(&book, "Flow State", "").is_none());
    }

    #[test]
    fn report_distinguishes_unsearched_books_from_no_matches() {
        let searched = HashSet::from([8u16, 12u16]);
        assert!(book_report_status(8, &searched).starts_with("Searched"));
        assert!(book_report_status(9, &searched).starts_with("Not searched"));
    }

    #[test]
    fn rejects_near_miss_titles_even_when_tokens_overlap() {
        let book = Book {
            id: 1,
            title: "The Art of War".into(),
            author: "Sun Tzu".into(),
            category: "Test".into(),
        };
        assert!(match_confidence(&book, "The Lost Art of War", "Sun Tzu II").is_none());
        assert!(match_confidence(&book, "Women and the Art of War", "Catherine Huang").is_none());
        assert!(match_confidence(&book, "The Art of War: A Classic Edition", "Sun Tzu").is_some());
    }
}
