![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Verilog](https://img.shields.io/badge/language-Verilog-green)
![FPGA](https://img.shields.io/badge/target-Lattice%20iCE40-purple)

# High-Performance 16-bit Mixed-Mode Booth Radix-8 Multiplier

<div align="center">
  <h2> (Optimized for Lattice iCE40 - Supports Signed & Unsigned Operations) </h2>
  <h3>🚀 Now v2.0: Faster (145 MHz), Lower Latency (5 Cycles), and Smaller Area!</h3>
</div>



A highly optimized, soft-core 16-bit multiplier designed specifically for Lattice iCE40 FPGAs.

## 📊 High-Level Diagram
```mermaid
graph LR
    subgraph INPUTS ["1. Input Decomposition"]
        direction TB
        A["Operand A (16-bit)"]
        B["Operand B (16-bit)"]
        
        A --> A_H["A High"]
        A --> A_L["A Low"]
        B --> B_H["B High"]
        B --> B_L["B Low"]
    end

    subgraph PARALLEL_CORES ["2. Parallel Execution (5 Cycles)"]
        direction TB
        M0["Core P0<br/>(Low x Low)"]
        M1["Core P1<br/>(High x Low)"]
        M2["Core P2<br/>(Low x High)"]
        M3["Core P3<br/>(High x High)"]
    end

    subgraph SPLIT_ADDER ["3. Split-Adder Topology"]
        direction TB
        P0_L["P0 Low Byte"]
        
        ADD1("Adder 1<br/>(18-bit Mid)")
        ADD2("Adder 2<br/>(24-bit Upper)")
        
        EXT["Sign Ext"]
        BASE["Base Upper"]
    end

    subgraph RESULT ["4. Output"]
        OUT([Final Product 32-bit])
    end

    %% Wiring connections - Input to Cores
    A_L --> M0
    B_L --> M0
    A_H --> M1
    B_L --> M1
    A_L --> M2
    B_H --> M2
    A_H --> M3
    B_H --> M3

    %% Wiring connections - Cores to Adder
    M0 --> P0_L
    M0 --> BASE
    M1 --> ADD1
    M2 --> ADD1
    M3 --> BASE

    %% Internal Adder Wiring
    ADD1 --> EXT
    EXT --> ADD2
    BASE --> ADD2
    
    %% Wiring to Output
    P0_L --- WIRE_FAST["Direct Wire<br/>(No Delay)"] --> OUT
    ADD2 --> OUT

    %% Styling
    style SPLIT_ADDER fill:#e1f5fe,stroke:#01579b,stroke-width:2px,stroke-dasharray: 5 5
    style PARALLEL_CORES fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style WIRE_FAST stroke:#00c853,stroke-width:4px
```


---

### Performance Comparison (Lattice iCE40)

The table below compares the three implementations. While the **Linear** version achieves a higher raw clock frequency, the **Pipeline** version delivers superior processing power (Throughput) by handling one operation every 4 cycles.

| Verilog Source File | Architecture | Latency (Cycles) | Max Freq ($F_{max}$) | Resources (LCs) | **Throughput (MOPS)** |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `..._su_5_linear_146.v` | Iterative Linear | 5 | 149.10 MHz | **441 (5%)** | 29.8 |
| `..._su_7_linear_155.v` | Registered I/O | 7 | **154.77 MHz** | 474 (6%) | 21.3 |
| `..._su_4_pipeline_144.v` | **Decoupled Pipeline** | **4 (Sustained)** | 141.00 MHz | 463 (6%) | **35.2** |

> **Definitions:**
> *   **MOPS:** Million Operations Per Second (Calculated as $F_{max} / \text{Cycles per Op}$).
> *   **Sustained Cycles:** The pipeline version has a longer absolute latency but accepts new data every **4 cycles**.

#### Summary of Versions

1.  **Linear (5 Cycles):**
    *   Best for **Low Area** requirements.
    *   Simple interface, lowest absolute latency for single operations.
    *   *Trade-off:* Lower throughput compared to the pipeline version.

2.  **Registered I/O (7 Cycles):**
    *   Best for **Timing Closure** in large designs.
    *   Inputs and outputs are fully registered, isolating the core path from routing delays.
    *   *Trade-off:* Lowest throughput due to extra registry stages.

3.  **Pipeline (4 Cycles Effective):**
    *   Best for **High Performance / DSP**.
    *   Uses a decoupled input buffer and sequencer to overlap I/O with computation.
    *   **Result:** Delivers **~18% more processing power** (35.2 vs 29.8 MOPS) than the linear version, despite having a slightly lower clock speed.

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
| **Fmax (Frequency)** | 96.8 MHz | **145.45 MHz** | **+50% Faster Clock** |
| **Latency (Cycles)** | 17 Cycles | **5 Cycles** | **3.4x Fewer Cycles** |
| **Total Execution Time** | ~175.4 ns | **~34.4 ns** | **5.1x Faster Calculation** |
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
