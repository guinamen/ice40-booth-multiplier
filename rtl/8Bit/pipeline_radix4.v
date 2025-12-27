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
    // ESTÁGIO 1: Extensão de Operandos
    //==========================================================================
    reg signed [9:0]  s1_a;      
    reg        [10:0] s1_b;      
    reg               s1_v;      
    
    always @(posedge clk) begin
        s1_a <= sm[1] ? $signed({{2{a[7]}}, a}) : $signed({2'b00, a});
        s1_b <= {(sm[0] ? {2{b[7]}} : 2'b00), b, 1'b0};
        s1_v <= v_in;
    end
    
    //==========================================================================
    // ESTÁGIO 2: Decodificação Booth
    //==========================================================================
    reg signed [9:0]  s2_p1, s2_p2;     
    reg [4:0]         s2_sel1x, s2_sel2x, s2_neg;    
    reg               s2_v;      
    
    always @(posedge clk) begin
        s2_v  <= s1_v;
        s2_p1 <= s1_a;           
        s2_p2 <= s1_a << 1;      
        
        s2_sel1x[0] <= s1_b[0] ^ s1_b[1];
        s2_sel2x[0] <= (s1_b[2] ^ s1_b[1]) & ~(s1_b[1] ^ s1_b[0]);
        s2_neg[0]   <= s1_b[2];
        
        s2_sel1x[1] <= s1_b[2] ^ s1_b[3];
        s2_sel2x[1] <= (s1_b[4] ^ s1_b[3]) & ~(s1_b[3] ^ s1_b[2]);
        s2_neg[1]   <= s1_b[4];
        
        s2_sel1x[2] <= s1_b[4] ^ s1_b[5];
        s2_sel2x[2] <= (s1_b[6] ^ s1_b[5]) & ~(s1_b[5] ^ s1_b[4]);
        s2_neg[2]   <= s1_b[6];
        
        s2_sel1x[3] <= s1_b[6] ^ s1_b[7];
        s2_sel2x[3] <= (s1_b[8] ^ s1_b[7]) & ~(s1_b[7] ^ s1_b[6]);
        s2_neg[3]   <= s1_b[8];
        
        s2_sel1x[4] <= s1_b[8] ^ s1_b[9];
        s2_sel2x[4] <= (s1_b[10] ^ s1_b[9]) & ~(s1_b[9] ^ s1_b[8]);
        s2_neg[4]   <= s1_b[10];
    end
    
    //==========================================================================
    // ESTÁGIO 3: Produtos Parciais
    //==========================================================================
    /* verilator lint_off UNUSED */
    reg [9:0] s3_pp0, s3_pp1, s3_pp2, s3_pp3, s3_pp4;
    /* verilator lint_on UNUSED */
    reg [4:0] s3_neg;    
    reg       s3_v;      
    
    always @(posedge clk) begin
        s3_v   <= s2_v;
        s3_neg <= s2_neg;
        s3_pp0 <= (({10{s2_sel1x[0]}} & s2_p1) | ({10{s2_sel2x[0]}} & s2_p2)) ^ {10{s2_neg[0]}};
        s3_pp1 <= (({10{s2_sel1x[1]}} & s2_p1) | ({10{s2_sel2x[1]}} & s2_p2)) ^ {10{s2_neg[1]}};
        s3_pp2 <= (({10{s2_sel1x[2]}} & s2_p1) | ({10{s2_sel2x[2]}} & s2_p2)) ^ {10{s2_neg[2]}};
        s3_pp3 <= (({10{s2_sel1x[3]}} & s2_p1) | ({10{s2_sel2x[3]}} & s2_p2)) ^ {10{s2_neg[3]}};
        s3_pp4 <= (({10{s2_sel1x[4]}} & s2_p1) | ({10{s2_sel2x[4]}} & s2_p2)) ^ {10{s2_neg[4]}};
    end
    
    //==========================================================================
    // ESTÁGIO 4: Redução 1 (Árvore de Soma)
    //==========================================================================
    reg signed [15:0] s4_sum01;     
    reg signed [15:0] s4_sum23;     
    reg signed [15:0] s4_pp4_corr;  
    reg               s4_v;         

    /* verilator lint_off WIDTH */
    always @(posedge clk) begin
        s4_v <= s3_v;
        
        // Somas truncadas explicitamente para 16 bits para iCE40
        s4_sum01 <= $signed({{6{s3_pp0[9]}}, s3_pp0}) + 
                    $signed({{4{s3_pp1[9]}}, s3_pp1, 2'b00});
        
        s4_sum23 <= $signed({{2{s3_pp2[9]}}, s3_pp2, 4'b0000}) + 
                    $signed({s3_pp3, 6'b000000});
        
        // Aqui os bits 8 e 9 de s3_pp4 são usados na soma, mas o resultado
        // é truncado para 16 bits. O pragma acima silencia o aviso de WIDTH.
        s4_pp4_corr <= $signed({s3_pp4, 8'b0}) + 
                       $signed({13'b0, s3_neg[4], 1'b0, s3_neg[3], 1'b0, 
                               s3_neg[2], 1'b0, s3_neg[1], 1'b0, s3_neg[0]});
    end
    /* verilator lint_on WIDTH */
    
    //==========================================================================
    // ESTÁGIO 5 e 6: Soma Final
    //==========================================================================
    reg signed [15:0] s5_sumA, s5_sumB;   
    reg               s5_v;      
    
    always @(posedge clk) begin
        s5_v    <= s4_v;
        s5_sumA <= s4_sum01 + s4_sum23;
        s5_sumB <= s4_pp4_corr;
    end
    
    always @(posedge clk) begin
        v_out <= s5_v;
        p     <= s5_sumA + s5_sumB;
    end

endmodule
