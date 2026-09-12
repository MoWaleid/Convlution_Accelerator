"""Generate the fixed 3x3 signed partial-product Dadda compressor.

The generated VHDL is structural and deterministic.  It compresses only
occupied bit columns, uses one LUT6_2 per 3:2 or 2:2 compressor, and inserts a
pipeline register after the third of six Dadda stages.
"""

from pathlib import Path


WIDTH = 21
TAPS = 9
TARGETS = (13, 9, 6, 4, 3, 2)
FULL_ADDER_INIT = "E8E8E8E896969696"
HALF_ADDER_INIT = "8888888866666666"


def generate() -> str:
    declarations: list[str] = []
    instances: list[str] = []
    heap: list[list[str]] = [[] for _ in range(WIDTH)]
    full_adder_count = 0
    half_adder_count = 0

    for tap in range(TAPS):
        declarations.append(f"    signal inv_lo_sign_{tap} : std_logic;")
        declarations.append(f"    signal inv_hi_sign_{tap} : std_logic;")

        for bit in range(11):
            heap[bit].append(f"pp_lo_flat({tap * 12 + bit})")
            heap[4 + bit].append(f"pp_hi_flat({tap * 12 + bit})")

        heap[11].append(f"inv_lo_sign_{tap}")
        heap[15].append(f"inv_hi_sign_{tap}")

    # Signed 12-bit x equals bits[10:0] + not(sign)*2^11 - 2^11.
    # Apply this to nine low and nine high (shifted-by-four) operands.
    correction = (-TAPS * (1 << 11) - TAPS * (1 << 15)) & ((1 << WIDTH) - 1)
    for column in range(WIDTH):
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
    register_assignments: list[tuple[str, str]] = []

    for stage, target in enumerate(TARGETS, start=1):
        next_heap: list[list[str]] = [[] for _ in range(WIDTH)]

        for column in range(WIDTH):
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
                if column + 1 < WIDTH:
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
                if column + 1 < WIDTH:
                    next_heap[column + 1].append(carry_name)

            next_heap[column].extend(old_bits)

        heap = next_heap
        stage_heights.append(
            f"-- Stage {stage}: target {target}, max height "
            f"{max(map(len, heap))}"
        )

        if stage == 3:
            registered_heap: list[list[str]] = [[] for _ in range(WIDTH)]
            for column, bits in enumerate(heap):
                for bit_index, source in enumerate(bits):
                    destination = f"s1_c{column}_b{bit_index}"
                    declarations.append(
                        f"    signal {destination} : std_logic := '0';"
                    )
                    register_assignments.append((destination, source))
                    registered_heap[column].append(destination)
            heap = registered_heap

    assert max(map(len, heap)) <= 2

    header = f"""-- ============================================================================
-- cfglut5_bitheap_3x3.vhd -- generated exact signed 18-row Dadda compressor
-- ============================================================================
-- Generated by scripts/generate_cfglut_bitheap.py.
-- {full_adder_count} full compressors + {half_adder_count} half compressors.
-- The first three levels are registered; the final three are combinational.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.ALL;

entity cfglut5_bitheap_3x3 is
    port (
        clk         : in  std_logic;
        resetn      : in  std_logic;
        ce          : in  std_logic;
        valid_in    : in  std_logic;
        pp_lo_flat  : in  std_logic_vector(107 downto 0);
        pp_hi_flat  : in  std_logic_vector(107 downto 0);
        row_a_out   : out std_logic_vector(20 downto 0);
        row_b_out   : out std_logic_vector(20 downto 0);
        valid_out   : out std_logic
    );
end entity cfglut5_bitheap_3x3;

architecture structural of cfglut5_bitheap_3x3 is
    signal valid_s1 : std_logic := '0';
"""

    body: list[str] = ["begin", ""]
    for tap in range(TAPS):
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

    body.extend(
        [
            "    stage1_registers : process(clk)",
            "    begin",
            "        if rising_edge(clk) then",
            "            if resetn = '0' then",
        ]
    )
    for destination, _ in register_assignments:
        body.append(f"                {destination} <= '0';")
    body.extend(
        [
            "                valid_s1 <= '0';",
            "            elsif ce = '1' then",
        ]
    )
    for destination, source in register_assignments:
        body.append(f"                {destination} <= {source};")
    body.extend(
        [
            "                valid_s1 <= valid_in;",
            "            end if;",
            "        end if;",
            "    end process stage1_registers;",
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
            "    valid_out <= valid_s1;",
            "end architecture structural;",
            "",
        ]
    )

    return header + "\n".join(declarations) + "\n" + "\n".join(body)


if __name__ == "__main__":
    output = (
        Path(__file__).resolve().parents[1]
        / "Convlution_Accelerator.srcs"
        / "sources_1"
        / "new"
        / "cfglut5_bitheap_3x3.vhd"
    )
    output.write_text(generate(), encoding="utf-8", newline="\n")
    print(output)
