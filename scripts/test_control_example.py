#!/usr/bin/env python3
"""Generate independent CRC vectors with Python and run the control reference."""
from pathlib import Path
import binascii
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def packet(opcode, sequence, payload=b"", version=1):
    body = bytes((version, opcode, sequence, len(payload))) + payload
    crc = binascii.crc_hqx(body, 0xFFFF)
    encoded = bytearray((0x55,))
    for value in body + crc.to_bytes(2, "big"):
        encoded.extend((0x7D, value ^ 0x20) if value in (0x55, 0x7D) else (value,))
    return bytes(encoded + b"\x55")


def stimuli():
    lines = []

    def statement(text):
        lines.append(text)

    def send(data, wait=True):
        lines.extend(f"send_byte(8'h{value:02x});" for value in data)
        statement("stop_bytes();")
        if wait:
            statement("settle();")

    # Fixed vectors prevent the reference encoder drifting unnoticed.
    assert binascii.crc_hqx(b"123456789", 0xFFFF) == 0x29B1
    assert packet(0x11, 3).hex() == "5501110300d37455"
    statement("reset_dut(); test_fifo();")
    send(packet(0x11, 1))
    statement("expect_reply(1, 1, 5, 0);")  # No valid shadow.
    send(packet(0x10, 2, b"\x00\x00\x01"))  # bypass off, +1 dB
    statement("expect_reply(2, 2, 0, 0); expect_active(1, 0, 0);")
    send(packet(0x11, 3))
    statement("expect_reply(3, 3, 1, 1); expect_active(1, 0, 0);")
    # Change shadow while pending; pending snapshot must remain immutable.
    send(packet(0x10, 4, b"\x01\x00\xff"))  # bypass on, -1 dB
    statement("activate(); expect_active(0, 256, 1);")
    statement("if (applied_sequence != 3) $fatal(1, \"applied identity\");")
    send(packet(0x11, 5))
    statement("expect_reply(5, 5, 1, 2);")
    send(packet(0x11, 5))  # Retry must not allocate generation 3.
    statement("expect_reply(6, 5, 1, 2);")
    send(packet(0x01, 5))
    statement("expect_reply(7, 5, 6, 0);")
    statement("activate(); expect_active(1, -256, 2);")
    send(packet(0x10, 6, b"\x00\x00\x0d"))  # +13 dB invalid
    statement("expect_reply(8, 6, 4, 0);")
    send(packet(0x11, 7))
    statement("activate(); expect_active(1, -256, 3);")
    # Corruption, lengths, escaping, and semantic rejection.
    statement("reset_dut();")
    send(bytes.fromhex("55 01 11 03 00 D3 75 55"))
    statement("if (replies != 0 || errors == 0) $fatal(1, \"bad CRC accepted\");")
    send(packet(0x10, 1, bytes(17)))
    statement("if (replies != 0) $fatal(1, \"oversize accepted\");")
    send(bytes.fromhex("55 7D 00 55"))
    statement("if (replies != 0) $fatal(1, \"invalid escape accepted\");")
    send(packet(0x01, 0x55) + packet(0x01, 0x7D))
    statement("expect_reply(2, 8'h7d, 0, 0);")
    send(packet(0x10, 8, b"\x00"))
    statement("expect_reply(3, 8, 3, 0);")
    send(packet(0x77, 9))
    statement("expect_reply(4, 9, 2, 0);")
    send(packet(0x01, 10, version=2))
    statement("expect_reply(5, 10, 7, 0);")
    # A timed-out prefix at every wire-byte position, including an escape.
    candidate = packet(0x10, 0x55, b"\x00\x55\x00")
    for cut in range(1, len(candidate)):
        statement("reset_dut();")
        send(candidate[:cut], wait=False)
        statement("repeat (80) @(negedge clk); #1;")
        statement("if (replies != 0 || pending_valid) $fatal(1, \"truncation executed\");")
        send(packet(0x01, 0x44))
        statement("expect_reply(1, 8'h44, 0, 0);")
    # Consecutive closing/opening delimiters must recover without a timeout.
    statement("reset_dut();")
    send(candidate[:-3] + packet(0x01, 0x44))
    statement("expect_reply(1, 8'h44, 0, 0);")
    # Pre-existing B activates on the edge that publishes C.
    statement("reset_dut();")
    send(packet(0x10, 1, b"\x00\x00\x01"))
    send(packet(0x11, 2))
    send(packet(0x10, 3, b"\x01\x00\xff"))
    send(packet(0x11, 4), wait=False)
    statement("wait (dut.commit); activate(); settle();")
    statement("expect_active(0, 256, 1);")
    statement("if (!pending_valid || applied_sequence != 2) $fatal(1, \"tie ordering\");")
    statement("activate(); expect_active(1, -256, 2);")
    # With no old pending snapshot, a same-edge commit cannot activate early.
    statement("reset_dut();")
    send(packet(0x10, 1, b"\x00\x00\x01"))
    send(packet(0x11, 2), wait=False)
    statement("wait (dut.commit); activate(); settle(); expect_active(1, 0, 0);")
    statement("if (!pending_valid || applications != 0) $fatal(1, \"early activation\");")
    statement("activate(); expect_active(0, 256, 1);")
    # An invalid candidate must not disturb an existing pending configuration.
    statement("reset_dut();")
    send(packet(0x10, 1, b"\x00\x00\x01"))
    send(packet(0x11, 2))
    send(packet(0x10, 3, b"\x02\x00\x00"))
    statement("expect_reply(3, 3, 4, 0); activate(); expect_active(0, 256, 1);")
    # Latest pending wins before activation; older generation never applies.
    statement("reset_dut();")
    send(packet(0x10, 1, b"\x00\x00\x01"))
    send(packet(0x11, 2))
    send(packet(0x10, 3, b"\x01\x00\xff"))
    send(packet(0x11, 4))
    statement("activate(); expect_active(1, -256, 2);")
    statement("if (applications != 1 || applied_sequence != 4) $fatal(1, \"superseded applied\");")
    # Abort unfinished assembly, then recover.
    statement("reset_dut();")
    send(candidate[:5], wait=False)
    statement("@(negedge clk); rx_error = 1; @(negedge clk); rx_error = 0;")
    send(packet(0x01, 9))
    statement("expect_reply(1, 9, 0, 0);")
    # Deliberately exceed the consumer rate with continuous byte-level traffic.
    # This is much faster than the real UART, and forces FIFO overflow.
    statement("reset_dut();")
    send(packet(0x01, 1) * 200)
    statement("if (overflows == 0) $fatal(1, \"overflow not exercised\");")
    statement("repeat (80) @(negedge clk); #1; baseline = replies;")
    send(packet(0x01, 9))
    statement("expect_reply(baseline+1, 9, 0, 0);")
    # Reset must discard both pending state and duplicate history.
    send(packet(0x10, 10, b"\x00\x00\x01"))
    send(packet(0x11, 11))
    statement("reset_dut();")
    statement("activate(); expect_active(1, 0, 0);")
    send(packet(0x11, 11))
    statement("expect_reply(1, 11, 5, 0);")
    return "\n".join(lines) + "\n"


def main():
    with tempfile.TemporaryDirectory(prefix="anima-control-") as directory:
        build = Path(directory)
        (build / "control_stimulus.vh").write_text(stimuli(), encoding="utf-8")
        executable = build / "control_sim"
        subprocess.run([
            "iverilog", "-g2001", "-Wall", "-s", "anima_control_example",
            "-o", str(build / "rtl_elaboration"),
            str(ROOT / "rtl/control/anima_control_example.v"),
        ], check=True, cwd=ROOT)
        subprocess.run([
            "iverilog", "-g2012", "-Wall", "-I", str(build),
            "-s", "tb_anima_control_example", "-o", str(executable),
            str(ROOT / "rtl/control/anima_control_example.v"),
            str(ROOT / "sim/control/tb_anima_control_example.sv"),
        ], check=True, cwd=ROOT)
        subprocess.run(["vvp", str(executable)], check=True, cwd=ROOT, timeout=30)


if __name__ == "__main__":
    main()
