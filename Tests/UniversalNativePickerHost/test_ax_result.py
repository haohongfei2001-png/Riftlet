import unittest

from ax_host import classify, ProbeFailure


class AXResultTests(unittest.TestCase):
    def test_submit_requires_both_receipts_and_preserved_draft(self):
        events = ['firstBodyByte', 'expectedCompleteBody']
        self.assertEqual(classify('appkit-file-list', 'EXACT_FILE_SUBMIT_ATTEMPTED', events, True),
                         'VERIFIED_EXTERNAL_FIXTURE_HANDOFF')
        for facts in [(events, False), ([], True), (events[:1], True), (events + ['unexpectedOrDuplicate'], True),
                      (['wrongFirstByte'], False), (['firstBodyByte', 'wrongCompleteBody'], True)]:
            with self.subTest(facts=facts), self.assertRaises(ProbeFailure):
                classify('appkit-file-list', 'EXACT_FILE_SUBMIT_ATTEMPTED', *facts)

    def test_capability_refusal_is_scoped_and_cannot_have_side_effects(self):
        self.assertEqual(classify('system-open-panel', 'SHEET_OWNED_FILE_ROW_UNPROVEN', [], False),
                         'SHEET_OWNED_FILE_ROW_UNPROVEN')
        self.assertEqual(classify('appkit-file-list', 'NOT_RUN_NO_EXISTING_AX_TRUST', [], False),
                         'NOT_RUN_NO_EXISTING_AX_TRUST')
        for prefix in [('appkit-file-list', 'SHEET_OWNED_FILE_ROW_UNPROVEN'),
                       ('system-open-panel', 'UNEXPECTED'), ('appkit-file-list', 'APPKIT_SELECTION_UNKNOWN')]:
            with self.subTest(prefix=prefix), self.assertRaises(ProbeFailure):
                classify(*prefix, [], False)
        with self.assertRaises(ProbeFailure):
            classify('system-open-panel', 'SHEET_OWNED_FILE_ROW_UNPROVEN', ['firstBodyByte'], False)
