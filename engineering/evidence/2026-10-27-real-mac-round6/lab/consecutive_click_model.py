"""Proposal-only scheduler fixture. No app imports, I/O, targets or uploads.
Core conflict decisions remain authoritative; start is deliberately not an unlock.
"""
from dataclasses import dataclass
from math import isfinite
import unittest


@dataclass(frozen=True)
class AcceptedSelection:
    asset: str
    lease: str
    epoch: int
    revision: int
    ack: float
    event: float
    observed: float
    accepted: bool = True


class Scheduler:
    """One lane. Calls stand for decisions, not actual Swift or SQLite actions."""
    def __init__(self):
        self.epoch = 1
        self.pending = []
        self.originals = set()
        self.intents = set()
        self.appends = []
        self.cancelled = []
        self.capture_calls = 0

    def accept(self, token):
        if (not token.accepted or token.epoch != self.epoch
                or not all(isfinite(t) for t in (token.ack, token.event, token.observed))
                or not 0 <= token.ack < token.event <= token.observed
                or token.asset in self.originals):
            return False
        self.originals.add(token.asset)
        self.pending.append(token)
        return True

    def step(self, *, visible=True, revision=0, original_lease_valid=True,
             core_blocked=True, intent_commit_allowed=True):
        if not self.pending:
            return 'idle'
        token = self.pending[0]
        if (token.epoch != self.epoch or not visible or revision != token.revision
                or not original_lease_valid):
            self.cancelled.append(self.pending.pop(0))
            return 'cancelBeforeIntent'
        if core_blocked:
            return 'park'
        # Models the final transactional recheck, even after a clear preflight.
        if not intent_commit_allowed:
            return 'park'
        self.pending.pop(0)
        self.intents.add(token.asset)
        self.appends.append((token.asset, token.lease))
        return 'firstInput'

    def invalidate(self):
        self.epoch += 1
        self.cancelled.extend(self.pending)
        self.pending.clear()

    def restart(self):
        self.invalidate()  # prepared is cancelled, never recreated from records
        # Intent tombstones remain observation-only in this conceptual model.


def selected(asset='B', **changes):
    fields = dict(asset=asset, lease='original-lease', epoch=1, revision=0,
                  ack=1.0, event=2.0, observed=2.1)
    fields.update(changes)
    return AcceptedSelection(**fields)


class SchedulingProposalTests(unittest.TestCase):
    def test_started_predecessor_keeps_core_lock(self):
        s = Scheduler(); self.assertTrue(s.accept(selected()))
        self.assertEqual(s.step(core_blocked=True), 'park')
        self.assertEqual(s.appends, [])
        self.assertEqual(len(s.pending), 1)

    def test_ready_unblocks_original_selection_once(self):
        s = Scheduler(); s.accept(selected()); s.step(core_blocked=True)
        self.assertEqual(s.step(core_blocked=False), 'firstInput')
        self.assertEqual(s.step(core_blocked=False), 'idle')
        self.assertEqual(s.appends, [('B', 'original-lease')])
        self.assertEqual(s.capture_calls, 0)

    def test_no_click_backfill(self):
        for changes in ({'ack': 2.0}, {'ack': 3.0}, {'ack': float('nan')},
                        {'event': 3.0}, {'accepted': False}, {'epoch': 2}):
            s = Scheduler(); self.assertFalse(s.accept(selected(**changes)))
            self.assertEqual(s.appends, [])

    def test_invalid_original_lease_is_not_recaptured(self):
        s = Scheduler(); s.accept(selected())
        self.assertEqual(s.step(core_blocked=False, original_lease_valid=False), 'cancelBeforeIntent')
        self.assertEqual(s.appends, []); self.assertEqual(s.capture_calls, 0)

    def test_removed_or_revision_changed_cancels(self):
        for changes in ({'visible': False}, {'revision': 1}):
            s = Scheduler(); s.accept(selected())
            self.assertEqual(s.step(core_blocked=False, **changes), 'cancelBeforeIntent')

    def test_duplicate_asset_never_adds_input(self):
        s = Scheduler(); s.accept(selected())
        self.assertFalse(s.accept(selected()))
        s.step(core_blocked=False)
        self.assertFalse(s.accept(selected()))
        self.assertEqual(len(s.appends), 1)

    def test_lock_race_at_final_transaction_parks(self):
        s = Scheduler(); s.accept(selected())
        self.assertEqual(s.step(core_blocked=False, intent_commit_allowed=False), 'park')
        self.assertEqual(s.appends, [])

    def test_epoch_cancel_has_no_replay(self):
        s = Scheduler(); s.accept(selected()); s.invalidate()
        self.assertEqual(s.step(core_blocked=False), 'idle')
        self.assertEqual(s.appends, [])

    def test_restart_never_replays_prepared_or_intent(self):
        s = Scheduler(); s.accept(selected('A')); s.step(core_blocked=False)
        s.accept(selected('B')); s.restart()
        self.assertEqual(s.step(core_blocked=False), 'idle')
        self.assertEqual(s.appends, [('A', 'original-lease')])
        self.assertIn('A', s.intents)

    def test_fifo_retained_while_parked(self):
        s = Scheduler(); s.accept(selected('B')); s.accept(selected('C'))
        self.assertEqual(s.step(core_blocked=True), 'park')
        s.step(core_blocked=False); s.step(core_blocked=False)
        self.assertEqual([asset for asset, _ in s.appends], ['B', 'C'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
