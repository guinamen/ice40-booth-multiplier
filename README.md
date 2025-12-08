# High-Performance 16-bit Booth Radix-8 Multiplier (iCE40 Optimized)

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Verilog](https://img.shields.io/badge/language-Verilog-green)
![FPGA](https://img.shields.io/badge/target-Lattice%20iCE40-purple)

A highly optimized, soft-core 16-bit multiplier designed specifically for Lattice iCE40 FPGAs. By utilizing a parallel Booth Radix-8 architecture with timing-critical pre-calculation, this core achieves **>133 MHz** performance and **~52ns** total latency, outperforming standard serial implementations by over 3x while remaining purely logic-based (No DSPs required).

## 🚀 Key Features

*   **High Performance:** Achieves **133.6 MHz** on iCE40HX8K (Speed Grade 1).
*   **Low Latency:** Completes a 16x16 operation in just **7 clock cycles** (Total time: ~52ns).
*   **Zero DSP Usage:** Implemented entirely in soft logic (LUTs/Carry Chains), perfect for devices with limited or exhausted DSP blocks.
*   **Parallel Architecture:** Uses 8-bit Decomposition (4 parallel cores) to reduce carry chain depth.
*   **Timing Optimized:** Implements **"Look-Ahead 3M Pre-calculation"** to break the critical path associated with Radix-8 arithmetic.
*   **Full Mode Support:** Supports Signed, Unsigned, and Mixed-mode (Signed × Unsigned) operations.

## 📊 Performance Benchmarks

Synthesized using Yosys/Nextpnr for **iCE40HX8K-CT256**. Comparison against a standard "Shift-and-Add" Serial Multiplier:

| Metric | Standard Serial Mult | **Booth Radix-8 (This Core)** | Improvement |
| :--- | :--- | :--- | :--- |
| **Fmax (Frequency)** | 96.8 MHz | **133.6 MHz** | **+38% Faster Clock** |
| **Latency (Cycles)** | 17 Cycles | **7 Cycles** | **2.4x Fewer Cycles** |
| **Total Execution Time** | ~175.4 ns | **~52.4 ns** | **3.3x Faster Calculation** |
| **Area (Logic Cells)** | ~340 LCs | **~488 LCs** | +43% Area (Trade-off) |

## 📈 Waveform Verification

![Simulation Waveform](waveform_booth.png)

## 🛠️ Usage

### Instantiation

```verilog
booth_radix8_multiplier #(
    .WIDTH(16)
) u_multiplier (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_signal),       // One-cycle pulse to start
    .multiplicand(op_a),        // 16-bit input A
    .multiplier(op_b),          // 16-bit input B
    .sign_mode(2'b11),          // Mode control for [AB] -> 0 unsigned 1 signed. 
    .product(result),           // 32-bit output
    .done(done_signal),         // High when result is ready
    .busy(busy_signal)          // High while calculating
);
