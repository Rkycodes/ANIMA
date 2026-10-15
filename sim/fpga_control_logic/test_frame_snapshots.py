"""Behavioral tests: python3 -m unittest discover -s sim -v.

These exercise snapshot ownership, not DSP arithmetic or FPGA storage release.
"""

import unittest
from dataclasses import FrozenInstanceError

from sim.fpga_control_logic.audio_frame import FrameStage
from sim.fpga_control_logic.preset import Preset, PresetConfig, PresetStatus as Status
from sim.fpga_control_logic.preset_manager import PresetManager


def make_preset(name="A", gain=0.0):
    return Preset(name, PresetConfig(bypass=False, input_gain_db=gain))


class FrameSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.manager = PresetManager()

    def test_startup_is_pending_until_first_frame(self):
        startup = self.manager.pending
        snapshot = self.manager.pending_snapshot
        self.assertIsNone(self.manager.active)
        self.assertEqual(startup.status, Status.PENDING)
        self.assertTrue(snapshot.config.bypass)
        self.assertEqual(snapshot.config.input_gain_db, 0)
        self.assertEqual(snapshot.generation, 1)

        frame = self.manager.begin_frame("0", 0.1, -0.2)
        self.assertEqual((frame.frame_id, frame.left, frame.right), ("0", 0.1, -0.2))
        self.assertEqual(frame.stage, FrameStage.RECEIVED)
        self.assertIs(frame.snapshot, snapshot)
        self.assertIs(self.manager.active, startup)
        self.assertEqual(startup.status, Status.ACTIVE)
        self.assertIsNone(self.manager.pending)
        self.assertIsNone(self.manager.pending_snapshot)

    def test_user_preset_can_supersede_startup_before_first_frame(self):
        startup = self.manager.pending
        candidate = make_preset(gain=-3)
        self.manager.submit(candidate)
        frame = self.manager.begin_frame("0", 0, 0)
        self.assertEqual(startup.status, Status.SUPERSEDED)
        self.assertEqual(candidate.status, Status.ACTIVE)
        self.assertEqual(frame.snapshot.config.input_gain_db, -3)
        self.assertEqual(frame.snapshot.generation, 2)

    def test_replacing_candidate_config_cannot_change_accepted_settings(self):
        candidate = make_preset(gain=-3)
        self.manager.submit(candidate)
        snapshot = self.manager.pending_snapshot
        candidate.config = PresetConfig(False, 100)
        frame = self.manager.begin_frame("10", 0, 0)
        self.assertIs(frame.snapshot, snapshot)
        self.assertEqual(frame.snapshot.config.input_gain_db, -3)

        candidate.config = PresetConfig(True, 6)
        self.assertEqual(self.manager.active_snapshot.config.input_gain_db, -3)
        self.assertFalse(frame.snapshot.config.bypass)

    def test_snapshot_and_its_config_are_frozen(self):
        snapshot = self.manager.pending_snapshot
        with self.assertRaises(FrozenInstanceError):
            snapshot.config = PresetConfig(False, 6)
        with self.assertRaises(FrozenInstanceError):
            snapshot.generation = 99
        with self.assertRaises(FrozenInstanceError):
            snapshot.config.input_gain_db = 6

    def test_frame_10_retains_a_until_completion_while_frame_11_uses_b(self):
        a, b = make_preset("A", -3), make_preset("B", 2)
        self.manager.submit(a)
        frame_10 = self.manager.begin_frame("10", 0.1, 0.2)
        snapshot_a = frame_10.snapshot
        frame_10.stage = FrameStage.EQ_DONE

        self.manager.submit(b)
        self.assertEqual(a.status, Status.ACTIVE)
        frame_11 = self.manager.begin_frame("11", 0.3, 0.4)
        self.assertEqual(a.status, Status.RETIRED)
        self.assertEqual(b.status, Status.ACTIVE)
        # A later consumer of frame 10 must still read A's accepted settings.
        self.assertIs(frame_10.snapshot, snapshot_a)
        self.assertEqual(frame_10.snapshot.config.input_gain_db, -3)
        self.assertEqual(frame_10.stage, FrameStage.EQ_DONE)
        self.assertEqual(frame_11.snapshot.config.input_gain_db, 2)
        self.assertNotEqual(frame_10.snapshot.generation, frame_11.snapshot.generation)

        self.manager.end_frame(frame_10)
        self.assertEqual(frame_10.stage, FrameStage.COMPLETE)
        self.assertEqual(frame_11.stage, FrameStage.RECEIVED)
        self.assertIs(self.manager.active_snapshot, frame_11.snapshot)
        self.assertEqual(frame_10.snapshot.config.input_gain_db, -3)

    def test_frames_share_snapshot_when_no_update_is_pending(self):
        first = self.manager.begin_frame("10", 0, 0)
        next_generation = self.manager.next_generation
        second = self.manager.begin_frame("11", 0, 0)
        self.assertIs(first.snapshot, second.snapshot)
        self.assertEqual(self.manager.next_generation, next_generation)

    def test_rejection_does_not_consume_generation_or_replace_snapshot(self):
        snapshot = self.manager.pending_snapshot
        next_generation = self.manager.next_generation
        invalid = make_preset(gain=13)
        self.manager.submit(invalid)
        self.assertEqual(invalid.status, Status.REJECTED)
        self.assertEqual(self.manager.next_generation, next_generation)
        self.assertIs(self.manager.pending_snapshot, snapshot)
        with self.assertRaises(ValueError):
            self.manager.submit(invalid)
        self.assertEqual(self.manager.next_generation, next_generation)

    def test_superseded_generation_is_skipped_at_activation(self):
        first = self.manager.begin_frame("10", 0, 0)
        b, c = make_preset("B", 1), make_preset("C", 2)
        self.manager.submit(b)
        generation_b = self.manager.pending_snapshot.generation
        self.manager.submit(c)
        generation_c = self.manager.pending_snapshot.generation
        frame = self.manager.begin_frame("11", 0, 0)
        self.assertEqual(b.status, Status.SUPERSEDED)
        self.assertEqual(generation_b, first.snapshot.generation + 1)
        self.assertEqual(generation_c, generation_b + 1)
        self.assertEqual(frame.snapshot.generation, generation_c)
        self.assertEqual(frame.snapshot.config.input_gain_db, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
