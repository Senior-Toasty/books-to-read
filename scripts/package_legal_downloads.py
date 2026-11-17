#!/usr/bin/env python3
"""Download only redistribution-eligible editions and build one ZIP release asset.

This deliberately does not download lending-only Open Library/Internet Archive
records or arbitrary Internet Archive uploads. A metadata licence flag alone is
not reliable proof that a commercial book was uploaded with the rightsholder's
permission.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

GUTENBERG_HOSTS = {"www.gutenberg.org", "gutenberg.org"}
OAPEN_HOSTS = {"library.oapen.org"}
MAX_FILE_BYTES = 80 * 1024 * 1024
MAX_TOTAL_BYTES = 500 * 1024 * 1024


def extension_for_url(url: str) -> str | None:
    path = urllib.parse.urlparse(url).path.lower()
    for suffix in (".epub3.images", ".epub3.noimages", ".epub.images", ".epub.noimages", ".epub3", ".epub"):
        if path.endswith(suffix):
            return ".epub"
    for suffix in (".txt.utf-8", ".txt.utf8", ".pdf", ".txt"):
        if path.endswith(suffix):
            return ".txt" if suffix in {".txt.utf-8", ".txt.utf8"} else suffix
    return None


def canonical_redistribution_license(license_text: str) -> str | None:
    """Return a canonical URL only for clearly identified reusable licences."""
    value = license_text.lower().strip().replace("_", "-")
    if "creativecommons.org/publicdomain/zero/" in value or value in {"cc0", "cc0-1.0", "cc zero"}:
        return "https://creativecommons.org/publicdomain/zero/1.0/"
    if "creativecommons.org/publicdomain/mark/" in value or value in {"pdm", "public domain mark"}:
        return "https://creativecommons.org/publicdomain/mark/1.0/"
    if "creativecommons.org/licenses/by-sa/" in value or value in {"cc by-sa", "cc-by-sa", "cc by-sa 4.0", "cc-by-sa-4.0", "creative commons attribution-sharealike 4.0 international"}:
        return "https://creativecommons.org/licenses/by-sa/4.0/"
    if "creativecommons.org/licenses/by/" in value or value in {"cc by", "cc-by", "cc by 4.0", "cc-by-4.0", "creative commons attribution 4.0 international"}:
        return "https://creativecommons.org/licenses/by/4.0/"
    return None


def candidate_for_hit(hit: dict[str, Any]) -> dict[str, Any] | None:
    source = str(hit.get("source", ""))
    url = str(hit.get("url", "")).strip()
    notes = str(hit.get("notes", ""))
    ext = extension_for_url(url)
    if not ext:
        return None

    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()

    if source == "Project Gutenberg (Gutendex)":
        if host not in GUTENBERG_HOSTS:
            return None
        match = re.search(r"Latest author death year:\s*(\d{4})", notes)
        if not match or int(match.group(1)) > 1975:
            return None
        return {
            "book_id": hit.get("book_id"),
            "title": hit.get("book_title", hit.get("found_title", "Unknown")),
            "author": hit.get("book_author", ""),
            "source": source,
            "url": url,
            "extension": ext,
            "license": "South African public-domain screen: latest listed co-author death year is 1975 or earlier; source is Project Gutenberg",
            "notes": "Project Gutenberg notes that its ebooks are public domain in the United States. The author-death-year screen is a conservative check against South Africa's usual life-plus-50-year term; confirm special cases before redistribution.",
        }

    if source in {"OAPEN Library", "Directory of Open Access Books (DOAB)"}:
        allowed_hosts = OAPEN_HOSTS if source == "OAPEN Library" else {"directory.doabooks.org"}
        if host not in allowed_hosts:
            return None
        license_match = re.search(r"Licence:\s*(https?://\S+|[^.\n]+)", notes)
        if not license_match:
            return None
        raw_license = license_match.group(1).rstrip(".,;)")
        license_text = canonical_redistribution_license(raw_license)
        if not license_text:
            return None
        return {
            "book_id": hit.get("book_id"),
            "title": hit.get("book_title", hit.get("found_title", "Unknown")),
            "author": hit.get("book_author", ""),
            "source": source,
            "url": url,
            "extension": ext,
            "license": license_text,
            "notes": "Curated open-access repository file with an explicit CC0, CC BY or CC BY-SA licence. Preserve attribution and licence notices.",
        }

    # In particular, do not auto-download Internet Archive user uploads just
    # because their metadata contains a CC/PD URL. Verify and download those
    # manually on the item's page.
    return None


def safe_filename(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._ -]+", "", value).strip(" .")
    value = re.sub(r"\s+", " ", value)
    return value[:90] or "Untitled"


def verify_file(path: Path, extension: str) -> bool:
    try:
        with path.open("rb") as handle:
            head = handle.read(512)
        if extension == ".pdf":
            return head.startswith(b"%PDF-")
        if extension == ".epub":
            if not head.startswith(b"PK"):
                return False
            with zipfile.ZipFile(path) as archive:
                return "mimetype" in archive.namelist() and "META-INF/container.xml" in archive.namelist()
        if extension == ".txt":
            return bool(head) and b"\x00" not in head and not head.lstrip().lower().startswith((b"<!doctype html", b"<html"))
    except (OSError, zipfile.BadZipFile):
        return False
    return False


def download_candidate(candidate: dict[str, Any], destination: Path) -> int:
    request = urllib.request.Request(
        candidate["url"],
        headers={"User-Agent": "BookHunter/0.2 (+https://github.com/Senior-Toasty/books-to-read)"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        final_host = (urllib.parse.urlparse(response.geturl()).hostname or "").lower()
        allowed = GUTENBERG_HOSTS if candidate["source"] == "Project Gutenberg (Gutendex)" else (OAPEN_HOSTS if candidate["source"] == "OAPEN Library" else {"directory.doabooks.org"})
        if final_host not in allowed:
            raise ValueError(f"download redirected to an unapproved host: {final_host}")
        content_type = response.headers.get_content_type().lower()
        if content_type in {"text/html", "application/xhtml+xml"}:
            raise ValueError("provider returned a web page instead of a book file")
        declared_size = response.headers.get("Content-Length")
        if declared_size and int(declared_size) > MAX_FILE_BYTES:
            raise ValueError("file exceeds the 80 MiB per-book limit")

        total = 0
        with destination.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_FILE_BYTES:
                    raise ValueError("file exceeded the 80 MiB per-book limit")
                output.write(chunk)

    if total == 0 or not verify_file(destination, candidate["extension"]):
        destination.unlink(missing_ok=True)
        raise ValueError("download did not pass file-format verification")
    return total


def build_package(report_path: Path, output_dir: Path) -> dict[str, Any]:
    report = json.loads(report_path.read_text(encoding="utf-8"))
    output_dir.mkdir(parents=True, exist_ok=True)
    files_dir = output_dir / "books"
    if files_dir.exists():
        shutil.rmtree(files_dir)
    files_dir.mkdir(parents=True)

    candidates = []
    for hit in report.get("hits", []):
        candidate = candidate_for_hit(hit)
        if candidate:
            candidates.append(candidate)

    # Prefer publisher-hosted OAPEN editions; keep at most one file per reading-list entry.
    candidates.sort(key=lambda item: (0 if item["source"] == "OAPEN Library" else 1, int(item["book_id"])))
    used_books: set[int] = set()
    downloaded = []
    errors = []
    total_bytes = 0

    for candidate in candidates:
        book_id = int(candidate["book_id"])
        if book_id in used_books:
            continue
        if total_bytes >= MAX_TOTAL_BYTES:
            errors.append({"book_id": book_id, "error": "overall 500 MiB package limit reached"})
            break

        filename = f"{book_id:03d} - {safe_filename(str(candidate['title']))}{candidate['extension']}"
        destination = files_dir / filename
        try:
            size = download_candidate(candidate, destination)
            if total_bytes + size > MAX_TOTAL_BYTES:
                destination.unlink(missing_ok=True)
                errors.append({"book_id": book_id, "error": "overall 500 MiB package limit reached"})
                continue
            total_bytes += size
            used_books.add(book_id)
            candidate["filename"] = f"books/{filename}"
            candidate["size_bytes"] = size
            downloaded.append(candidate)
            print(f"Downloaded book {book_id}: {filename} ({size:,} bytes)")
        except (OSError, urllib.error.URLError, ValueError, zipfile.BadZipFile) as error:
            destination.unlink(missing_ok=True)
            errors.append({"book_id": book_id, "title": candidate["title"], "error": str(error)})
            print(f"Skipped book {book_id}: {error}", file=sys.stderr)

    manifest_path = output_dir / "download-manifest.json"
    manifest_path.write_text(json.dumps({
        "generated_from": str(report_path),
        "report_generated_at": report.get("generated_at"),
        "eligible_files": len(downloaded),
        "eligible_books": sorted(used_books),
        "total_bytes": total_bytes,
        "downloads": downloaded,
        "skipped_downloads": errors,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    csv_path = output_dir / "download-manifest.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["book_id", "title", "author", "source", "filename", "size_bytes", "license", "url"])
        writer.writeheader()
        for item in downloaded:
            writer.writerow({key: item.get(key, "") for key in writer.fieldnames})

    readme = output_dir / "README.txt"
    readme.write_text(
        "BOOKHUNTER LEGAL DOWNLOAD BUNDLE\n"
        "================================\n\n"
        f"Books included: {len(downloaded)}\n"
        f"Total file size: {total_bytes:,} bytes\n\n"
        "Only files from Project Gutenberg that pass a conservative South African author-death-year screen,\n"
        "and OAPEN/DOAB repository files carrying explicit CC0, CC BY or CC BY-SA licences, are included.\n"
        "Internet Archive user uploads, lending-only records, previews, metadata-only entries, and links\n"
        "with unclear or non-redistributable terms are intentionally excluded.\n\n"
        "Keep the original licence and attribution information. See download-manifest.csv and\n"
        "download-manifest.json for the source URL and licence associated with each file.\n"
        "Copyright exceptions and terms can vary by work and territory; verify any edge cases before sharing.\n",
        encoding="utf-8",
    )

    zip_path = output_dir / "bookhunter-books.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.write(readme, "README.txt")
        archive.write(manifest_path, "download-manifest.json")
        archive.write(csv_path, "download-manifest.csv")
        for file in sorted(files_dir.iterdir()):
            if file.is_file():
                archive.write(file, f"books/{file.name}")

    release_notes = output_dir / "RELEASE_NOTES.md"
    release_notes.write_text(
        "# BookHunter download release\n\n"
        f"- Reading-list entries searched: {report.get('searched_books', 0)} / {report.get('total_books', 0)}\n"
        f"- Catalogue matches: {len(report.get('hits', []))}\n"
        f"- Verified files packaged: {len(downloaded)}\n"
        f"- Download bundle size: {total_bytes:,} bytes\n"
        f"- Provider errors: {len(report.get('errors', []))}\n\n"
        "The ZIP contains only direct files that pass BookHunter's conservative redistribution checks.\n"
        "It does not contain lending-only scans, previews, metadata-only results, or unverified uploads.\n"
        "See the attached search report for all catalogue matches and manual access links.\n",
        encoding="utf-8",
    )

    return {
        "zip": str(zip_path),
        "downloaded_files": len(downloaded),
        "downloaded_books": len(used_books),
        "total_bytes": total_bytes,
        "skipped": len(errors),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("downloads"))
    args = parser.parse_args()
    result = build_package(args.report, args.output)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
