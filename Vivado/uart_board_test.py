"""Using a fake serial link; no pySerial or hardware required."""

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "uart_board_test.py"
SPEC = importlib.util.spec_from_file_location("uart_board_test", SCRIPT)
tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tool)


class FakePort:
    def __init__(self, greeting=b"USI\n", chunk_size=2):
        self.pending = bytearray(greeting)
        self.timeout = 0.1
        self.chunk_size = chunk_size
        self.now = 0.0
        self.writes = []
        self.corrupt_echo = False
        self.extra_echo = False
        self.short_write = False
        self.fail_write = False

    def read(self, count):
        if not self.pending:
            self.now += self.timeout
            return b""
        take = min(count, self.chunk_size, len(self.pending))
        result = bytes(self.pending[:take])
        del self.pending[:take]
        return result

    def write(self, payload):
        if self.fail_write:
            raise OSError("serial link disconnected")
        self.writes.append(payload)
        if self.short_write:
            return 2
        self.pending.extend(bytes(value ^ 1 for value in payload) if self.corrupt_echo else payload)
        if self.extra_echo:
            self.pending.extend(b"\0")
        return len(payload)


class BoardToolTests(unittest.TestCase):
    def run_link(self, port, **kwargs):
        with patch.object(tool, "monotonic", side_effect=lambda: port.now):
            return tool.exercise(port, **kwargs)

    def test_short_reads_and_full_binary_range_in_order(self):
        port = FakePort(chunk_size=1)
        self.assertEqual(self.run_link(port, blocks=128), 512)
        self.assertEqual(port.writes[0], b"\x00\x55\xaa\xff")
        self.assertEqual(port.writes, [tool.block_pattern(index) for index in range(128)])
        self.assertEqual(set(b"".join(port.writes)), set(range(256)))
        self.assertFalse(port.pending)

    def test_deadline_covers_all_short_reads(self):
        port = FakePort(greeting=b"US", chunk_size=1)
        with self.assertRaisesRegex(TimeoutError, "received 2/4 bytes"):
            self.run_link(port, blocks=1, reset_timeout=0.25)
        self.assertAlmostEqual(port.now, 0.25)
        self.assertEqual(port.writes, [])

    def test_wrong_greeting_rejected_before_writes(self):
        port = FakePort(greeting=b"BAD\n")
        with self.assertRaisesRegex(RuntimeError, "reset greeting"):
            self.run_link(port, blocks=1)
        self.assertEqual(port.writes, [])

    def test_wrong_echo_is_rejected(self):
        port = FakePort()
        port.corrupt_echo = True
        with self.assertRaisesRegex(RuntimeError, "echo block 0"):
            self.run_link(port, blocks=2)
        self.assertEqual(len(port.writes), 1)

    def test_missing_echo_times_out(self):
        port = FakePort()
        port.write = lambda payload: len(payload)
        with self.assertRaisesRegex(TimeoutError, "received 0/4 bytes"):
            self.run_link(port, blocks=1, timeout=0.2)

    def test_unexpected_greeting_tail_is_rejected(self):
        port = FakePort(greeting=b"USI\nUSI\n")
        with self.assertRaisesRegex(RuntimeError, "unexpected extra UART data"):
            self.run_link(port, blocks=1)
        self.assertEqual(port.writes, [])

    def test_extra_echo_is_rejected_after_last_block(self):
        port = FakePort()
        port.extra_echo = True
        with self.assertRaisesRegex(RuntimeError, "unexpected extra UART data"):
            self.run_link(port, blocks=1)

    def test_short_write_and_disconnected_link_fail(self):
        port = FakePort()
        port.short_write = True
        with self.assertRaisesRegex(RuntimeError, "serial write accepted 2/4"):
            self.run_link(port, blocks=1)
        port = FakePort()
        port.fail_write = True
        with self.assertRaisesRegex(OSError, "disconnected"):
            self.run_link(port, blocks=1)

    def test_argument_timeouts_must_be_finite_and_positive(self):
        for value in ["0", "-1", "nan", "inf"]:
            with self.subTest(value=value), self.assertRaises(tool.argparse.ArgumentTypeError):
                tool.positive_seconds(value)


if __name__ == "__main__":
    unittest.main()