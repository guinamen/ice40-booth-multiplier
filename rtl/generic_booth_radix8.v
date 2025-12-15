`timescale 1ns / 1ps
`default_nettype none

module booth_mult_generic #(
    parameter integer WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire signed [WIDTH-1:0] multiplicand,
    input  wire signed [WIDTH-1:0] multiplier,
    input  wire [1:0]            sign_mode,
    output reg signed [(2*WIDTH)-1:0] product
);

    // ========================================================================
    // CONSTANTES
    // ========================================================================
    localparam integer NUM_PPS = (WIDTH + 3) / 3;
    localparam integer EXT_A_WIDTH = WIDTH + 4; 
    localparam integer OUT_WIDTH = 2 * WIDTH;

    // ========================================================================
    // ESTÁGIO 1: Pré-cálculo 3A
    // ========================================================================
    reg signed [EXT_A_WIDTH-1:0] r1_A_1x;
    reg signed [EXT_A_WIDTH-1:0] r1_A_3x;
    reg [(NUM_PPS*3)+3:0]        r1_B_coded; 

    wire s_bit_a = sign_mode[1] & multiplicand[WIDTH-1];
    wire s_bit_b = sign_mode[0] & multiplier[WIDTH-1];
    wire signed [EXT_A_WIDTH-1:0] A_ext = { {(EXT_A_WIDTH-WIDTH){s_bit_a}}, multiplicand };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r1_A_1x    <= 0;
            r1_A_3x    <= 0;
            r1_B_coded <= 0;
        end else begin
            r1_A_1x <= A_ext;
            r1_A_3x <= A_ext + (A_ext <<< 1);
            r1_B_coded <= { {(NUM_PPS*3 - WIDTH + 4){s_bit_b}}, multiplier, 1'b0 };
        end
    end

    // ========================================================================
    // ESTÁGIO 2: Geração PPs + Vetor de Correção
    // ========================================================================
    // Tratamos o conjunto de bits '+1' (inversão) como um vetor extra a ser somado.
    
    // Total de itens para somar = NUM_PPS + 1 (Vetor de Correção)
    localparam integer NUM_ITEMS_L0 = NUM_PPS + 1;
    
    reg signed [OUT_WIDTH-1:0] r2_items [0:NUM_ITEMS_L0-1];

    function signed [OUT_WIDTH-1:0] get_booth_val (
        input [3:0] group_bits,
        input signed [EXT_A_WIDTH-1:0] in_1x,
        input signed [EXT_A_WIDTH-1:0] in_3x,
        input integer shift_amount
    );
        reg sel_1x, sel_2x, sel_3x, sel_4x;
        reg [2:0] recoded;
        reg signed [EXT_A_WIDTH-1:0] mag;
        reg inv;
        reg signed [OUT_WIDTH-1:0] mag_shifted;
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
        mag_shifted = mag; 
        // Apenas XOR, o +1 vai pro vetor de correção
        get_booth_val = (mag_shifted ^ {OUT_WIDTH{inv}}) <<< shift_amount;
    end
    endfunction
    
    function get_booth_inv (input [3:0] group_bits);
        get_booth_inv = group_bits[3] & ~(&group_bits[2:0]);
    endfunction

    integer i;
    reg [OUT_WIDTH-1:0] correction_accum;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<NUM_ITEMS_L0; i=i+1) r2_items[i] <= 0;
        end else begin
            // 1. Gera os PPs normais
            correction_accum = 0;
            for (i=0; i<NUM_PPS; i=i+1) begin
                r2_items[i] <= get_booth_val(r1_B_coded[i*3 +: 4], r1_A_1x, r1_A_3x, i*3);
                
                // Monta o vetor de correção (Hot Bits)
                if (get_booth_inv(r1_B_coded[i*3 +: 4]))
                    correction_accum = correction_accum | (1'b1 <<< (i*3));
            end
            // 2. O último item é o vetor de correção
            r2_items[NUM_PPS] <= correction_accum;
        end
    end

    // ========================================================================
    // ARVORE DE SOMA BINARIA (PIPELINED)
    // ========================================================================
    // A cada estágio, o número de itens cai pela metade.
    // Usamos 'generate' ou constantes fixas? Para manter genérico, vamos usar 
    // arrays fixos grandes o suficiente e lógica "generate-like" procedural.
    
    // Definição dos Níveis da Árvore (Suporta até ~32 PPs -> 128 bits width)
    localparam CNT_L1 = (NUM_ITEMS_L0 + 1) / 2;
    localparam CNT_L2 = (CNT_L1 + 1) / 2;
    localparam CNT_L3 = (CNT_L2 + 1) / 2;
    localparam CNT_L4 = (CNT_L3 + 1) / 2; // Final

    reg signed [OUT_WIDTH-1:0] r_tree_L1 [0:CNT_L1-1];
    reg signed [OUT_WIDTH-1:0] r_tree_L2 [0:CNT_L2-1];
    reg signed [OUT_WIDTH-1:0] r_tree_L3 [0:CNT_L3-1];
    reg signed [OUT_WIDTH-1:0] r_tree_L4 [0:CNT_L4-1]; // Deve ser 1 item aqui se <= 16 PPs iniciais

    integer k;

    // ESTÁGIO 3: Nível 1 da Árvore
    always @(posedge clk) begin
        for (k=0; k<CNT_L1; k=k+1) begin
            if (k*2 + 1 < NUM_ITEMS_L0)
                r_tree_L1[k] <= r2_items[k*2] + r2_items[k*2 + 1];
            else // Sobra um ímpar
                r_tree_L1[k] <= r2_items[k*2];
        end
    end

    // ESTÁGIO 4: Nível 2 da Árvore
    always @(posedge clk) begin
        for (k=0; k<CNT_L2; k=k+1) begin
            if (k*2 + 1 < CNT_L1)
                r_tree_L2[k] <= r_tree_L1[k*2] + r_tree_L1[k*2 + 1];
            else
                r_tree_L2[k] <= r_tree_L1[k*2];
        end
    end

    // ESTÁGIO 5: Nível 3 da Árvore
    always @(posedge clk) begin
        for (k=0; k<CNT_L3; k=k+1) begin
            if (k*2 + 1 < CNT_L2)
                r_tree_L3[k] <= r_tree_L2[k*2] + r_tree_L2[k*2 + 1];
            else
                r_tree_L3[k] <= r_tree_L2[k*2];
        end
    end

    // ESTÁGIO 6: Nível 4 da Árvore (Para 32-bit width, isso finaliza em 1 item)
    // Se WIDTH for enorme (64 bits), talvez precise de mais um estágio, mas 
    // para 32 bits (12 itens iniciais), L4 terá apenas 1 item.
    always @(posedge clk) begin
        for (k=0; k<CNT_L4; k=k+1) begin
            if (k*2 + 1 < CNT_L3)
                r_tree_L4[k] <= r_tree_L3[k*2] + r_tree_L3[k*2 + 1];
            else
                r_tree_L4[k] <= r_tree_L3[k*2];
        end
    end

    // ========================================================================
    // SAÍDA
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) product <= 0;
        else        product <= r_tree_L4[0];
    end

endmodule
`default_nettype wire
