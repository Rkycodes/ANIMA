from __future__ import annotations

import math
from dataclasses import dataclass, field

# custom imports
from preset import Preset, PresetConfig, PresetSnapshot
from preset import PresetStatus as Status
from audio_frame import AudioFrame, FrameStage


@dataclass
class PresetManager:
    active: Preset | None = None
    pending: Preset | None = None

    active_snapshot: PresetSnapshot | None = None
    pending_snapshot: PresetSnapshot | None = None

    next_generation: int = field(default=1, init=False)

    def __post_init__(self):
        default = Preset(preset_id = 'startup', 
                         config = PresetConfig(
                            bypass = True,
                            input_gain_db = 0
                        ), 
                    )
        self.submit(default)

    def submit(self, candidate: Preset):
        if candidate.status != Status.DRAFT:
            raise ValueError("Only draft presets can be submitted")

        # invalid configs are rejected and function returns
        # Example model limits; these are not yet the agreed DSP limits.
        if not self.validate_config(candidate.config, -12, 12):
            candidate.status = Status.REJECTED
            candidate.rejection_reason = (
                "Expected PresetConfig with Boolean bypass and finite numeric "
                "input_gain_db between -12 and 12 (example model limits)"
            )
            return

        # take a snapshot of the candidate preset
        # prevents invalid configs from potentially activating if candidate.config is modified after validation
        candidate_snapshot = PresetSnapshot(
            generation = self.next_generation,
            config = PresetConfig(
                bypass = candidate.config.bypass,
                input_gain_db = candidate.config.input_gain_db
            )
        )
        self.next_generation += 1

        # if the pending slot in the manager is occupied
        # supersede the current pending preset
        if self.pending is not None:
            self.pending.status = Status.SUPERSEDED

        # update the current pending slot
        candidate.status = Status.PENDING
        candidate.rejection_reason = None

        # store the snapshot to prevent activations of invalid configs
        self.pending = candidate
        self.pending_snapshot = candidate_snapshot


    # Activate pending preset
    def activate(self):
        if self.pending is None:
            return

        if self.active is not None:
            self.active.status = Status.RETIRED     # Retire current 'active' preset

        self.active = self.pending                     # Also works for the first activation
        self.active_snapshot = self.pending_snapshot

        self.active.status = Status.ACTIVE

        # clear pending slots
        self.pending = None
        self.pending_snapshot = None

    def validate_config(self, config: PresetConfig, min_gain_db: float, max_gain_db: float) -> bool:
        if not isinstance(config, PresetConfig):
            return False

        if not isinstance(config.bypass, bool):
            return False

        gain = config.input_gain_db

        # Python treats bool as a subclass of int, so reject it explicitally
        if isinstance(gain, bool) or not isinstance(gain, (int, float)):
            return False

        # Integers are finite; converting a huge integer to float can overflow.
        if isinstance(gain, float) and not math.isfinite(gain):
            return False

        return min_gain_db <= gain <= max_gain_db

    # activates the pending snapshot, if one exists, give the frame a reference to the active snapshot
    def begin_frame(self, frame_id: str, left: float, right: float) -> AudioFrame:
        self.activate()

        if self.active is None:
            raise RuntimeError("No preset has been activated")

        return AudioFrame(frame_id = frame_id, left = left, right = right, snapshot = self.active_snapshot)
    


    def end_frame(frame: AudioFrame):
        frame.stage = FrameStage.COMPLETE
