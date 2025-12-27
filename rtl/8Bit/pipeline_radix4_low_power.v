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

    //==========================================================================
    // ESTÁGIO 1: Extensão de Operandos com Clock Gating
    //==========================================================================
    reg signed [9:0]  s1_a;
    reg        [10:0] s1_b;
    reg               s1_v;

    // Clock gating: apenas atualiza quando v_in = 1
    always @(posedge clk) begin
        s1_v <= v_in;
        
        if (v_in) begin
            s1_a <= sm[1] ? $signed({{2{a[7]}}, a}) : $signed({2'b00, a});
            s1_b <= {(sm[0] ? {2{b[7]}} : 2'b00), b, 1'b0};
        end
        // Quando v_in=0, registros mantêm valor (sem toggle desnecessário)
    end

    //==========================================================================
    // ESTÁGIO 2: Decodificação Booth com Gating
    //==========================================================================
    reg signed [9:0]  s2_p1, s2_p2;
    reg [4:0]         s2_sel1x, s2_sel2x, s2_neg;
    reg               s2_v;

    integer i;
    always @(posedge clk) begin
        s2_v <= s1_v;
        
        if (s1_v) begin
            s2_p1 <= s1_a;
            s2_p2 <= s1_a << 1;

            for (i = 0; i < 5; i = i + 1) begin
                s2_sel1x[i] <= s1_b[2*i] ^ s1_b[2*i+1];
                s2_sel2x[i] <= (s1_b[2*i+2] ^ s1_b[2*i+1]) & ~(s1_b[2*i+1] ^ s1_b[2*i]);
                s2_neg[i]   <= s1_b[2*i+2];
            end
        end
    end

    //==========================================================================
    // ESTÁGIO 3: Produtos Parciais com Gating
    //==========================================================================
    reg [9:0] s3_pp0, s3_pp1, s3_pp2, s3_pp3;
    reg [7:0] s3_pp4;
    reg [4:0] s3_neg;
    reg       s3_v;

    always @(posedge clk) begin
        s3_v <= s2_v;
        
        if (s2_v) begin
            s3_neg <= s2_neg;
            s3_pp0 <= ({10{s2_sel1x[0]}} & s2_p1 | {10{s2_sel2x[0]}} & s2_p2) ^ {10{s2_neg[0]}};
            s3_pp1 <= ({10{s2_sel1x[1]}} & s2_p1 | {10{s2_sel2x[1]}} & s2_p2) ^ {10{s2_neg[1]}};
            s3_pp2 <= ({10{s2_sel1x[2]}} & s2_p1 | {10{s2_sel2x[2]}} & s2_p2) ^ {10{s2_neg[2]}};
            s3_pp3 <= ({10{s2_sel1x[3]}} & s2_p1 | {10{s2_sel2x[3]}} & s2_p2) ^ {10{s2_neg[3]}};
            s3_pp4 <= ({8{s2_sel1x[4]}} & s2_p1[7:0] | {8{s2_sel2x[4]}} & s2_p2[7:0]) ^ {8{s2_neg[4]}};
        end
    end

    //==========================================================================
    // ESTÁGIO 4: Primeira Redução com Gating
    //==========================================================================
    reg signed [15:0] s4_sum01;
    reg signed [15:0] s4_sum23;
    reg signed [15:0] s4_pp4_ext;
    reg [4:0]         s4_neg;
    reg               s4_v;

    always @(posedge clk) begin
        s4_v <= s3_v;
        
        if (s3_v) begin
            s4_neg <= s3_neg;
            
            s4_sum01 <= $signed({{6{s3_pp0[9]}}, s3_pp0}) + 
                        $signed({{4{s3_pp1[9]}}, s3_pp1, 2'b00});
            
            s4_sum23 <= $signed({{2{s3_pp2[9]}}, s3_pp2, 4'b0000}) + 
                        $signed({s3_pp3, 6'b000000});
            
            s4_pp4_ext <= $signed({s3_pp4, 8'b00000000});
        end
    end

    //==========================================================================
    // ESTÁGIO 5: Segunda Redução com Gating
    //==========================================================================
    reg signed [15:0] s5_sum0123;
    reg signed [15:0] s5_pp4_corr;
    reg               s5_v;

    always @(posedge clk) begin
        s5_v <= s4_v;
        
        if (s4_v) begin
            s5_sum0123 <= s4_sum01 + s4_sum23;
            
            s5_pp4_corr <= s4_pp4_ext + 
                           $signed({7'b0000000, s4_neg[4], 1'b0, s4_neg[3], 1'b0, 
                                    s4_neg[2], 1'b0, s4_neg[1], 1'b0, s4_neg[0]});
        end
    end

    //==========================================================================
    // ESTÁGIO 6: Soma Final com Gating
    //==========================================================================
    always @(posedge clk) begin
        v_out <= s5_v;
        
        if (s5_v) begin
            p <= s5_sum0123 + s5_pp4_corr;
        end
    end

endmodule

`default_nettype wire
