"""Fault injection for export admission, independent of historical UI assertions."""
from pathlib import Path
import tempfile
import unittest
from verify_delivery import ROOT, expected_payloads, validate_html


class DeliveryValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.valid = (ROOT / 'exports/Riftlet-Experience-Prototype.html').read_text(encoding='utf-8')

    def test_current_export_matches_sources_and_parses(self):
        self.assertEqual(validate_html(self.valid, ROOT / 'prototype')['result'], 'PASS')

    def test_exact_historical_broken_export_is_rejected(self):
        broken = (ROOT / 'evidence/export-repair-20261107/before-standalone.html').read_text(encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'not byte-identical'):
            validate_html(broken, ROOT / 'prototype')

    def test_dollar_replacement_corruption_cannot_be_admitted(self):
        self.assertGreater(self.valid.count('$$'), 0)
        with self.assertRaisesRegex(ValueError, 'not byte-identical'):
            validate_html(self.valid.replace('$$', '$'), ROOT / 'prototype')

    def test_even_exact_source_with_a_syntax_error_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix='riftlet-export-source-') as directory:
            p = Path(directory)
            (p / 'assets').mkdir()
            (p / 'assets/riftlet.svg').write_bytes((ROOT / 'prototype/assets/riftlet.svg').read_bytes())
            for name in ('samples.js', 'baselines.js', 'settings.js', 'app.css', 'settings.css'):
                (p / name).write_text('', encoding='utf-8')
            (p / 'app.js').write_text('const $ = 1, $ = 2;', encoding='utf-8')
            js, css, logo = expected_payloads(p)
            document = '<link rel="icon" href="'+logo+'"><style>\n'+css+'\n</style><script>\n'+js+'\n</script>'
            with self.assertRaisesRegex(ValueError, 'syntax gate failed'):
                validate_html(document, p)

    def test_unembedded_resource_and_stale_css_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'non-embedded resource'):
            validate_html(self.valid.replace('</head>', '<link rel="stylesheet" href="forgotten.css"></head>'), ROOT / 'prototype')
        with self.assertRaisesRegex(ValueError, 'CSS is not byte-identical'):
            validate_html(self.valid.replace('<style>', '<style>/* stale */', 1), ROOT / 'prototype')


if __name__ == '__main__':
    unittest.main(verbosity=2)
