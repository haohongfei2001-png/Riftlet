"""Offline acceptance predicates. The fake editor process does not access AX, browsers or a provider."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from prepare import prepare
from selection_step import SelectionStep

class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        self.route = dict(applicationID='com.google.Chrome',session='chrome-kernel-v1:101:8:1',windowID='10',tabID='11')
        self.scope = dict(bundle=self.route['applicationID'], pid=101, sessionID=self.route['session'],
                          windowID='10', tabID='11', dynamicSignature=True, exactTemporaryURL=True,
                          originalSelection=True, originalSoleTab=True, systemForeground=True)
        self.script = self.output / 'qa-only'
        self.marker = self.output / 'selection-preparation-once.json'
        self.state = dict(entryID='entry',timeOrigin=1.25,witnessEpoch='qa-epoch', original=True,
                          oldCardsIntact=True, priorCardCount=1, sendClicks=0, formSubmits=0,
                          activeOriginal=True, emptyDOMCaretAtStart=True, textState='empty', geometry=dict(x=4, y=5))

    def run_helper(self, source):
        self.script.write_text('#!/usr/bin/env python3\n' + source)
        self.script.chmod(0o700)
        def read():
            s = dict(self.state)
            if (self.output/'text-present').exists():
                s['textState'] = 'expected'
            return s
        return prepare(self.route, lambda:self.scope, read, self.output, self.script)

    def test_one_insert_one_select_and_final_confirmation(self):
        result = self.run_helper("""import json,sys
from pathlib import Path
print('READY_EMPTY',flush=True)
assert json.loads(input())['token']=='INSERT_ONCE'
Path(__file__).with_name('text-present').touch()
print('TEXT_PRESENT',flush=True)
assert json.loads(input())['token']=='SELECT_ONCE'
print('SELECTION_PRESENT',flush=True)
""")
        self.assertTrue(result['axChecksPassed'])
        last = json.loads(self.marker.read_text().splitlines()[-1])
        self.assertEqual(last['steps'], ['INSERT_INTENT','SELECT_INTENT','AX_RANGE_CONFIRMED'])

    def test_wrong_dom_caret_stops_before_keyboard_input_intent(self):
        self.state['emptyDOMCaretAtStart'] = False
        with self.assertRaisesRegex(ValueError, 'ORIGINAL_COLLAPSED_DOM_CARET_AT_START_REQUIRED'):
            self.run_helper("print('READY_EMPTY',flush=True)\ninput()\n")
        self.assertEqual(self.marker.read_text(), '')

    def test_lost_result_keeps_exclusive_write_intent(self):
        source = "print('READY_EMPTY',flush=True)\ninput()\n"
        with self.assertRaises(RuntimeError):
            self.run_helper(source)
        self.assertEqual(json.loads(self.marker.read_text())['steps'], ['INSERT_INTENT'])
        with self.assertRaises(FileExistsError):
            self.run_helper(source)

    def test_wrong_window_rejected_before_process_or_marker(self):
        self.scope['windowID'] = 'other'
        with self.assertRaisesRegex(ValueError, 'NATIVE_SCOPE_CHANGED'):
            prepare(self.route, lambda:self.scope, lambda:self.state, self.output, self.script)
        self.assertFalse(self.marker.exists())

class ComparisonTests(unittest.TestCase):
    def test_changed_direction_or_anchor_rejected_with_unchanged_text(self):
        row = dict(entryID='entry',timeOrigin=1.25,witnessEpoch='qa-epoch',text='test case',
                   selectedText='case',start=5,end=9,anchor=5,focus=9,direction='forward',priorCardCount=1)
        session = object.__new__(SelectionStep)
        session.before = row
        session.watch = Mock(return_value={'textUnchanged':False,'selectionUnchanged':False})
        session.probe = Mock(return_value=({},dict(row,anchor=9,focus=5,direction='backward')))
        with self.assertRaisesRegex(RuntimeError, 'SELECTION_OR_DRAFT_CHANGED'):
            session.read_page()

if __name__ == '__main__':
    unittest.main()
