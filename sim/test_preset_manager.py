"""Run from the repository root: python3 -m unittest discover -s sim -v."""

import unittest
from dataclasses import FrozenInstanceError

from preset import Preset, PresetConfig, PresetStatus as Status
from preset_manager import PresetManager


def make_preset(name="A", gain=0.0, bypass=False):
    return Preset(name, PresetConfig(bypass=bypass, input_gain_db=gain))


class PresetManagerTests(unittest.TestCase):
    def setUp(self):
        self.manager = PresetManager()

    def test_submit_valid_preset_waits_for_activation(self):
        candidate = make_preset()
        self.manager.submit(candidate)
        self.assertIs(self.manager.pending, candidate)
        self.assertEqual(candidate.status, Status.PENDING)
        self.assertIsNone(self.manager.active)

    def test_first_activation_clears_pending_slot(self):
        candidate = make_preset()
        self.manager.submit(candidate)
        self.manager.activate()
        self.assertIs(self.manager.active, candidate)
        self.assertEqual(candidate.status, Status.ACTIVE)
        self.assertIsNone(self.manager.pending)

    def test_activation_without_pending_is_a_no_op(self):
        self.manager.activate()
        self.assertIsNone(self.manager.active)
        self.assertIsNone(self.manager.pending)

        candidate = make_preset()
        self.manager.submit(candidate)
        self.manager.activate()
        self.manager.activate()
        self.assertIs(self.manager.active, candidate)
        self.assertEqual(candidate.status, Status.ACTIVE)
        self.assertIsNone(self.manager.pending)

    def test_latest_pending_wins_and_active_retires_only_on_activation(self):
        a, b, c = (make_preset(name) for name in ("A", "B", "C"))
        self.manager.submit(a)
        self.manager.activate()
        self.manager.submit(b)
        self.manager.submit(c)

        self.assertIs(self.manager.active, a)
        self.assertEqual(a.status, Status.ACTIVE)
        self.assertEqual(b.status, Status.SUPERSEDED)
        self.assertIs(self.manager.pending, c)
        self.assertEqual(c.status, Status.PENDING)

        self.manager.activate()
        self.assertEqual(a.status, Status.RETIRED)
        self.assertEqual(b.status, Status.SUPERSEDED)
        self.assertIs(self.manager.active, c)
        self.assertEqual(c.status, Status.ACTIVE)
        self.assertIsNone(self.manager.pending)

    def test_invalid_submission_preserves_active_and_pending(self):
        a, b = make_preset("A"), make_preset("B")
        self.manager.submit(a)
        self.manager.activate()
        self.manager.submit(b)
        c = make_preset("C", gain=13.0)
        self.manager.submit(c)

        self.assertEqual(c.status, Status.REJECTED)
        self.assertTrue(c.rejection_reason)
        self.assertIs(self.manager.active, a)
        self.assertEqual(a.status, Status.ACTIVE)
        self.assertIs(self.manager.pending, b)
        self.assertEqual(b.status, Status.PENDING)
        self.manager.activate()
        self.assertIs(self.manager.active, b)
        self.assertEqual(b.status, Status.ACTIVE)

    def test_non_draft_submission_raises_without_changing_slots(self):
        a, b = make_preset("A"), make_preset("B")
        self.manager.submit(a)
        self.manager.activate()
        self.manager.submit(b)

        for status in Status:
            if status == Status.DRAFT:
                continue
            with self.subTest(status=status):
                candidate = make_preset("C")
                candidate.status = status
                with self.assertRaisesRegex(ValueError, "Only draft"):
                    self.manager.submit(candidate)
                self.assertEqual(candidate.status, status)
                self.assertIs(self.manager.active, a)
                self.assertIs(self.manager.pending, b)
                self.assertEqual(a.status, Status.ACTIVE)
                self.assertEqual(b.status, Status.PENDING)

    def test_resubmitting_same_pending_object_does_not_supersede_it(self):
        candidate = make_preset()
        self.manager.submit(candidate)
        with self.assertRaises(ValueError):
            self.manager.submit(candidate)
        self.assertIs(self.manager.pending, candidate)
        self.assertEqual(candidate.status, Status.PENDING)

    def test_validation_accepts_finite_gain_including_boundaries(self):
        # +/-12 dB are the current model's example limits.
        for gain in (-12, -0.5, 0, 0.5, 12):
            for bypass in (False, True):
                with self.subTest(gain=gain, bypass=bypass):
                    config = PresetConfig(bypass, gain)
                    self.assertTrue(self.manager.validate_config(config, -12, 12))

    def test_invalid_values_are_rejected_by_validation_and_submit(self):
        invalid_configs = [
            PresetConfig(False, gain)
            for gain in (-12.01, 12.01, float("nan"), float("inf"),
                         float("-inf"), True, False, "0", None, 10**1000, -(10**1000))
        ]
        invalid_configs.extend(PresetConfig(bypass, 0) for bypass in (0, 1, "False", None))

        for config in invalid_configs:
            with self.subTest(config=config):
                self.assertFalse(self.manager.validate_config(config, -12, 12))
                candidate = Preset("invalid", config)
                self.manager.submit(candidate)
                self.assertEqual(candidate.status, Status.REJECTED)
                self.assertIsNone(self.manager.active)
                self.assertIsNone(self.manager.pending)

    def test_missing_or_wrong_config_is_rejected_without_losing_pending(self):
        pending = make_preset("B")
        self.manager.submit(pending)
        for config in (None, {}, "invalid"):
            with self.subTest(config=config):
                candidate = Preset("C", config)
                self.manager.submit(candidate)
                self.assertEqual(candidate.status, Status.REJECTED)
                self.assertTrue(candidate.rejection_reason)
                self.assertIs(self.manager.pending, pending)
                self.assertEqual(pending.status, Status.PENDING)

    def test_valid_submission_clears_stale_rejection_reason(self):
        candidate = make_preset()
        candidate.rejection_reason = "Old draft validation error"
        self.manager.submit(candidate)
        self.assertEqual(candidate.status, Status.PENDING)
        self.assertIsNone(candidate.rejection_reason)

    def test_configuration_fields_cannot_be_edited_in_place(self):
        candidate = make_preset()
        self.manager.submit(candidate)
        with self.assertRaises(FrozenInstanceError):
            candidate.config.input_gain_db = 100
        self.assertEqual(self.manager.pending.config.input_gain_db, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
