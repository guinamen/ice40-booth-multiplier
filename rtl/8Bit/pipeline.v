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

    // S1: Normalização (Input Sampling)
    reg signed [9:0]  s1_a;
    reg        [10:0] s1_b;
    reg               s1_v;

    // S2: Booth Control Generation
    reg signed [9:0]  s2_p1, s2_p2;
    reg [4:0]         s2_sel1x, s2_sel2x, s2_neg;
    reg               s2_v;

    // S3: Bitwise Selection (O ponto mais rápido para o iCE40)
    reg [9:0]         s3_pp0, s3_pp1, s3_pp2, s3_pp3, s3_pp4;
    reg [4:0]         s3_neg;
    reg               s3_v;

    // S4: Nível de Soma 1 (Compressão parcial)
    reg signed [19:0] s4_sum01, s4_sum23, s4_pp4_corr;
    reg               s4_v;

    // S5: Nível de Soma 2 (Finalização da Árvore)
    reg signed [19:0] s5_sumA, s5_sumB;
    reg               s5_v;

    integer i;

    always @(posedge clk) begin
        // --- S1: Captura e Extensão ---
        s1_a <= sm[1] ? $signed({{2{a[7]}}, a}) : $signed({2'b00, a});
        s1_b <= { (sm[0] ? {2{b[7]}} : 2'b00), b, 1'b0 };
        s1_v <= v_in;

        // --- S2: Pré-cálculo de Controles ---
        s2_v  <= s1_v;
        s2_p1 <= s1_a;
        s2_p2 <= s1_a << 1;
        for (i=0; i<5; i=i+1) begin
            // Lógica de Booth Radix-4 decodificada em bits individuais
            s2_sel1x[i] <= s1_b[2*i] ^ s1_b[2*i+1];
            s2_sel2x[i] <= (s1_b[2*i+2] ^ s1_b[2*i+1]) & ~(s1_b[2*i+1] ^ s1_b[2*i]);
            s2_neg[i]   <= s1_b[2*i+2];
        end

        // --- S3: Mux Otimizado (XOR Inversion) ---
        s3_v   <= s2_v;
        s3_neg <= s2_neg;
        s3_pp0 <= ({10{s2_sel1x[0]}} & s2_p1 | {10{s2_sel2x[0]}} & s2_p2) ^ {10{s2_neg[0]}};
        s3_pp1 <= ({10{s2_sel1x[1]}} & s2_p1 | {10{s2_sel2x[1]}} & s2_p2) ^ {10{s2_neg[1]}};
        s3_pp2 <= ({10{s2_sel1x[2]}} & s2_p1 | {10{s2_sel2x[2]}} & s2_p2) ^ {10{s2_neg[2]}};
        s3_pp3 <= ({10{s2_sel1x[3]}} & s2_p1 | {10{s2_sel2x[3]}} & s2_p2) ^ {10{s2_neg[3]}};
        s3_pp4 <= ({10{s2_sel1x[4]}} & s2_p1 | {10{s2_sel2x[4]}} & s2_p2) ^ {10{s2_neg[4]}};

        // --- S4: Alinhamento e Soma Camada 1 ---
        s4_v <= s3_v;
        s4_sum01 <= $signed({{10{s3_pp0[9]}}, s3_pp0}) + $signed({{8{s3_pp1[9]}}, s3_pp1, 2'b00});
        s4_sum23 <= $signed({{6{s3_pp2[9]}}, s3_pp2, 4'b0000}) + $signed({{4{s3_pp3[9]}}, s3_pp3, 6'b000000});
        // Combina PP4 com o vetor de correção para economizar um somador no estágio final
        s4_pp4_corr <= $signed({{2{s3_pp4[9]}}, s3_pp4, 8'b00000000}) +
                       $signed({11'b0, s3_neg[4], 1'b0, s3_neg[3], 1'b0, s3_neg[2], 1'b0, s3_neg[1], 1'b0, s3_neg[0]});

        // --- S5: Camada 2 ---
        s5_v    <= s4_v;
        s5_sumA <= s4_sum01 + s4_sum23;
        s5_sumB <= s4_pp4_corr;

        // --- S6: Output Stage (Registro Final) ---
        v_out <= s5_v;
        p     <= (s5_sumA + s5_sumB);
    end

endmodule
