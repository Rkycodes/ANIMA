from __future__ import annotations

import math

from dataclasses import dataclass
from preset import Preset, PresetConfig
from preset import PresetStatus as Status


@dataclass
class PresetManager:
    active: Preset | None = None
    pending: Preset | None = None

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

        # if the pending slot in the manager is occupied
        # supersede the current pending preset
        if self.pending is not None:
            self.pending.status = Status.SUPERSEDED

        # update the current pending slot
        candidate.status = Status.PENDING
        candidate.rejection_reason = None
        self.pending = candidate


    # Activate pending preset
    def activate(self):
        if self.pending is None:
            return

        if self.active is not None:
            self.active.status = Status.RETIRED     # Retire current 'active' preset

        self.active = self.pending                     # Also works for the first activation
        self.active.status = Status.ACTIVE
        self.pending = None

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
