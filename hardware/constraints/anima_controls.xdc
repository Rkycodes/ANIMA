# Control/reference pin fragment for anima_bypass_control_shell integration.
# Pin facts: docs/planning.md SRC-008 (D.1) and supplementary SRC-014 (rev B).
# Authored fragment, not a copied vendor XDC. Not a complete board constraint set.
set_property PACKAGE_PIN W5 [get_ports ref_clk]
set_property IOSTANDARD LVCMOS33 [get_ports ref_clk]
create_clock -name ref_100mhz -period 10.000 [get_ports ref_clk]
set_property PACKAGE_PIN U18 [get_ports button_center]
set_property PACKAGE_PIN U17 [get_ports button_down]
set_property PACKAGE_PIN U16 [get_ports led0]
set_property IOSTANDARD LVCMOS33 [get_ports {button_center button_down led0}]
# audio_clk/LOCKED/MMCM reset are INTERNAL connections in the eventual board top.
# No audio-pin/output-delay, generated-clock, CDC or routing acceptance is implied.
