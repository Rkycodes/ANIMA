# ANIMA

**Artix Networked I2S Multiband Audio Processor** — Robel Yaee and An Tiet.

A planned Basys 3 / Pmod I2S2 stereo audio processor with ESP32 wireless controls. Nominal 48 kHz, signed 24-bit samples, two 32-bit I2S slots. Wi-Fi carries controls only.

**Current status:** Python preset/frame behavioral model, repository checks and [serial-timing](docs/implemented.md#serial-timing-component), [warm-reset controller](docs/implemented.md#warm-reset-controller), [I2S receiver](docs/implemented.md#i2s-receiver), [RX frame queue](docs/implemented.md#rx-frame-queue), [frame scheduler](docs/implemented.md#frame-scheduler) and [I2S transmitter](docs/implemented.md#i2s-transmitter) RTL components with passing simulation checks. Short component-chain simulation only; no accepted bypass build, firmware, synthesis target, routed timing or hardware audio validation. First audio milestone: stereo bypass without DSP. Basys 3 D.1 is on hand; the intended Pmod has not yet been purchased.

## Read the project

| Document | What belongs there |
| --- | --- |
| [Planning & Design](docs/planning.md) | Contracts, hardware, clocks, DSP/control proposals, acceptance requirements, ownership, open decisions and sources |
| [Implemented & Verified](docs/implemented.md) | Current code, checks actually run, tool evidence, reproducible commands and limitations |

The [source register](docs/planning.md#source-register) retains stable source IDs. Selected requirements are distinct from proposals and verified behavior.

## Planned system

This describes the planned final system, not implemented audio. Solid arrows carry audio; dashed arrows carry controls or observations. The first milestone implements only RX → coherent stereo frames → TX.

```mermaid
flowchart LR
  subgraph AUDIO["Planned audio path"]
    SRC["Stereo line source"] --> ADC["Pmod I2S2 ADC"]
    ADC --> RX["I2S receiver"] --> INFRAME["Stereo frame handoff"]
    INFRAME --> ING["Input gain"] --> EQ["Five-band EQ per channel"]
    EQ --> COMP["Stereo-linked compressor"] --> OUTG["Output gain / saturation"]
    OUTG --> OUTFRAME["Stereo frame handoff"] --> TX["I2S transmitter"]
    TX --> DAC["Pmod I2S2 DAC"] --> SPK["Powered speakers / amplifier"]
  end
  subgraph CONTROL["Planned control path"]
    WIFI["Wireless controls / web UI"] -.-> ESP["ESP32"]
    ESP -.-> UART["FPGA UART / parser"] -.-> SHADOW["Shadow parameters"]
    SHADOW -.-> ACT["Atomic parameter activation at frame boundary"]
  end
  subgraph OBS["Planned observations / display"]
    TEL["Nonblocking coherent telemetry"] -.-> VGA["VGA meters"]
  end
  ACT -.-> ING
  ACT -.-> EQ
  ACT -.-> COMP
  ACT -.-> OUTG
  OUTFRAME -.-> TEL
  COMP -.-> TEL
  ACT -.-> TEL
  TEL -.-> UART
  UART -.-> ESP
```

## Run current checks

With Python 3.12, from the repository root:

```sh
python scripts/check_repo.py
python -B -m unittest discover -s sim/fpga_control_logic -v
```

These check repository integrity and the Python behavioral model, not audio, FPGA timing or hardware. See [reproduction and evidence](docs/implemented.md#reproduce-current-checks).
