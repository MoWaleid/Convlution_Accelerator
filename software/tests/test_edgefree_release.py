"""Host checks for the release package/runner. No MMIO or board access."""
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'software'))
import edgefree_board as board


class ReleaseChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name)
        shutil.copy2(ROOT / 'release/hardware.json', self.package / 'hardware.json')
        shutil.copytree(ROOT / 'golden_model/data/weights_k16', self.package / 'params/B32')
        (self.package / 'input_u8.bin').write_bytes(bytes(range(256))*4)
        self.hashes()

    def hashes(self):
        entries = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(self.package).as_posix()}'
                   for p in sorted(self.package.rglob('*')) if p.is_file() and p.name != 'SHA256SUMS.txt']
        (self.package / 'SHA256SUMS.txt').write_text('\n'.join(entries))

    def test_valid_package_and_reference(self):
        _, channels, padded, expected = board.verify_package(self.package)
        self.assertEqual((len(channels), len(padded), len(expected)), (16, 1156, 16384))
        # Independent dot-product and floor/remainder rounding for edge/center positions.
        for row, col, ch in ((0, 0, 0), (31, 31, 15), (12, 17, 9)):
            weights, bias, shift, relu = channels[ch]
            total = bias + sum(padded[(row + k//3)*34 + col + k%3]*weights[k] for k in range(9))
            quotient, remainder = divmod(total, 1 << shift)
            value = quotient + (1 if shift and remainder >= (1 << (shift-1)) else 0)
            value = min(32767, max(-32768, value))
            if relu:
                value = max(0, value)
            self.assertEqual(expected[(row*32+col)*16+ch], value)

    def test_tampered_input_rejected(self):
        (self.package / 'input_u8.bin').write_bytes(b'x'*1024)
        with self.assertRaisesRegex(RuntimeError, 'hash mismatch'):
            board.verify_package(self.package)

    def test_wrong_geometry_rejected(self):
        path = self.package / 'hardware.json'
        obj = json.loads(path.read_text())
        obj['accelerator']['channels_k'] = 8
        path.write_text(json.dumps(obj))
        self.hashes()
        with self.assertRaisesRegex(RuntimeError, 'geometry'):
            board.verify_package(self.package)

    def test_missing_clock_confirmation_never_opens_devices(self):
        with patch.object(sys, 'argv', ['edgefree_board.py', '--package', str(self.package)]), \
             patch.object(board.platform, 'machine', return_value='armv7l'), \
             patch.object(board.driver, 'open_handles') as opened:
            with self.assertRaisesRegex(RuntimeError, 'FCLK0'):
                board.main()
            opened.assert_not_called()

    def test_host_check_never_opens_devices(self):
        with patch.object(sys, 'argv', ['edgefree_board.py', '--package', str(self.package), '--check-only']), \
             patch.object(board.driver, 'open_handles') as opened:
            board.main()
            opened.assert_not_called()


if __name__ == '__main__':
    unittest.main()
