`timescale 1ns / 1ps
`default_nettype none

module pipeline_radix8 (
    input  wire        clk,
    input  wire        v_in,
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire [1:0]  sm,
    output reg  [15:0] p,
    output reg         v_out
);

    //==========================================================================
    // S1: Captura e Extensão Dinâmica
    //==========================================================================
    reg signed [11:0] s1_a;
    // CORREÇÃO: Reduzido para 10 bits (Suficiente para Booth Radix-8 em 8-bit input)
    reg        [9:0]  s1_b; 
    reg               s1_v;

    always @(posedge clk) begin
        s1_v <= v_in;
        // A precisa de 12 bits para suportar shifts (4A) e sinal
        s1_a <= sm[1] ? $signed({{4{a[7]}}, a}) : $signed({4'b0, a});
        
        // B precisa apenas de 10 bits: [SignExt, b[7:0], ImpliedZero]
        // Se assinado: repete b[7]. Se não: 0.
        s1_b <= sm[0] ? { b[7], b, 1'b0 } : { 1'b0, b, 1'b0 };
    end

    //==========================================================================
    // S2: Geração do Múltiplo Hard (3A)
    //==========================================================================
    reg [11:0] s2_a1, s2_a2, s2_a3, s2_a4;
    reg [9:0]  s2_b;
    reg        s2_v;

    always @(posedge clk) begin
        s2_v  <= s1_v;
        s2_b  <= s1_b; // Agora 10 bits -> 10 bits (Sem warnings)
        s2_a1 <= $unsigned(s1_a);
        s2_a2 <= $unsigned(s1_a << 1);
        s2_a3 <= $unsigned(s1_a + (s1_a << 1)); 
        s2_a4 <= $unsigned(s1_a << 2);
    end

    //==========================================================================
    // S3: Decodificação Simétrica
    //==========================================================================
    function [3:0] decode_mag(input [2:0] mag_idx);
        case (mag_idx)
            3'b111:         decode_mag = 4'b1000;
            3'b110, 3'b101: decode_mag = 4'b0100;
            3'b100, 3'b011: decode_mag = 4'b0010;
            3'b010, 3'b001: decode_mag = 4'b0001;
            default:        decode_mag = 4'b0000;
        endcase
    endfunction

    reg [2:0] s3_sel1, s3_sel2, s3_sel3, s3_sel4, s3_neg;
    reg [11:0] s3_a1, s3_a2, s3_a3, s3_a4;
    reg        s3_v;

    always @(posedge clk) begin
        s3_v  <= s2_v;
        s3_a1 <= s2_a1; s3_a2 <= s2_a2; s3_a3 <= s2_a3; s3_a4 <= s2_a4;
        
        // Utiliza bits 9, 6, 3. Todos dentro do range [9:0].
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

    wire [15:0] ext_a1 = {{4{s3_a1[11]}}, s3_a1};
    wire [15:0] ext_a2 = {{4{s3_a2[11]}}, s3_a2};
    wire [15:0] ext_a3 = {{4{s3_a3[11]}}, s3_a3};
    wire [15:0] ext_a4 = {{4{s3_a4[11]}}, s3_a4};

    always @(posedge clk) begin
        s4_v <= s3_v;
        
        s4_p0 <= ( ({16{s3_sel1[0]}} & ext_a1) | ({16{s3_sel2[0]}} & ext_a2) |
                   ({16{s3_sel3[0]}} & ext_a3) | ({16{s3_sel4[0]}} & ext_a4) ) ^ {16{s3_neg[0]}};
        
        s4_p1 <= ( ( ({16{s3_sel1[1]}} & ext_a1) | ({16{s3_sel2[1]}} & ext_a2) |
                     ({16{s3_sel3[1]}} & ext_a3) | ({16{s3_sel4[1]}} & ext_a4) ) ^ {16{s3_neg[1]}} ) << 3;

        s4_p2 <= ( ( ({16{s3_sel1[2]}} & ext_a1) | ({16{s3_sel2[2]}} & ext_a2) |
                     ({16{s3_sel3[2]}} & ext_a3) | ({16{s3_sel4[2]}} & ext_a4) ) ^ {16{s3_neg[2]}} ) << 6;
        
        // CORREÇÃO: Alterado 7'b0 -> 9'b0 para totalizar 16 bits.
        // 9(zeros) + 1(neg) + 2(zeros) + 1(neg) + 2(zeros) + 1(neg) = 16 bits.
        s4_corr <= {9'b0, s3_neg[2], 2'b0, s3_neg[1], 2'b0, s3_neg[0]};
    end

    //==========================================================================
    // S5: Redução CSA (Carry-Save Adder) 4:2
    //==========================================================================
    reg [15:0] s5_s, s5_c;
    reg        s5_v;

    wire [15:0] csa_t_sum = s4_p0 ^ s4_p1 ^ s4_p2;
    wire [15:0] csa_t_car = ((s4_p0 & s4_p1) | (s4_p1 & s4_p2) | (s4_p0 & s4_p2)) << 1;

    always @(posedge clk) begin
        s5_v <= s4_v;
        s5_s <= csa_t_sum ^ csa_t_car ^ s4_corr;
        s5_c <= ((csa_t_sum & csa_t_car) | (csa_t_car & s4_corr) | (csa_t_sum & s4_corr)) << 1;
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
`default_nettype wire `timescale 1ns / 1ps
