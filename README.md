# High-Performance 16-bit Mixed-Mode Booth Radix-8 Multiplier
<div align="center">
  <h2> (Optimized for Lattice iCE40 - Supports Signed & Unsigned Operations) </h2>
  <h3>🚀 Now v2.0: Faster (145 MHz), Lower Latency (5 Cycles), and Smaller Area!</h3>
</div>

```mermaid
graph TD
    subgraph INPUTS ["Input Decomposition"]
        A[Operand A (16-bit)] --> A_H[A High] & A_L[A Low]
        B[Operand B (16-bit)] --> B_H[B High] & B_L[B Low]
    end

    subgraph PARALLEL_CORES ["Parallel Execution Engine (5 Cycles)"]
        direction LR
        note1[Features:<br/>- Flattened Control Logic<br/>- Look-Ahead 3M Calc]
        
        M0[<b>Core P0</b><br/>Low x Low]
        M1[<b>Core P1</b><br/>High x Low]
        M2[<b>Core P2</b><br/>Low x High]
        M3[<b>Core P3</b><br/>High x High]

        A_L & B_L --> M0
        A_H & B_L --> M1
        A_L & B_H --> M2
        A_H & B_H --> M3
    end

    subgraph SPLIT_ADDER ["Optimized Split-Adder Topology"]
        P0_L[P0 Low Byte] --- WIRE_FAST[Direct Wire<br/>(No Delay)]
        
        P1 & P2 --> ADD1(<b>Adder 1</b><br/>18-bit Intermediate)
        
        ADD1 --> EXT[Sign Ext]
        P3 & P0_H[P0 High Byte] --> BASE[Base Upper]
        
        BASE & EXT --> ADD2(<b>Adder 2</b><br/>24-bit Final Upper)
    end

    subgraph RESULT ["Output"]
        ADD2 --> RES_H[Result Upper]
        WIRE_FAST --> RES_L[Result Lower]
        RES_H & RES_L --> OUT([<b>Final Product</b><br/>32-bit])
    end

    %% Connections specific to data flow
    M0 --> P0_L & P0_H
    M1 --> P1
    M2 --> P2
    M3 --> P3

    style SPLIT_ADDER fill:#e1f5fe,stroke:#01579b,stroke-width:2px,stroke-dasharray: 5 5
    style PARALLEL_CORES fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style WIRE_FAST stroke:#00c853,stroke-width:4px
```
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Verilog](https://img.shields.io/badge/language-Verilog-green)
![FPGA](https://img.shields.io/badge/target-Lattice%20iCE40-purple)

A highly optimized, soft-core 16-bit multiplier designed specifically for Lattice iCE40 FPGAs. Through deep architectural optimizations (**Flattened Control Mux** and **Split-Adder Topology**), this V2 core achieves **~145 MHz** performance and a deterministic latency of just **34.5ns** (5 cycles), outperforming standard serial implementations by over 5x while consuming only ~5% of the FPGA resources.

## 📈 Waveform Verification

![Simulation Waveform](doc/waveform.png?raw=true))
![Simulation Waveform](doc/gtk_wave.png?raw=true)

## 🚀 Key Features

*   **Industrial Performance:** Achieves **144.9 MHz** on iCE40HX8K (Speed Grade 1).
*   **Ultra-Low Latency:** Completes a 16x16 operation in just **5 clock cycles** (Total time: ~34.5ns).
*   **PPA Optimized:** Faster *and* smaller than previous versions (~407 LCs).
*   **Zero DSP Usage:** Implemented entirely in soft logic (LUTs/Carry Chains).
*   **Parallel Architecture:** Uses 8-bit Decomposition (4 parallel cores) + Split-Adder Recombination.
*   **Advanced Optimization:** Implements **"Look-Ahead 3M"** + **"Flattened Control Logic"** to minimize logic levels.
*   **Full Mode Support:** Supports Signed, Unsigned, and Mixed-mode (Signed × Unsigned) operations.

## 📊 Performance Benchmarks

Synthesized using Yosys/Nextpnr for **iCE40HX8K-CT256**. Comparison against a standard "Shift-and-Add" Serial Multiplier:

| Metric | Standard Serial Mult | **Booth Radix-8 (V2)** | Improvement |
| :--- | :--- | :--- | :--- |
| **Fmax (Frequency)** | 96.8 MHz | **144.9 MHz** | **+50% Faster Clock** |
| **Latency (Cycles)** | 17 Cycles | **5 Cycles** | **3.4x Fewer Cycles** |
| **Total Execution Time** | ~175.4 ns | **~34.5 ns** | **5.1x Faster Calculation** |
| **Area (Logic Cells)** | ~340 LCs | **~407 LCs** | Extremely Efficient (~5% util) |

> **Note:** Version 2.0 reduced the area by ~17% compared to V1 while increasing speed by ~9%.

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
iverilog -Wall -o sim_mult.out tb/tb_booth_radix8_su_simple.v  rtl/booth_radix8_multiplier.v
vvp sim_mult.out
gtkwave dump.vcd
```

## ⚡ How to Synthesize 

Prerequisites: Yosys and Icetime.
```bash
script/synthesis.sh rtl/booth_radix8_multiplier.v
```

## ⚙️ Architectural Details

The high speed of this core comes from three specific optimizations targeting the iCE40 LUT4 architecture:

1. "Flattened" Control Logic

Standard Booth multipliers use a deep logic chain (Decode → Select → Invert → Add). This design calculates selection signals (1x, 2x, 3x, 4x) and inversion flags in parallel, reducing the logic depth before the adder to just 1 LUT level.

2. Look-Ahead 3M Calculation

The hard "3×M" term (M + 2M) is pre-calculated during the setup cycle and stored in a register. This removes the adder overhead from the critical path of the iterative loop.

3. Split-Adder Topology (Top Level)

Instead of recombining the 4 sub-products using a slow 32-bit chain, the final adder is split. We skip carry propagation for the lower 8 bits (which require no addition), effectively turning the final stage into a faster ~24-bit adder.

## 📄 License

This project is open-source and available under the MIT License.
