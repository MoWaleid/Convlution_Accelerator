import tempfile
import unittest
from fractions import Fraction

from conv_lab.admission import RecordingMockBackend,reference_only
from conv_lab.errors import AdmissionError
from conv_lab.strict import sha256
from .fixtures import FixtureDecoder,selection_session,write_selection
from .oracle import oracle


class CanonicalIntegration(unittest.TestCase):
    def test_one_decode_same_bytes_reference_and_mock_tx(self):
        with tempfile.TemporaryDirectory(prefix="m2-integration-") as root:
            roots,pixels = write_selection(root)
            decoder = FixtureDecoder(pixels)
            session = selection_session(roots,pixels,decoder=decoder)
            backend = RecordingMockBackend()
            ctx = session.admit(*roots,"sample")
            result = reference_only(ctx)
            self.assertEqual(backend.events,())
            self.assertEqual(decoder.calls,1)
            self.assertEqual(result.raw,oracle(3,2,3,ctx.channels,pixels))
            self.assertEqual(result.canonical_sha256,ctx.canonical_sha256)
            session.submit(ctx,backend)
            tx = next(e for e in backend.events if e[0] == "dma_tx")
            self.assertEqual(tx[4],ctx.canonical_sha256)
            self.assertEqual(tx[3],ctx.padded_tx)
            self.assertEqual(sha256(tx[3]),ctx.padded_tx_sha256)
            # Independent, hand-sized reconstruction; not the implementation packer.
            self.assertEqual(tx[3],b"\0"*5+b"\0"+pixels[:3]+b"\0"+b"\0"+pixels[3:]+b"\0"+b"\0"*5)
            self.assertEqual(decoder.calls,1)
            self.assertEqual(ctx.input_scale,Fraction(1,256))
            session.invalidate()
            before = backend.events
            with self.assertRaises(AdmissionError):
                session.submit(ctx,backend)
            self.assertEqual(backend.events,before)
