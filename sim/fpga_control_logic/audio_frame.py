from dataclasses import dataclass
from enum import Enum, auto
from sim.fpga_control_logic.preset import PresetSnapshot


class FrameStage(Enum):
    RECEIVED = auto()
    EQ_DONE = auto()
    COMPLETE = auto()

@dataclass
class AudioFrame:
    frame_id: str
    left: float
    right: float
    snapshot: PresetSnapshot
    stage: FrameStage = FrameStage.RECEIVED

