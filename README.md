# High-Performance 16-bit Booth Radix-8 Multiplier (iCE40 Optimized)

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Verilog](https://img.shields.io/badge/language-Verilog-green)
![FPGA](https://img.shields.io/badge/target-Lattice%20iCE40-purple)

A highly optimized, soft-core 16-bit multiplier designed specifically for Lattice iCE40 FPGAs. By utilizing a parallel Booth Radix-8 architecture with timing-critical pre-calculation, this core achieves **>133 MHz** performance and **~52ns** total latency, outperforming standard serial implementations by over 3x while remaining purely logic-based (No DSPs required).

## 📈 Waveform Verification

![Simulation Waveform](https://github.com/guinamen/ice40-booth-multiplier/blob/main/booth_multiplayer.png?raw=true)

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

## 🛠️ Usage

### Instantiation Template

```verilog
booth_radix8_multiplier #(
    .WIDTH(16)
) u_multiplier (
    .clk(clk),
    .rst_n(rst_n),
    .start(start_signal),       // One-cycle pulse to start
    .multiplicand(op_a),        // 16-bit input A
    .multiplier(op_b),          // 16-bit input B
    .sign_mode(2'b11),          // Mode control (see below)
    .product(result),           // 32-bit output
    .done(done_signal),         // High when result is ready
    .busy(busy_signal)          // High while calculating
);
```

### Sign Modes (sign_mode)

This core handles bit extension automatically based on the selected mode:

    2'b00: Unsigned × Unsigned
    2'b01: Unsigned × Signed (A is Unsigned, B is Signed)
    2'b10: Signed × Unsigned (A is Signed, B is Unsigned)
    2'b11: Signed × Signed (Standard behavior)

## ⚡ How to Simulate

Prerequisites: Icarus Verilog and GTKWave.
```bash
git clone https://github.com/guinamen/ice40-booth-multiplier.git
cd ice40-booth-multiplier
iverilog -Wall -o sim_mult.out tb/tb_booth_radix8_su.v  rtl/booth_radix8_multiplier.v
vvp sim_mult.out
gtkwave dump.vcd
```

## ⚙️ Architectural Details

### The "Hard 3M" Problem

The bottleneck of the Booth Radix-8 algorithm is calculating the 3×M3×M term (which requires computing M+2MM+2M). In a standard implementation, this adder sits in the critical path of the iterative loop, severely limiting Fmax.

### The Optimization
This design breaks that bottleneck by **pre-calculating the 3M term** during the setup cycle (when the start signal is active). The result is stored in a register.
    
**Result** : During the calculation loops, the MUX simply selects the pre-calculated value. The critical path is reduced to a simple MUX + Accumulator, allowing the clock speed to rise from ~110 MHz to ~133 MHz.

### Decomposition
Instead of a single 16-bit iterative core, the design splits the operation into four 8-bit multiplications (L×LL×L,H×LH×L,L×HL×H,H×HH×H) running in parallel. This keeps the carry chains short and manageable for the FPGA routing fabric.

## 📄 License

This project is open-source and available under the MIT License.
