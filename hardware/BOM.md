# Materials

| Item | Quantity | Purpose / status |
| --- | --- | --- |
| Digilent Basys 3 | 1 | FPGA board received October 14, 2026, reported by Robel on October 15; physical revision D.1 previously reported by Robel on 2026-10-08. Manufacturer schematic is explicitly D.1 (SRC-008). Supplied PDF manual applies to rev. C (SRC-001); its applicability to D.1 remains to be verified |
| Digilent Pmod I2S2 (410-379), intended board | 1 | Not yet purchased, reconfirmed by Robel on 2026-10-15; JA reserved for the intended module. [Proposed Amazon listing, ASIN B0CLLXNPTG](https://www.amazon.com/dp/B0CLLXNPTG); listing identity and compatibility unverified because page retrieval failed. Confirm manufacturer/model, ADC/DAC parts, connector pinout and revision before purchase |
| ESP32 DevKit V1 | 1 | Board designation reported by Robel on 2026-10-08; ESP32-WROOM-32 module confirmed by Robel on 2026-10-08, resolving the module-identification deferral. Dev-board manufacturer/revision, pin count, USB-serial chip and firmware framework/version remain unconfirmed; verify exact board wiring before UART pin allocation or electrical integration. Supplied pinout guides are supplementary references (SRC-010/SRC-011), not a verified schematic for this board |
| Stereo 3.5 mm TRS male-to-male cable | 2 | One stereo input cable and one stereo output cable |
| Line-level stereo source | 1 | Computer, player, or phone with suitable audio output/dongle |
| Powered speakers or amplifier with line input | 1 | The codec output should feed a suitable line input |
| Basys 3 USB programming/power cable | 1 | Match board connector |
| ESP32 USB data/power cable | 1 | Match chosen board connector |
| 3.3 V-compatible jumper wires / Pmod extension as needed | Set | UART and codec connections; check connector layout |
| Development computer | 1 per person preferred | Vivado, simulator, Python, ESP32 tools |

Useful lab equipment: multimeter, logic analyzer with adequate sample rate for I2S, oscilloscope, and an audio interface for measurement. These improve diagnosis and evidence but are not prerequisites for the first demo.

Each TRS cable carries both left and right channels. Two cables are needed because input and output are separate connections.
