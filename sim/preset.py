from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto

class PresetStatus(Enum):
    DRAFT = auto()           # Configuration is being assembled/edited
    PENDING = auto()         # Configuration is complete and valid, waiting for activation
    ACTIVE = auto()          # Configuration is active
    SUPERSEDED = auto()      # Configuration replaced by newer, pending preset before it was activated
    REJECTED = auto()        # Submitted configuration failed validation
    RETIRED = auto()         # Previously active; replaced by another active preset

# Preset lifecycle:
# DRAFT   -> PENDING:    Submitted and valid.
# DRAFT   -> REJECTED:   Submitted and invalid; active/pending presets unchanged.
# PENDING -> ACTIVE:     Selected at the agreed activation boundary.
# PENDING -> SUPERSEDED: Replaced by a newer valid preset before activation.
# ACTIVE  -> RETIRED:    Another preset actually activates.
#
# A new submission alone does not retire the active preset.
# Retired presets may still be needed by in-flight audio frames.


@dataclass(frozen=True)
class PresetConfig:
    bypass: bool
    input_gain_db: float

@dataclass
class Preset:
    preset_id: str
    config: PresetConfig
    status: PresetStatus = PresetStatus.DRAFT
    rejection_reason: str | None = None

