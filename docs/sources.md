# Sources

Manufacturer references for [architecture](architecture.md). Stable IDs retain its citations; locators identify clock/format decisions. Verify physical board and installed tool revisions before implementation.

| ID | Source | ANIMA use / decision locator |
| --- | --- | --- |
| SRC-001 | [Basys 3 Reference Manual - Digilent](https://digilent.com/reference/_media/basys3:basys3_rm.pdf) | Rev. C, April 8, 2016; section 4, p. 6: 100 MHz reference and clock resources |
| SRC-002 | [Pmod I2S2 schematic - Digilent](https://digilent.com/reference/_media/reference/pmod/pmodi2s2/pmodi2s2_sch.pdf) | A.0, January 16, 2018; sheet 1, J1/JP1/IC1-IC3: codec clock nets and ADC mode selection |
| SRC-003 | [Pmod I2S2 Reference Manual - Digilent](https://digilent.com/reference/pmod/pmodi2s2/reference-manual) | Board operation/jumper cross-check; previous access returned HTTP 403, so not used as evidence |
| SRC-004 | [CS5343/4 datasheet - Cirrus Logic](https://statics.cirrus.com/pubs/proDatasheet/CS5343-44_F5.pdf) | DS687F5, March 2015, marked Draft: timing pp. 9-10; sections 4.1-4.2 / Tables 1-5 / Figure 4, pp. 12-14: ADC ratios, mode and I2S. Confirm applicable released revision |
| SRC-005 | [CS4344/5/8 datasheet - Cirrus Logic](https://statics.cirrus.com/pubs/proDatasheet/CS4344-45-48_F2.pdf) | DS613F2, July 2013: timing p. 9; sections 4.1-4.2 / Table 1 p. 12; Figure 7 p. 13; sections 4.4-4.5 / Figure 11 pp. 15-16: DAC ratios, external SCLK and startup |
| SRC-006 | [7 Series Clocking Resources - AMD/Xilinx](https://docs.amd.com/v/u/en-US/ug472_7Series_Clocking) ([PDF](https://docs.amd.com/api/khub/documents/1kFbRqzm2fhwGy~cLQG2yA/content)) | UG472 v1.14: primitive ports pp. 70-71; LOCKED p. 83; Clocking Wizard p. 102 |
| SRC-007 | [Clocking Wizard: Configuring Output Clocks - AMD](https://docs.amd.com/r/en-US/pg065-clk-wiz/Configuring-Output-Clocks) | PG065 v6.0, April 20, 2022; named HTML section: requested/actual frequency and fractional-divider restrictions |

No external code is reused. Any future reuse must record its original immutable commit/release, reused paths, license/SPDX and license URL; documentation references do not grant code licenses.
