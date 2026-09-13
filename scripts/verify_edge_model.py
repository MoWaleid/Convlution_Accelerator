"""Independent simplified CE/valid scheduling model for the K16 edge-bubble fix.

SCOPE (stated per review): this is a simplified clock-enable/valid scheduling
model built from RTL facts only (no testbench code reuse).  It models the
window-generator geometry, the 4-stage engine pipeline, and the serializer's
one-vector-per-4-clocks acceptance.  It does NOT model AXIS byte packing,
output-FIFO depth behavior, the controller lifecycle (FAULT/ABORT/reset),
arithmetic values, software commands, or randomized stalls.  It is a
scheduling cross-check of the measured XSim metrics, not an independent
full-wrapper functional proof.

Reproduced metrics (continuous-supply frame D):
  baseline (prefetch=false): invalid_advances=62, window span 4080 clk,
                             output span 4095 clk
  prefetch=true:             invalid_advances=0,  same spans
"""

W, H, N, K = 34, 34, 3, 16
FCLK_MHZ = 100.0
BEATS_PER_VECTOR = (K * 16) // 64          # 32 bytes / 8 = 4 beats
TOTAL_PIXELS = W * H                        # 1156
WINDOWS = (W - N + 1) * (H - N + 1)         # 1024
TOTAL_BEATS = WINDOWS * BEATS_PER_VECTOR    # 4096
FILL = (N - 1) * W + (N - 1)                # 70 pixels before first window
BASELINE_INVALID = (H - N) * (N - 1)        # 31 row transitions x 2 = 62


class TimeoutError_(Exception):
    pass


def valid_after(c):
    """Registered window_valid after consuming pixel index c (0-based)."""
    return c >= FILL and (c % W) >= (N - 1)


def simulate(prefetch, max_clocks=20000, strict=True):
    """Run one frame.  Raises TimeoutError_ (strict) if the frame does not
    complete within max_clocks; otherwise returns the result dict with an
    explicit 'completed' flag."""
    consumed = 0
    window_valid = False            # generator valid_out_reg
    pipe = [False] * 4              # engine pipeline valid flags
    ser_holding = False             # formatter holds a vector
    ser_cnt = 0                     # beats emitted of the held vector (0..3)
    beats_emitted = 0
    windows_seen = 0
    invalid_advances = 0
    first_window_t = last_window_t = None
    first_beat_t = last_beat_t = None
    completed = False
    t = 0

    for t in range(max_clocks):
        # --- serializer: sink always ready, one beat per held clock ---
        emit = ser_holding
        finishing = ser_holding and ser_cnt == 3
        if emit:
            beats_emitted += 1
            if first_beat_t is None:
                first_beat_t = t
            last_beat_t = t

        in_ready = (not ser_holding) or finishing
        core_valid = pipe[3]

        # --- engine CE (wrapper: core_ce stalls only on a blocked result) ---
        ce = not (core_valid and not in_ready)

        # --- result acceptance: exactly one vector per accepted window ---
        accept = core_valid and in_ready

        # --- engine consumes window on ce; count metrics ---
        if ce:
            if window_valid:
                windows_seen += 1
                if first_window_t is None:
                    first_window_t = t
                last_window_t = t
            elif 1 <= windows_seen < WINDOWS:
                # TB metric window: first valid window .. last valid window
                invalid_advances += 1

        # --- window generator CE policy and pixel ingest ---
        window_ce = (ce or not window_valid) if prefetch else ce
        next_window_valid = window_valid
        if window_ce:
            if consumed < TOTAL_PIXELS:
                consumed += 1
                next_window_valid = valid_after(consumed - 1)
            else:
                # RTL else-branch: generator ce without a pixel clears valid
                next_window_valid = False

        # --- next-state updates ---
        if ce:
            pipe = [window_valid] + pipe[:3]

        next_holding, next_cnt = ser_holding, ser_cnt
        if emit:
            next_cnt += 1
            if next_cnt == BEATS_PER_VECTOR:
                next_holding, next_cnt = False, 0
        if accept:
            next_holding, next_cnt = True, 0   # registered acceptance
        ser_holding, ser_cnt = next_holding, next_cnt

        window_valid = next_window_valid

        if beats_emitted >= TOTAL_BEATS and consumed == TOTAL_PIXELS:
            completed = True
            break

    result = {
        "prefetch": prefetch,
        "completed": completed,
        "invalid_advances": invalid_advances,
        "windows": windows_seen,
        "consumed": consumed,
        "beats": beats_emitted,
        "window_span_clk": (last_window_t - first_window_t) if first_window_t is not None else None,
        "output_span_clk": (last_beat_t - first_beat_t) if first_beat_t is not None else None,
        "model_completion_clk": t,   # simplified model only: excludes
                                     # controller/software overhead
    }
    if strict and not completed:
        raise TimeoutError_(
            f"frame did not complete within {max_clocks} clocks "
            f"(windows={windows_seen}, consumed={consumed}, beats={beats_emitted})")
    return result


def check(result):
    """Assert exact completion counts and the policy's benchmark metrics."""
    assert result["completed"], "frame incomplete"
    assert result["windows"] == WINDOWS, result
    assert result["consumed"] == TOTAL_PIXELS, result   # lossless ingest
    assert result["beats"] == TOTAL_BEATS, result
    expected_invalid = 0 if result["prefetch"] else BASELINE_INVALID
    assert result["invalid_advances"] == expected_invalid, result
    assert result["output_span_clk"] == TOTAL_BEATS - 1, result  # gapless


if __name__ == "__main__":
    print(f"geometry: {TOTAL_PIXELS} px, {WINDOWS} windows, fill={FILL}, "
          f"{BEATS_PER_VECTOR} beats/vector")

    # Deliberate timeout test: a tiny budget must yield an incomplete frame.
    short = simulate(True, max_clocks=100, strict=False)
    assert not short["completed"], "timeout self-test failed to time out"
    print("timeout self-test: incomplete at max_clocks=100 -> detected OK")

    results = {}
    for prefetch in (False, True):
        r = simulate(prefetch)          # strict: raises on timeout
        check(r)
        results[prefetch] = r
        print(f"prefetch={str(prefetch):5}  invalid_advances={r['invalid_advances']:3d}  "
              f"windows={r['windows']}  consumed={r['consumed']}  "
              f"window_span={r['window_span_clk']} clk  "
              f"output_span={r['output_span_clk']} clk  "
              f"model_completion={r['model_completion_clk']} clk")

    # Throughput at 100 MHz.  Like-for-like: the continuous output burst
    # delivers TOTAL_BEATS transfers in TOTAL_BEATS clock slots (the measured
    # first-to-last timestamp difference is one slot shorter).  All rates
    # below are sustained output-path rates; the core's II=1 peak is 16
    # output pixels/cycle but this serializer cannot drain faster than 4.
    slot_ns = 1000.0 / FCLK_MHZ
    for prefetch in (False, True):
        r = results[prefetch]
        useful = WINDOWS
        slots = WINDOWS + r["invalid_advances"]
        print(f"\n--- throughput prefetch={prefetch} @{FCLK_MHZ:.0f} MHz ---")
        print(f"slot efficiency          : {100.0*useful/slots:6.2f} % "
              f"({useful}/{slots} engine slots, {r['invalid_advances']} wasted)")
        print(f"beat throughput          : {FCLK_MHZ*1e6/1e6:6.2f} M 64-bit beats/s (1 beat/clock)")
        print(f"output bandwidth         : {FCLK_MHZ*1e6*8/1e6:6.2f} MB/s (decimal, 64-bit link)")
        print(f"vector throughput        : {FCLK_MHZ*1e6/BEATS_PER_VECTOR/1e6:6.2f} M K16 vectors/s")
        print(f"channel results          : {FCLK_MHZ*1e6*K/BEATS_PER_VECTOR/1e6:6.2f} M results/s")
        print(f"first-to-last timestamp  : {r['output_span_clk']*slot_ns/1000:7.3f} us "
              f"({TOTAL_BEATS} transfers in {TOTAL_BEATS} slots)")
        print(f"model completion (upper bound, no controller/software "
              f"overhead): {r['model_completion_clk']*slot_ns/1000:7.3f} us")
