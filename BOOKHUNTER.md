# BookHunter

BookHunter is a Rust application for discovering books from the numbered reading list in README2.md. It searches public catalogue and open-access APIs, records source errors, produces phone-friendly reports, and builds one ZIP containing only files that pass conservative redistribution checks.

## Automated discovery sources

BookHunter has thirteen API integrations:

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
| doab | Directory of Open Access Books REST API | Curated open-access book metadata and repository records |
| openaire | OpenAIRE Graph API | Open research products and repository records; some may be articles rather than books |
| crossref | Crossref REST API | Book, monograph, edited-book and book-chapter bibliographic records |
| wikidata | Wikidata entity search API | Additional bibliographic metadata and entity records |
| zenodo | Zenodo REST API | Published repository records and their metadata; files/licences must be checked individually |

The default scan enables all thirteen sources. Every provider has its own request gate and pacing delay. The scan retries temporary failures when the retry setting is enabled. Google Books and Library of Congress are paced more slowly because the previous scan encountered rate limits.

Each result is a candidate, not a guarantee that the requested edition exists or is free. OpenAIRE and OpenAlex can return related scholarly papers. Crossref, Wikidata and Zenodo records supply bibliographic metadata; they are not automatically treated as ebook downloads. Open Library records may require borrowing.

Official source documentation:
- [DOAB REST API and metadata](https://doabooks.org/en/librarians/doab-metadata)
- [Zenodo REST API](https://developers.zenodo.org/)
- [OpenAIRE Graph API](https://graph.openaire.eu/docs/apis/)
- [Crossref REST API](https://www.crossref.org/documentation/retrieve-metadata/rest-api/)
- [OAPEN REST API](https://library.oapen.org/)

## Downloads and releases

Every completed full search runs the packaging script and creates downloads/bookhunter-books.zip. The workflow creates a GitHub Release for that scan and attaches the ZIP plus the HTML, Markdown, JSON and CSV search reports.

The ZIP includes only:

- OAPEN and DOAB PDF/EPUB files with an explicit CC0, CC BY or CC BY-SA licence and a direct file hosted by the respective repository.
- Project Gutenberg EPUB/PDF/text files where Gutendex lists death years for every author and the latest co-author death year is 1975 or earlier. This is a conservative screening rule intended to reduce South African copyright risk. It is not a legal guarantee for unusual rights situations.

The package intentionally excludes:

- Internet Archive user uploads, even when an item's metadata displays a Creative Commons or Public Domain Mark URL. An uploader-supplied label alone is not enough verification for automatic redistribution.
- Borrow-only or print-disabled lending records, previews, catalogue-only hits, metadata-only records, Zenodo files and records with unclear or non-redistributable licences.
- OAPEN/DOAB licences outside the explicit redistribution allow-list, such as non-commercial or no-derivatives variants.
- Any URL that is not a direct PDF, EPUB or plain-text file on an approved source host.

If no candidate passes these checks, the workflow still creates a ZIP with its README and manifest explaining why no book files were included. It does not fill the archive with questionable copies just to make the download count look impressive.

## Important access and copyright rules

- A catalogue hit is not proof of a complete, lawful, unrestricted ebook.
- Never bypass paywalls, DRM, borrowing controls or account restrictions.
- Project Gutenberg states its own US public-domain terms. The author-death-year screen is intended to reduce territorial risk in South Africa, but exceptions can apply.
- Section 3 of South Africa's Copyright Act generally provides life-plus-50-years for literary works, calculated from the end of the year of death. For joint authorship, the relevant death is the last surviving author. See the [Copyright Act](https://www.gov.za/sites/default/files/gcis_document/201504/act-98-1978.pdf).
- Always check the precise edition, licence and source page before sharing a file.

## Manual discovery shortcuts

The HTML and Markdown reports include manual links to WorldCat, HathiTrust, Google Books, Google, Bing, DuckDuckGo, Brave Search, Google Scholar, DOAB, OAPEN, CORE, OpenAIRE, Crossref, Wikidata, DPLA, Smithsonian Open Access, Biodiversity Heritage Library, Gallica, Europeana, Project Gutenberg, Standard Ebooks, Wikisource, Library of Congress, Internet Archive, publisher sites and university sites.

Some services, including DPLA, Smithsonian and Biodiversity Heritage Library API endpoints, require an API key. They are listed as manual discovery routes and are not falsely described as active API integrations.

## Run locally

Install a current stable Rust toolchain and Python 3, then run:

~~~bash
cargo run --release -- --help
cargo run --release -- --output reports --retry-failed
python3 scripts/package_legal_downloads.py --report reports/bookhunter-results.json --output downloads
~~~

Choose sources and limit request concurrency:

~~~bash
cargo run --release -- --sources google-books,open-library,internet-archive,gutenberg,loc,wikisource,openalex,oapen,doab,openaire,crossref,wikidata,zenodo --concurrency 4 --retry-failed
~~~

## Run from a phone with GitHub Actions

No Rust installation or Termux is required.

1. Open this repository on GitHub.
2. Open the Actions tab.
3. Select BookHunter search and tap Run workflow.
4. Leave Sources as all, keep retries enabled, and use concurrency 4 or 8.
5. When the run finishes, open its GitHub Release and download bookhunter-books.zip. The reports are attached to the same release.

The workflow always reads the complete README2.md list. It checks the report before packaging to ensure all listed books were searched. It also uploads a separate troubleshooting artifact. A monthly scheduled full scan is configured.

## Reports

- reports/bookhunter-results.html — phone-friendly results page
- reports/bookhunter-results.json — complete machine-readable results and source errors
- reports/bookhunter-results.csv — spreadsheet-friendly matches
- reports/bookhunter-results.md — readable report
- downloads/bookhunter-books.zip — one ZIP containing eligible downloads and a licence manifest
- downloads/download-manifest.csv / .json — file-by-file source and licence details

## Development checks

CI runs rustfmt, Clippy, Rust tests, a release build, a one-book API smoke search, and Python tests for the download/redistribution filters.
