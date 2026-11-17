# BookHunter

BookHunter is a Rust application for discovering books from the numbered reading list in README2.md. It searches public catalogue and open-access APIs, records source errors, produces phone-friendly reports, and builds one ZIP containing only files that pass conservative redistribution checks.

## Automated discovery sources

BookHunter currently supports eleven API integrations:

| Source ID | Provider | What it is useful for |
|---|---|---|
| google-books | Google Books Books API | Edition metadata, preview/full-view status and reported PDF/EPUB availability |
| open-library | Open Library Search API | Work/edition records, public ebook status and lending status |
| internet-archive | Internet Archive Advanced Search | Archive records, licence metadata and borrowing restrictions |
| gutenberg | Gutendex / Project Gutenberg | Public-domain catalogue entries and available ebook formats |
| loc | Library of Congress JSON API | Digitised collection records |
| wikisource | English Wikisource MediaWiki API | Candidate public-domain/free source texts |
| openalex | OpenAlex Works API | Open-access scholarly works related to a title |
| oapen | OAPEN Library REST API | Open-access scholarly books, repository licences and PDF/EPUB bitstreams |
| openaire | OpenAIRE Graph API | Open research products and repository records; some may be articles rather than books |
| crossref | Crossref REST API | Book, monograph, edited-book and book-chapter bibliographic records |
| wikidata | Wikidata entity search API | Additional bibliographic metadata and entity records |

The default scan uses Open Library, Internet Archive, Project Gutenberg, Wikisource, OpenAlex, OAPEN, OpenAIRE, Crossref and Wikidata. Google Books and the Library of Congress remain selectable, but are not in the default set because the last full-list run encountered persistent rate-limit responses from those providers.

Each result is a candidate, not a guarantee that the requested edition exists or is free. OpenAIRE and OpenAlex can return related scholarly papers. Crossref and Wikidata supply metadata, not ebooks. Open Library results may require borrowing.

## Downloads and releases

Every successful full search runs the packaging script and creates downloads/bookhunter-books.zip. A GitHub Release is created for that run and includes the ZIP plus the HTML, Markdown and JSON search reports.

The ZIP only includes:

- OAPEN PDF/EPUB files with an explicit CC0, CC BY or CC BY-SA licence. The original source URL and licence are retained in the manifest.
- Project Gutenberg EPUB/PDF/text files where Gutendex lists death years for all authors and the latest co-author death year is 1975 or earlier. This is a conservative screen aligned with South Africa's usual life-plus-50-year term for literary works. It is not a substitute for checking unusual rights situations.

The package intentionally excludes:

- Internet Archive user uploads, even when an item's metadata displays a Creative Commons or Public Domain Mark URL. An uploader-supplied label alone is not enough verification for automatic redistribution.
- Borrow-only or print-disabled lending records, previews, catalogue-only hits, metadata-only records, and records with unclear or non-redistributable licences.
- OAPEN licences outside the explicit redistribution allow-list, such as non-commercial or no-derivatives variants.

If no candidate passes these checks, the workflow still creates the ZIP with its README and manifest explaining why no book files were included. It does not fill the archive with questionable copies just to make the download count look impressive.

## Important access and copyright rules

- A catalogue hit is not proof of a complete, lawful, unrestricted ebook.
- Never bypass paywalls, DRM, borrowing controls or account restrictions.
- Project Gutenberg states its own US public-domain terms; the author-death-year screen is intended to reduce territorial risk in South Africa. Confirm edge cases before redistribution.
- South African Copyright Act section 3 generally gives literary works copyright for the author's life plus 50 years from the end of the year of death. Joint authorship uses the last surviving author.
- Always check the precise edition, licence and source page before sharing a file.

## Manual discovery shortcuts

The HTML and Markdown reports also include manual links to WorldCat, HathiTrust, Google Books, Google, Bing, DuckDuckGo, Brave Search, Google Scholar, DOAB, OAPEN, CORE, OpenAIRE, Crossref, Wikidata, DPLA, Smithsonian Open Access, Biodiversity Heritage Library, Gallica, Europeana, Project Gutenberg, Standard Ebooks, Wikisource, the Library of Congress, Internet Archive, publisher sites and university sites.

Some services, including DPLA, Smithsonian and Biodiversity Heritage Library API endpoints, require an API key. They are listed as manual discovery routes and are not falsely described as active API integrations.

## Run locally

Install a current stable Rust toolchain and Python 3, then run:

~~~bash
cargo run --release -- --help
cargo run --release -- --output reports
python3 scripts/package_legal_downloads.py --report reports/bookhunter-results.json --output downloads
~~~

Choose sources and limit request concurrency:

~~~bash
cargo run --release -- --sources open-library,internet-archive,gutenberg,oapen,openaire,crossref,wikidata --concurrency 4 --retry-failed
~~~

Search one book:

~~~bash
cargo run --release -- --book-id 8 --sources open-library,oapen,crossref --retry-failed
~~~

## Run from a phone with GitHub Actions

No Rust installation or Termux is required.

1. Open this repository on GitHub.
2. Open the Actions tab.
3. Select BookHunter search and tap Run workflow.
4. Leave the source field as all, keep retries enabled, and use concurrency 4 or 8.
5. When the run finishes, open its GitHub Release to download bookhunter-books.zip. The HTML report is also attached.

The workflow runs a full scan of README2.md; it does not accept a single-book filter. It also uploads a separate report artifact for troubleshooting. A monthly scheduled full scan is configured.

## Reports

- reports/bookhunter-results.html — phone-friendly results page
- reports/bookhunter-results.json — complete machine-readable results and source errors
- reports/bookhunter-results.csv — spreadsheet-friendly matches
- reports/bookhunter-results.md — readable report
- downloads/bookhunter-books.zip — one ZIP containing eligible downloads and a licence manifest
- downloads/download-manifest.csv / .json — file-by-file source and licence details

## Development checks

CI runs rustfmt, Clippy, Rust tests, a release build, a one-book API smoke search, and Python tests for the download/redistribution filters.
