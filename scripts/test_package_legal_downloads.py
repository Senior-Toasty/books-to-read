import unittest

from package_legal_downloads import candidate_for_hit, extension_for_url


class CandidateRulesTest(unittest.TestCase):
    def base(self, **overrides):
        item = {
            "book_id": 8,
            "book_title": "The Art of War",
            "book_author": "Sun Tzu",
            "source": "Project Gutenberg (Gutendex)",
            "url": "https://www.gutenberg.org/cache/epub/132/pg132-images-3.epub",
            "access": "Public-domain full text (Project Gutenberg)",
            "notes": "Latest author death year: 496.",
        }
        item.update(overrides)
        return item

    def test_accepts_gutenberg_with_south_african_pd_screen(self):
        result = candidate_for_hit(self.base())
        self.assertIsNotNone(result)
        self.assertEqual(result["extension"], ".epub")

    def test_rejects_unknown_or_recent_author_death(self):
        self.assertIsNone(candidate_for_hit(self.base(notes="No author dates available.")))
        self.assertIsNone(candidate_for_hit(self.base(notes="Latest author death year: 1976.")))

    def test_rejects_gutenberg_landing_pages_and_unapproved_hosts(self):
        self.assertIsNone(candidate_for_hit(self.base(url="https://www.gutenberg.org/ebooks/132")))
        self.assertIsNone(candidate_for_hit(self.base(url="https://mirror.example/pg132.epub")))

    def test_accepts_oapen_cc_by_direct_pdf(self):
        result = candidate_for_hit({
            "book_id": 20,
            "book_title": "Open Access Book",
            "book_author": "Author",
            "source": "OAPEN Library",
            "url": "https://library.oapen.org/bitstream/handle/20.500.12657/12345/book.pdf",
            "notes": "Licence: https://creativecommons.org/licenses/by/4.0/. Item page: https://library.oapen.org/handle/12345",
        })
        self.assertIsNotNone(result)
        self.assertEqual(result["extension"], ".pdf")

    def test_rejects_non_redistributable_oapen_licences(self):
        hit = {
            "book_id": 20,
            "book_title": "Restricted",
            "book_author": "Author",
            "source": "OAPEN Library",
            "url": "https://library.oapen.org/bitstream/handle/20.500.12657/12345/book.pdf",
            "notes": "Licence: https://creativecommons.org/licenses/by-nc-nd/4.0/. Item page: https://library.oapen.org/handle/12345",
        }
        self.assertIsNone(candidate_for_hit(hit))

    def test_rejects_internet_archive_uploads_even_with_a_cc_label(self):
        hit = {
            "book_id": 73,
            "book_title": "A modern bestseller",
            "book_author": "Living Author",
            "source": "Internet Archive",
            "url": "https://archive.org/download/example/book.pdf",
            "notes": "Licence: https://creativecommons.org/publicdomain/mark/1.0/",
        }
        self.assertIsNone(candidate_for_hit(hit))

    def test_recognises_gutenberg_text_extension(self):
        self.assertEqual(extension_for_url("https://www.gutenberg.org/files/132/132-0.txt.utf-8"), ".txt")

    def test_recognises_gutenberg_epub_variants(self):
        self.assertEqual(extension_for_url("https://www.gutenberg.org/ebooks/132.epub.images"), ".epub")
        self.assertEqual(extension_for_url("https://www.gutenberg.org/ebooks/132.epub3.noimages"), ".epub")

    def test_accepts_doab_direct_cc_by_sa_file(self):
        result = candidate_for_hit({
            "book_id": 21,
            "book_title": "Open Book",
            "book_author": "Author",
            "source": "Directory of Open Access Books (DOAB)",
            "url": "https://directory.doabooks.org/bitstream/handle/20.500.12854/123/book.epub",
            "notes": "Licence: https://creativecommons.org/licenses/by-sa/4.0/. Item page: https://directory.doabooks.org/handle/123",
        })
        self.assertIsNotNone(result)
        self.assertEqual(result["extension"], ".epub")

    def test_rejects_doab_files_from_external_unknown_hosts(self):
        hit = {
            "book_id": 22,
            "book_title": "Open Book",
            "book_author": "Author",
            "source": "Directory of Open Access Books (DOAB)",
            "url": "https://untrusted.example/book.pdf",
            "notes": "Licence: https://creativecommons.org/licenses/by/4.0/. Item page: https://directory.doabooks.org/handle/123",
        }
        self.assertIsNone(candidate_for_hit(hit))



if __name__ == "__main__":
    unittest.main()
