`timescale 1ns / 1ps
`default_nettype none

module booth_mult8_pipeline_opt (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire signed [7:0]     multiplicand,
    input  wire signed [7:0]     multiplier,
    input  wire [1:0]            sign_mode,
    output reg signed [15:0]     product
);

    // ========================================================================
    // ESTÁGIO 1: Pré-cálculo (Mantido)
    // ========================================================================
    localparam EXT_A_WIDTH = 12; 
    
    reg signed [EXT_A_WIDTH-1:0] r1_A_1x;
    reg signed [EXT_A_WIDTH-1:0] r1_A_3x;
    reg        [10:0]            r1_B_coded; 
    
    wire s_bit_a = sign_mode[1] & multiplicand[7];
    wire s_bit_b = sign_mode[0] & multiplier[7];
    wire signed [EXT_A_WIDTH-1:0] A_ext = { {(EXT_A_WIDTH-8){s_bit_a}}, multiplicand };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_A_1x    <= 0;
            r1_A_3x    <= 0;
            r1_B_coded <= 0;
        end else begin
            r1_A_1x <= A_ext;
            r1_A_3x <= A_ext + (A_ext <<< 1);
            r1_B_coded <= { s_bit_b, s_bit_b, multiplier, 1'b0 };
        end
    end

    // ========================================================================
    // ESTÁGIO 2: Geração de PPs (PURAMENTE LÓGICO - SEM SOMA)
    // ========================================================================
    // Separa o valor (1's complement) do bit de ajuste (+1)
    
    reg signed [15:0] r2_pp0_val;
    reg signed [15:0] r2_pp1_val;
    reg signed [15:0] r2_pp2_val;
    reg               r2_inv0, r2_inv1, r2_inv2;

    // Função modificada: Retorna apenas o XOR, sem somar o carry
    function signed [15:0] get_booth_val (
        input [3:0]                  group_bits,
        input signed [EXT_A_WIDTH-1:0] in_1x,
        input signed [EXT_A_WIDTH-1:0] in_3x
    );
        reg sel_1x, sel_2x, sel_3x, sel_4x;
        reg [2:0] recoded;
        reg signed [EXT_A_WIDTH-1:0] mag;
        reg inv;
        reg signed [15:0] mag_extended; 
    begin
        recoded = group_bits[2:0] ^ {3{group_bits[3]}};
        inv     = group_bits[3] & ~(&group_bits[2:0]); 

        sel_1x = (recoded == 3'b001 || recoded == 3'b010);
        sel_2x = (recoded == 3'b011 || recoded == 3'b100);
        sel_3x = (recoded == 3'b101 || recoded == 3'b110);
        sel_4x = (recoded == 3'b111);

        mag = ({EXT_A_WIDTH{sel_1x}} & in_1x) |
              ({EXT_A_WIDTH{sel_2x}} & (in_1x <<< 1)) |
              ({EXT_A_WIDTH{sel_3x}} & in_3x) |
              ({EXT_A_WIDTH{sel_4x}} & (in_1x <<< 2));

        mag_extended = mag; // Sign extension ocorre aqui
        
        // AQUI ESTÁ A OTIMIZAÇÃO: Apenas XOR. A soma acontece no próximo clock.
        get_booth_val = mag_extended ^ {16{inv}};
    end
    endfunction
    
    // Função auxiliar para extrair apenas o bit de inversão
    function get_booth_inv (input [3:0] group_bits);
        get_booth_inv = group_bits[3] & ~(&group_bits[2:0]);
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r2_pp0_val <= 0; r2_inv0 <= 0;
            r2_pp1_val <= 0; r2_inv1 <= 0;
            r2_pp2_val <= 0; r2_inv2 <= 0;
        end else begin
            r2_pp0_val <= get_booth_val(r1_B_coded[3:0], r1_A_1x, r1_A_3x);
            r2_inv0    <= get_booth_inv(r1_B_coded[3:0]);

            r2_pp1_val <= get_booth_val(r1_B_coded[6:3], r1_A_1x, r1_A_3x);
            r2_inv1    <= get_booth_inv(r1_B_coded[6:3]);

            r2_pp2_val <= get_booth_val(r1_B_coded[9:6], r1_A_1x, r1_A_3x);
            r2_inv2    <= get_booth_inv(r1_B_coded[9:6]);
        end
    end

    // ========================================================================
    // ESTÁGIO 3: Árvore de Soma Balanceada
    // ========================================================================
    // Caminho A: PP0 + PP1
    // Caminho B: PP2 + Bits de Correção (Hot Bits)
    
    reg signed [15:0] r3_sum_A;
    reg signed [15:0] r3_sum_B;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r3_sum_A <= 0;
            r3_sum_B <= 0;
        end else begin
            // Adder 1
            r3_sum_A <= r2_pp0_val + (r2_pp1_val <<< 3);
            
            // Adder 2: Soma o PP2 com o vetor formado pelos bits de inversão
            // inv0 na pos 0, inv1 na pos 3, inv2 na pos 6
            r3_sum_B <= (r2_pp2_val <<< 6) + 
                        { 9'b0, r2_inv2, 2'b0, r2_inv1, 2'b0, r2_inv0 };
        end
    end

    // ========================================================================
    // ESTÁGIO 4: Soma Final
    // ========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product <= 16'sd0;
        end else begin
            // Adder 3 (Final)
            product <= r3_sum_A + r3_sum_B;
        end
    end

endmodule
`default_nettype wire
