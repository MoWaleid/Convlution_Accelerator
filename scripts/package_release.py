"""Package a timing-passing build for transfer to the ZedBoard; stdlib only."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    hw = json.loads((root / 'release/hardware.json').read_text())
    mhz = hw['accelerator']['clock_mhz']
    artifacts = root / f'work/release_{mhz}/artifacts'
    marker = (artifacts / 'timing_pass.txt').read_text()
    if f'MHz={mhz}\n' not in marker:
        raise RuntimeError('Release clock/timing marker mismatch')
    timing = (artifacts / 'timing.rpt').read_text()
    if 'All user specified timing constraints are met.' not in timing:
        raise RuntimeError('Timing did not pass')
    rtl = root / 'Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd'
    match = re.search(r'CFG_BUILD_ID.*?x"([0-9A-Fa-f]+)"', rtl.read_text(), re.S)
    if not match or match[1].lower() != hw['accelerator']['build_id_hex']:
        raise RuntimeError('RTL/software build ID mismatch')
    # Refuse to attach passing reports to source changed after the fresh import.
    imported = artifacts.parent / 'project/edgefree.srcs/sources_1'
    names = ('config_pkg conv_pkg sync_fifo coeff_bias_shift_regfile axi_lite_ctrl '
             'window_generator cfglut5_kcm cfglut5_bitheap_3x3 conv_channel conv_engine '
             'conv_top axi_stream_input_frontend axi_stream_output_serializer conv_axis_wrapper').split()
    source_hashes = {}
    for name in [n + '.vhd' for n in names] + ['conv_axis_wrapper_bd.v']:
        candidates = list(imported.rglob(name))
        source = rtl.parent / name
        if len(candidates) != 1 or sha(candidates[0]) != sha(source):
            raise RuntimeError(f'Build/source mismatch: {name}; rebuild before packaging')
        source_hashes[name] = sha(source)
    args.out.mkdir(parents=True, exist_ok=False)
    shutil.copytree(artifacts, args.out / 'artifacts', ignore=shutil.ignore_patterns('*.dcp'))
    (args.out / 'software').mkdir()
    for name in ('edgefree_board.py', 'm7_switch.py', 'm4_filebackend.py'):
        shutil.copy2(root / 'software' / name, args.out / 'software' / name)
    shutil.copytree(root / 'software/conv_lab', args.out / 'software/conv_lab',
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copytree(root / 'golden_model/data/weights_k16', args.out / 'params/B32')
    shutil.copy2(root / 'release/QUICKSTART.md', args.out / 'QUICKSTART.md')
    hw['artifacts'] = {
        'bitstream_file': 'artifacts/edgefree.bit',
        'bitstream_sha256': sha(artifacts / 'edgefree.bit'),
        'xsa_file': 'artifacts/edgefree.xsa',
        'xsa_sha256': sha(artifacts / 'edgefree.xsa'),
    }
    (args.out / 'hardware.json').write_text(json.dumps(hw, indent=2) + '\n')
    (args.out / 'rtl_sha256.json').write_text(json.dumps(source_hashes, indent=2) + '\n')
    # Deterministic grayscale ramp/checker input: no private dataset dependency.
    (args.out / 'input_u8.bin').write_bytes(bytes((17*x + 29*y + (x*y)%71) & 255
                                                 for y in range(32) for x in range(32)))
    entries = []
    for path in sorted(args.out.rglob('*')):
        if path.is_file():
            entries.append(f'{sha(path)}  {path.relative_to(args.out).as_posix()}')
    (args.out / 'SHA256SUMS.txt').write_text('\n'.join(entries) + '\n', encoding='ascii')
    print(f'PACKAGE_COMPLETE {args.out.resolve()} (board validation NOT_RUN)')


if __name__ == '__main__':
    main()
