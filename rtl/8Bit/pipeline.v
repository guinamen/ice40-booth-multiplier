`timescale 1ns / 1ps
`default_nettype none

module booth_core_250mhz (
    input  wire        clk,
    input  wire        v_in,
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    input  wire [1:0]  sm,
    output reg  [15:0] p,
    output reg         v_out
);

    // S1: Entrada
    reg signed [9:0]  s1_a;
    reg        [10:0] s1_b;
    reg               s1_v;

    // S2: Multiples + Booth Decodification
    reg signed [9:0]  s2_p1, s2_p2, s2_m1, s2_m2;
    reg               s2_v;
    reg [2:0]         s2_t0, s2_t1, s2_t2, s2_t3, s2_t4; // Tripletos individuais
    reg [4:0]         s2_neg;

    // S3: Selection Mux (Agora apenas 10 bits para atingir >250MHz)
    reg signed [9:0]  s3_pp [0:4];
    reg [4:0]         s3_neg;
    reg               s3_v;

    // S4: Sign Extension Manual + Adder Level 1 (20 bits)
    reg signed [19:0] s4_sum01, s4_sum23, s4_pp4, s4_corr;
    reg               s4_v;

    // S5: Adder Level 2
    reg signed [19:0] s5_sumA, s5_sumB;
    reg               s5_v;

    integer i;

    always @(posedge clk) begin
        // --- S1: Normalização ---
        s1_a <= sm[1] ? $signed({{2{a[7]}}, a}) : $signed({2'b00, a});
        s1_b <= { (sm[0] ? {2{b[7]}} : 2'b00), b, 1'b0 };
        s1_v <= v_in;

        // --- S2: Geração de Múltiplos e Registro de Tripletos ---
        s2_v  <= s1_v;
        s2_p1 <= s1_a;
        s2_p2 <= s1_a <<< 1;
        s2_m1 <= ~s1_a;
        s2_m2 <= ~(s1_a <<< 1);

        s2_t0 <= s1_b[2:0];
        s2_t1 <= s1_b[4:2];
        s2_t2 <= s1_b[6:4];
        s2_t3 <= s1_b[8:6];
        s2_t4 <= s1_b[10:8];

        for (i=0; i<5; i=i+1) begin
            s2_neg[i] <= s1_b[2*i+2] & ~(s1_b[2*i+1] & s1_b[2*i]);
        end

        // --- S3: Selection (10 bits - Caminho Crítico Otimizado) ---
        s3_v   <= s2_v;
        s3_neg <= s2_neg;

        // Mux 0
        case (s2_t0)
            3'b001, 3'b010: s3_pp[0] <= s2_p1;
            3'b011:         s3_pp[0] <= s2_p2;
            3'b100:         s3_pp[0] <= s2_m2;
            3'b101, 3'b110: s3_pp[0] <= s2_m1;
            default:        s3_pp[0] <= 10'sh0;
        endcase
        // Mux 1
        case (s2_t1)
            3'b001, 3'b010: s3_pp[1] <= s2_p1;
            3'b011:         s3_pp[1] <= s2_p2;
            3'b100:         s3_pp[1] <= s2_m2;
            3'b101, 3'b110: s3_pp[1] <= s2_m1;
            default:        s3_pp[1] <= 10'sh0;
        endcase
        // Mux 2
        case (s2_t2)
            3'b001, 3'b010: s3_pp[2] <= s2_p1;
            3'b011:         s3_pp[2] <= s2_p2;
            3'b100:         s3_pp[2] <= s2_m2;
            3'b101, 3'b110: s3_pp[2] <= s2_m1;
            default:        s3_pp[2] <= 10'sh0;
        endcase
        // Mux 3
        case (s2_t3)
            3'b001, 3'b010: s3_pp[3] <= s2_p1;
            3'b011:         s3_pp[3] <= s2_p2;
            3'b100:         s3_pp[3] <= s2_m2;
            3'b101, 3'b110: s3_pp[3] <= s2_m1;
            default:        s3_pp[3] <= 10'sh0;
        endcase
        // Mux 4
        case (s2_t4)
            3'b001, 3'b010: s3_pp[4] <= s2_p1;
            3'b011:         s3_pp[4] <= s2_p2;
            3'b100:         s3_pp[4] <= s2_m2;
            3'b101, 3'b110: s3_pp[4] <= s2_m1;
            default:        s3_pp[4] <= 10'sh0;
        endcase

        // --- S4: Extensão Manual + Soma (20 bits) ---
        s4_v     <= s3_v;
        // Extensão de sinal manual + Shift via concatenação
        s4_sum01 <= { {10{s3_pp[0][9]}}, s3_pp[0] } +
                    { {8{s3_pp[1][9]}}, s3_pp[1], 2'b00 };

        s4_sum23 <= { {6{s3_pp[2][9]}}, s3_pp[2], 4'b0000 } +
                    { {4{s3_pp[3][9]}}, s3_pp[3], 6'b000000 };

        s4_pp4   <= { {2{s3_pp[4][9]}}, s3_pp[4], 8'b00000000 };

        s4_corr  <= (s3_neg[0]) + (s3_neg[1] << 2) + (s3_neg[2] << 4) +
                    (s3_neg[3] << 6) + (s3_neg[4] << 8);

        // --- S5: Soma Nível 2 ---
        s5_v    <= s4_v;
        s5_sumA <= s4_sum01 + s4_sum23;
        s5_sumB <= s4_pp4 + s4_corr;

        // --- S6: Saída ---
        v_out <= s5_v;
        p     <= (s5_sumA + s5_sumB);
    end
endmodule
`default_nettype wire
