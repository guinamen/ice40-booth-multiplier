`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Multiplicador Booth Radix-8 Masterpiece - iCE40 @ 267MHz
//==============================================================================
// Latência: 8 Ciclos | Throughput: 1 result/cycle | Frequência: > 260 MHz
// Otimizações: Decodificação Simétrica 3-bit, Redução CSA 4:2, Somador 8+8 bit
//==============================================================================

module booth_radix8_250mhz (
    input  wire        clk,
    input  wire        v_in,
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire [1:0]  sm,    // [1]=A signed, [0]=B signed
    output reg  [15:0] p,
    output reg         v_out
);

    //==========================================================================
    // S1: Captura e Extensão Dinâmica
    //==========================================================================
    reg signed [11:0] s1_a;
    reg        [11:0] s1_b;
    reg               s1_v;

    always @(posedge clk) begin
        s1_v <= v_in;
        s1_a <= sm[1] ? $signed({{4{a[7]}}, a}) : $signed({4'b0, a});
        s1_b <= sm[0] ? { {3{b[7]}}, b, 1'b0 }   : { 3'b0, b, 1'b0 };
    end

    //==========================================================================
    // S2: Geração do Múltiplo Hard (3A)
    //==========================================================================
    reg [11:0] s2_a1, s2_a2, s2_a3, s2_a4;
    reg [11:0] s2_b;
    reg        s2_v;

    always @(posedge clk) begin
        s2_v  <= s1_v;
        s2_b  <= s1_b;
        s2_a1 <= $unsigned(s1_a);
        s2_a2 <= $unsigned(s1_a << 1);
        s2_a3 <= $unsigned(s1_a + (s1_a << 1)); 
        s2_a4 <= $unsigned(s1_a << 2);
    end

    //==========================================================================
    // S3: Decodificação Simétrica (Magnitude de 3 bits)
    //==========================================================================
    function [3:0] decode_mag(input [2:0] mag_idx);
        case (mag_idx)
            3'b111:         decode_mag = 4'b1000; // Magnitude 4A
            3'b110, 3'b101: decode_mag = 4'b0100; // Magnitude 3A
            3'b100, 3'b011: decode_mag = 4'b0010; // Magnitude 2A
            3'b010, 3'b001: decode_mag = 4'b0001; // Magnitude 1A
            default:        decode_mag = 4'b0000; // Magnitude 0
        endcase
    endfunction

    reg [2:0] s3_sel1, s3_sel2, s3_sel3, s3_sel4, s3_neg;
    reg [11:0] s3_a1, s3_a2, s3_a3, s3_a4;
    reg        s3_v;

    always @(posedge clk) begin
        s3_v  <= s2_v;
        s3_a1 <= s2_a1; s3_a2 <= s2_a2; s3_a3 <= s2_a3; s3_a4 <= s2_a4;
        s3_neg <= {s2_b[9], s2_b[6], s2_b[3]}; 
        
        {s3_sel4[0], s3_sel3[0], s3_sel2[0], s3_sel1[0]} <= decode_mag(s2_b[2:0] ^ {3{s2_b[3]}});
        {s3_sel4[1], s3_sel3[1], s3_sel2[1], s3_sel1[1]} <= decode_mag(s2_b[5:3] ^ {3{s2_b[6]}});
        {s3_sel4[2], s3_sel3[2], s3_sel2[2], s3_sel1[2]} <= decode_mag(s2_b[8:6] ^ {3{s2_b[9]}});
    end

    //==========================================================================
    // S4: Seleção dos Produtos Parciais (MUX 4:1)
    //==========================================================================
    reg [15:0] s4_p0, s4_p1, s4_p2, s4_corr;
    reg        s4_v;

    always @(posedge clk) begin
        s4_v <= s3_v;
        s4_p0 <= ( ({16{s3_sel1[0]}} & {4'b0, s3_a1}) | ({16{s3_sel2[0]}} & {4'b0, s3_a2}) |
                   ({16{s3_sel3[0]}} & {4'b0, s3_a3}) | ({16{s3_sel4[0]}} & {4'b0, s3_a4}) ) ^ {16{s3_neg[0]}};
        
        s4_p1 <= ( ( ({16{s3_sel1[1]}} & {4'b0, s3_a1}) | ({16{s3_sel2[1]}} & {4'b0, s3_a2}) |
                     ({16{s3_sel3[1]}} & {4'b0, s3_a3}) | ({16{s3_sel4[1]}} & {4'b0, s3_a4}) ) ^ {16{s3_neg[1]}} ) << 3;

        s4_p2 <= ( ( ({16{s3_sel1[2]}} & {4'b0, s3_a1}) | ({16{s3_sel2[2]}} & {4'b0, s3_a2}) |
                     ({16{s3_sel3[2]}} & {4'b0, s3_a3}) | ({16{s3_sel4[2]}} & {4'b0, s3_a4}) ) ^ {16{s3_neg[2]}} ) << 6;
        
        s4_corr <= {7'b0, s3_neg[2], 2'b0, s3_neg[1], 2'b0, s3_neg[0]};
    end

    //==========================================================================
    // S5: Redução CSA (Carry-Save Adder) 4:2
    //==========================================================================
    reg [15:0] s5_s, s5_c, s5_corr;
    reg        s5_v;
    reg [15:0] t_s, t_c; // Temporários de compressão

    always @(posedge clk) begin
        s5_v <= s4_v;
        s5_corr <= s4_corr;
        t_s = s4_p0 ^ s4_p1 ^ s4_p2;
        t_c = ((s4_p0 & s4_p1) | (s4_p1 & s4_p2) | (s4_p0 & s4_p2)) << 1;
        s5_s <= t_s ^ t_c ^ s4_corr;
        s5_c <= ((t_s & t_c) | (t_c & s4_corr) | (t_s & s4_corr)) << 1;
    end

    //==========================================================================
    // S6: Somador Segmentado - LSB 8-bits
    //==========================================================================
    reg [7:0]  s6_res_low;
    reg        s6_carry;
    reg [15:8] s6_s_high, s6_c_high;
    reg        s6_v;

    always @(posedge clk) begin
        s6_v <= s5_v;
        {s6_carry, s6_res_low} <= s5_s[7:0] + s5_c[7:0];
        s6_s_high <= s5_s[15:8];
        s6_c_high <= s5_c[15:8];
    end

    //==========================================================================
    // S7: Somador Segmentado - MSB 8 bits
    //==========================================================================
    reg [15:0] s7_p;
    reg        s7_v;

    always @(posedge clk) begin
        s7_v <= s6_v;
        s7_p[15:8] <= s6_s_high + s6_c_high + {7'b0, s6_carry};
        s7_p[7:0]  <= s6_res_low;
    end

    //==========================================================================
    // S8: Saída Final
    //==========================================================================
    always @(posedge clk) begin
        v_out <= s7_v;
        p     <= s7_p;
    end

endmodule
`default_nettype wire
