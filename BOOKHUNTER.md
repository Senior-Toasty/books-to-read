# BookHunter

BookHunter is a Rust command-line application for finding legitimate access routes to the books in this repository's numbered reading list. It reads **README2.md directly**. The list is not copied into a separate dataset, so the source of truth remains the existing 164-book file.

## What it searches

The app makes API requests to seven sources:

| Source ID | Provider | What the result can establish |
|---|---|---|
| google-books | Google Books Books API | Edition metadata, preview/full-view status and reported PDF/EPUB availability |
| open-library | Open Library Search API | Edition/work records, public ebook access or lending status |
| internet-archive | Internet Archive Advanced Search | Archive records, licence metadata and restricted-access hints |
| gutenberg | Gutendex / Project Gutenberg | Public-domain catalogue entries and available reading formats |
| loc | Library of Congress JSON API | Catalogue and digitised-item records |
| wikisource | English Wikisource MediaWiki API | Candidate public-domain/free source-text pages |
| openalex | OpenAlex Works API | Open-access scholarly works related to a title; not necessarily the book itself |

BookHunter also puts clearly labelled manual search shortcuts for WorldCat, HathiTrust, Google Books, Google, Bing, DuckDuckGo, Brave Search, Google Scholar, Project Gutenberg, Standard Ebooks, Wikisource and Europeana into every report. These are **search links, not automated integrations or verified search results**.

Providers whose public APIs require keys or formal access, including some WorldCat, HathiTrust, Europeana, DPLA and CORE endpoints, are not falsely presented as integrated. They can be added when legitimate credentials and API terms are available.

## Important access and copyright rules

- A catalogue hit is not proof that a complete book is free.
- The reports distinguish public-domain full text, open access, borrowing, preview, catalogue-only and related scholarly records.
- OpenAlex hits may be papers or chapters rather than the requested book.
- Project Gutenberg's public-domain status is based on its stated distribution terms and may not match copyright status in every country. Check the law that applies where you are.
- BookHunter only links to sources. It does not bypass paywalls, DRM, borrowing controls or access restrictions, and it does not download copyrighted books from unauthorised mirrors.
- Always open the result and verify the exact edition, author, licence and access conditions.

## Run locally

Install a current stable Rust toolchain, then run:

```bash
cargo run --release -- --help
cargo run --release -- --output reports
```

Search a single book:

```bash
cargo run --release -- --book-id 1
```

Choose providers and limit request concurrency:

```bash
cargo run --release -- --sources google-books,open-library,gutenberg --concurrency 4 --retry-failed
```

Retry only books with no matches in a previous report in the same output directory:

```bash
cargo run --release -- --retry-empty --retry-failed
```

Reports are generated as:

- `reports/bookhunter-results.html` — phone-friendly results page with clickable links
- `reports/bookhunter-results.json` — complete machine-readable data and source errors
- `reports/bookhunter-results.csv` — spreadsheet-friendly results
- `reports/bookhunter-results.md` — readable Markdown report

## Run from a phone with GitHub Actions

No Rust installation or Termux is required on the phone.

1. Open this repository on GitHub.
2. Open the **Actions** tab.
3. Select **BookHunter search** and tap **Run workflow**.
4. Leave Book ID blank to search all 164 books, or enter a number from 1 to 164.
5. Wait for the workflow to finish, open its run, and download the **bookhunter-report** artifact.
6. Open the HTML report on your phone, or use the CSV/JSON files elsewhere.

A monthly scheduled full search is configured for 03:17 UTC on the first day of each month. Search providers may change their APIs or return incomplete data, so reports include errors instead of silently treating failed sources as empty results. BookHunter also serialises requests to rate-limited catalogues: it waits about 1.1 seconds between Open Library and Wikisource requests, and about 3.1 seconds between Library of Congress requests. A full run can therefore take several minutes; this pacing is deliberate.

## Development checks

The CI workflow runs formatting checks, Clippy, tests and a release build on pushes and pull requests. One test reads README2.md and verifies that the numbered list contains exactly 164 continuously numbered books.
