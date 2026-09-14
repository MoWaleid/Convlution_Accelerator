"""Generate exact signed CFGLUT5 Dadda compressors for 3x3 and 5x5.

The generated VHDL is structural and deterministic.  It compresses only
occupied bit columns, uses one LUT6_2 per 3:2 or 2:2 compressor, and inserts
pipeline boundaries so no generated reduction section exceeds three Dadda
levels.  The 3x3 renderer intentionally preserves the byte-for-byte output
of the original fixed generator.
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path


FULL_ADDER_INIT = "E8E8E8E896969696"
HALF_ADDER_INIT = "8888888866666666"
RTL_DIR = (
    Path(__file__).resolve().parents[1]
    / "Convlution_Accelerator.srcs"
    / "sources_1"
    / "new"
)


@dataclass(frozen=True)
class Geometry:
    n: int
    taps: int
    width: int
    targets: tuple[int, ...]
    register_stages: tuple[int, ...]

    @property
    def entity(self) -> str:
        return f"cfglut5_bitheap_{self.n}x{self.n}"

    @property
    def output(self) -> Path:
        return RTL_DIR / f"{self.entity}.vhd"


def dadda_targets(rows: int) -> tuple[int, ...]:
    """Return the standard descending Dadda target-height sequence."""
    heights = [2]
    while heights[-1] < rows:
        heights.append((3 * heights[-1]) // 2)
    return tuple(reversed(heights[:-1]))


def geometry(n: int) -> Geometry:
    if n not in (3, 5):
        raise ValueError("supported CFGLUT5 kernels are 3 and 5")
    taps = n * n
    width = 17 + math.ceil(math.log2(taps))
    targets = dadda_targets(2 * taps)
    register_stages = (3,) if n == 3 else (3, 6)
    return Geometry(n, taps, width, targets, register_stages)


def generate_geometry(spec: Geometry) -> str:
    declarations: list[str] = []
    instances: list[str] = []
    heap: list[list[str]] = [[] for _ in range(spec.width)]
    full_adder_count = 0
    half_adder_count = 0

    for tap in range(spec.taps):
        declarations.append(f"    signal inv_lo_sign_{tap} : std_logic;")
        declarations.append(f"    signal inv_hi_sign_{tap} : std_logic;")

        for bit in range(11):
            heap[bit].append(f"pp_lo_flat({tap * 12 + bit})")
            heap[4 + bit].append(f"pp_hi_flat({tap * 12 + bit})")

        heap[11].append(f"inv_lo_sign_{tap}")
        heap[15].append(f"inv_hi_sign_{tap}")

    # Signed 12-bit x equals bits[10:0] + not(sign)*2^11 - 2^11.
    # Apply this to every low and high (shifted-by-four) operand.
    correction = (
        -spec.taps * (1 << 11) - spec.taps * (1 << 15)
    ) & ((1 << spec.width) - 1)
    for column in range(spec.width):
        if correction & (1 << column):
            heap[column].append("'1'")

    def compressor(
        *,
        stage: int,
        column: int,
        inputs: list[str],
        is_half: bool,
    ) -> tuple[str, str]:
        nonlocal full_adder_count, half_adder_count

        if is_half:
            index = half_adder_count
            half_adder_count += 1
            stem = f"l{stage}_c{column}_ha{index}"
            init = HALF_ADDER_INIT
            i2 = "'0'"
        else:
            index = full_adder_count
            full_adder_count += 1
            stem = f"l{stage}_c{column}_fa{index}"
            init = FULL_ADDER_INIT
            i2 = inputs[2]

        sum_name = f"{stem}_sum"
        carry_name = f"{stem}_carry"
        declarations.append(f"    signal {sum_name} : std_logic;")
        declarations.append(f"    signal {carry_name} : std_logic;")

        instances.extend(
            [
                f"    {stem} : LUT6_2",
                "        generic map (",
                f'            INIT => X"{init}"',
                "        )",
                "        port map (",
                f"            O5 => {sum_name},",
                f"            O6 => {carry_name},",
                f"            I0 => {inputs[0]},",
                f"            I1 => {inputs[1]},",
                f"            I2 => {i2},",
                "            I3 => '0',",
                "            I4 => '0',",
                "            I5 => '1'",
                "        );",
                "",
            ]
        )
        return sum_name, carry_name

    stage_heights: list[str] = []
    register_banks: list[list[tuple[str, str]]] = []

    for stage, target in enumerate(spec.targets, start=1):
        next_heap: list[list[str]] = [[] for _ in range(spec.width)]

        for column in range(spec.width):
            old_bits = list(heap[column])
            reduction = max(0, len(next_heap[column]) + len(old_bits) - target)
            full_count = reduction // 2
            half_count = reduction % 2

            for _ in range(full_count):
                inputs = old_bits[:3]
                del old_bits[:3]
                sum_name, carry_name = compressor(
                    stage=stage,
                    column=column,
                    inputs=inputs,
                    is_half=False,
                )
                next_heap[column].append(sum_name)
                if column + 1 < spec.width:
                    next_heap[column + 1].append(carry_name)

            if half_count:
                inputs = old_bits[:2]
                del old_bits[:2]
                sum_name, carry_name = compressor(
                    stage=stage,
                    column=column,
                    inputs=inputs,
                    is_half=True,
                )
                next_heap[column].append(sum_name)
                if column + 1 < spec.width:
                    next_heap[column + 1].append(carry_name)

            next_heap[column].extend(old_bits)

        heap = next_heap
        stage_heights.append(
            f"-- Stage {stage}: target {target}, max height "
            f"{max(map(len, heap))}"
        )

        if stage in spec.register_stages:
            bank = len(register_banks) + 1
            assignments: list[tuple[str, str]] = []
            registered_heap: list[list[str]] = [
                [] for _ in range(spec.width)
            ]
            for column, bits in enumerate(heap):
                for bit_index, source in enumerate(bits):
                    destination = f"s{bank}_c{column}_b{bit_index}"
                    declarations.append(
                        f"    signal {destination} : std_logic := '0';"
                    )
                    assignments.append((destination, source))
                    registered_heap[column].append(destination)
            register_banks.append(assignments)
            heap = registered_heap

    assert max(map(len, heap)) <= 2

    row_count = 2 * spec.taps
    register_description = (
        "The first three levels are registered; the final three are combinational."
        if spec.n == 3
        else "Registers follow levels 3 and 6; the final three are combinational."
    )
    header = f"""-- ============================================================================
-- {spec.entity}.vhd -- generated exact signed {row_count}-row Dadda compressor
-- ============================================================================
-- Generated by scripts/generate_cfglut_bitheap.py.
-- {full_adder_count} full compressors + {half_adder_count} half compressors.
-- {register_description}
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.ALL;

entity {spec.entity} is
    port (
        clk         : in  std_logic;
        resetn      : in  std_logic;
        ce          : in  std_logic;
        valid_in    : in  std_logic;
        pp_lo_flat  : in  std_logic_vector({12 * spec.taps - 1} downto 0);
        pp_hi_flat  : in  std_logic_vector({12 * spec.taps - 1} downto 0);
        row_a_out   : out std_logic_vector({spec.width - 1} downto 0);
        row_b_out   : out std_logic_vector({spec.width - 1} downto 0);
        valid_out   : out std_logic
    );
end entity {spec.entity};

architecture structural of {spec.entity} is
"""
    for bank in range(1, len(register_banks) + 1):
        header += f"    signal valid_s{bank} : std_logic := '0';\n"

    body: list[str] = ["begin", ""]
    for tap in range(spec.taps):
        body.append(
            f"    inv_lo_sign_{tap} <= not pp_lo_flat({tap * 12 + 11});"
        )
        body.append(
            f"    inv_hi_sign_{tap} <= not pp_hi_flat({tap * 12 + 11});"
        )
    body.append("")
    body.extend(f"    {line}" for line in stage_heights)
    body.append("")
    body.extend(instances)

    for bank, assignments in enumerate(register_banks, start=1):
        valid_source = "valid_in" if bank == 1 else f"valid_s{bank - 1}"
        body.extend(
            [
                f"    stage{bank}_registers : process(clk)",
                "    begin",
                "        if rising_edge(clk) then",
                "            if resetn = '0' then",
            ]
        )
        for destination, _ in assignments:
            body.append(f"                {destination} <= '0';")
        body.extend(
            [
                f"                valid_s{bank} <= '0';",
                "            elsif ce = '1' then",
            ]
        )
        for destination, source in assignments:
            body.append(f"                {destination} <= {source};")
        body.extend(
            [
                f"                valid_s{bank} <= {valid_source};",
                "            end if;",
                "        end if;",
                f"    end process stage{bank}_registers;",
                "",
            ]
        )

    for column, bits in enumerate(heap):
        row_a = bits[0] if bits else "'0'"
        row_b = bits[1] if len(bits) > 1 else "'0'"
        body.append(f"    row_a_out({column}) <= {row_a};")
        body.append(f"    row_b_out({column}) <= {row_b};")

    body.extend(
        [
            "",
            f"    valid_out <= valid_s{len(register_banks)};",
            "end architecture structural;",
            "",
        ]
    )

    return header + "\n".join(declarations) + "\n" + "\n".join(body)


def generate() -> str:
    """Compatibility entry point for callers of the original generator."""
    return generate_geometry(geometry(3))


def selected_geometries(kernel: str) -> tuple[Geometry, ...]:
    if kernel == "all":
        return geometry(3), geometry(5)
    return (geometry(int(kernel)),)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--kernel", choices=("3", "5", "all"), default="all",
        help="compressor geometry to generate (default: both)",
    )
    parser.add_argument(
        "--check", action="store_true",
        help="verify committed outputs without rewriting them",
    )
    args = parser.parse_args()

    failed = False
    for spec in selected_geometries(args.kernel):
        rendered = generate_geometry(spec)
        if args.check:
            if not spec.output.is_file() or spec.output.read_text() != rendered:
                print(f"MISMATCH: {spec.output}")
                failed = True
            else:
                print(f"OK: {spec.output}")
        else:
            spec.output.write_text(rendered, encoding="utf-8", newline="\n")
            print(spec.output)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
