`timescale 1ns / 1ps
`default_nettype none

/*
 * ============================================================================
 * Módulo: booth_mult8_fastest_gold
 * Arquitetura: Radix-4 Booth Pipelined
 * Estratégia: "Invert-and-Add" (Zero Carry Delay na entrada)
 * Latência: 6 Ciclos
 * Frequência Alvo: > 250 MHz (Lattice iCE40)
 * ============================================================================
 */

module booth_mult8_fastest_gold #(
    parameter integer WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  valid_in,
    input  wire signed [WIDTH-1:0] multiplicand,
    input  wire signed [WIDTH-1:0] multiplier,
    input  wire [1:0]            sign_mode, // [1]=Signed Mcand, [0]=Signed Mult
    
    output reg  signed [(2*WIDTH)-1:0] product,
    output reg                   valid_out
);

    // ------------------------------------------------------------------------
    // DEFINIÇÃO DE LARGURAS
    // ------------------------------------------------------------------------
    // OP_W: 10 bits. 
    // Necessário para acomodar o maior negativo (-128) e a operação 2x sem overflow
    // e também para converter Unsigned (255) em Signed positivo (0_1111_1111).
    localparam OP_W  = WIDTH + 2; 
    
    // SUM_W: 24 bits.
    // O resultado final é 16 bits, mas as somas parciais precisam de "guard bits"
    // para evitar overflow intermediário antes da redução final.
    localparam SUM_W = (2 * WIDTH) + 8;

    // ------------------------------------------------------------------------
    // FUNÇÕES AUXILIARES
    // ------------------------------------------------------------------------
    function automatic [2:0] f_booth_enc;
        input [2:0] code;
    begin
        // Decodificador Booth Radix-4 Padrão
        case (code)
            3'b000: f_booth_enc = 3'b000; //  0
            3'b001: f_booth_enc = 3'b001; // +1
            3'b010: f_booth_enc = 3'b001; // +1
            3'b011: f_booth_enc = 3'b011; // +2
            3'b100: f_booth_enc = 3'b100; // -2
            3'b101: f_booth_enc = 3'b010; // -1
            3'b110: f_booth_enc = 3'b010; // -1
            3'b111: f_booth_enc = 3'b000; // -0
            default: f_booth_enc = 3'b000;
        endcase
    end
    endfunction

    // ------------------------------------------------------------------------
    // ESTÁGIO 1: Registro de Entrada e Extensão de Sinal
    // ------------------------------------------------------------------------
    reg signed [OP_W-1:0] s1_a_reg, s1_b_reg;
    reg s1_valid;
    reg signed [OP_W-1:0] w_a_ext, w_b_ext;

    always @* begin
        // Extensão Inteligente:
        // Se Signed: Repete o bit de sinal.
        // Se Unsigned: Preenche com zeros à esquerda.
        if (sign_mode[1]) w_a_ext = { {2{multiplicand[WIDTH-1]}}, multiplicand };
        else              w_a_ext = { 2'b00, multiplicand };

        if (sign_mode[0]) w_b_ext = { {2{multiplier[WIDTH-1]}}, multiplier };
        else              w_b_ext = { 2'b00, multiplier };
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin s1_a_reg <= 0; s1_b_reg <= 0; s1_valid <= 0; end
        else begin
            s1_valid <= valid_in;
            s1_a_reg <= w_a_ext;
            s1_b_reg <= w_b_ext;
        end
    end

    // ------------------------------------------------------------------------
    // ESTÁGIO 2: Pré-Cálculo Otimizado (Zero Carry Delay)
    // ------------------------------------------------------------------------
    // Em vez de calcular -A (que exige somar 1 e propagar carry),
    // calculamos apenas ~A (inversão bit a bit). O "+1" é somado lá no final.
    
    // Duplicação de registros (LO/HI) para reduzir Fan-Out e ajudar o Roteador
    reg signed [OP_W-1:0] s2_a_lo, s2_inv_a_lo, s2_2a_lo, s2_inv_2a_lo;
    reg signed [OP_W-1:0] s2_a_hi, s2_inv_a_hi, s2_2a_hi, s2_inv_2a_hi;

    // Sinais de Controle "One-Hot" (Decodificados agora para simplificar o próximo estágio)
    reg [3:0] s2_sel_p1; // Select +1A
    reg [3:0] s2_sel_m1; // Select ~1A
    reg [3:0] s2_sel_p2; // Select +2A
    reg [3:0] s2_sel_m2; // Select ~2A
    
    // Bits de Correção: Se a operação for negativa, precisamos somar +1 depois
    reg [4:0] s2_neg_bit; 

    // Sinais dedicados ao Produto Parcial 4 (PP4)
    reg s2_sel_p1_pp4, s2_sel_m1_pp4, s2_sel_p2_pp4, s2_sel_m2_pp4;

    reg s2_valid;
    wire [10:0] w_b_vec = {s1_b_reg, 1'b0}; // Vetor B com zero implícito
    reg [2:0] w_c0, w_c1, w_c2, w_c3, w_c4;

    always @* begin
        // Booth Encoding (Combinacional rápido)
        w_c0 = f_booth_enc(w_b_vec[2:0]);
        w_c1 = f_booth_enc(w_b_vec[4:2]);
        w_c2 = f_booth_enc(w_b_vec[6:4]);
        w_c3 = f_booth_enc(w_b_vec[8:6]);
        w_c4 = f_booth_enc(w_b_vec[10:8]);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_a_lo <= 0; s2_inv_a_lo <= 0; s2_2a_lo <= 0; s2_inv_2a_lo <= 0;
            s2_a_hi <= 0; s2_inv_a_hi <= 0; s2_2a_hi <= 0; s2_inv_2a_hi <= 0;
            s2_sel_p1 <= 0; s2_sel_m1 <= 0; s2_sel_p2 <= 0; s2_sel_m2 <= 0;
            s2_neg_bit <= 0;
            s2_sel_p1_pp4 <= 0; s2_sel_m1_pp4 <= 0; s2_sel_p2_pp4 <= 0; s2_sel_m2_pp4 <= 0;
            s2_valid <= 0;
        end else begin
            s2_valid <= s1_valid;

            // Operações Bitwise (Muito rápidas, sem carry)
            s2_a_lo <= s1_a_reg; s2_inv_a_lo <= ~s1_a_reg; s2_2a_lo <= s1_a_reg << 1; s2_inv_2a_lo <= ~(s1_a_reg << 1);
            s2_a_hi <= s1_a_reg; s2_inv_a_hi <= ~s1_a_reg; s2_2a_hi <= s1_a_reg << 1; s2_inv_2a_hi <= ~(s1_a_reg << 1);

            // Geração One-Hot e Bit de Correção
            // Grupo 0
            s2_sel_p1[0] <= (w_c0 == 3'b001); s2_sel_p2[0] <= (w_c0 == 3'b011);
            s2_sel_m1[0] <= (w_c0 == 3'b010); s2_sel_m2[0] <= (w_c0 == 3'b100);
            s2_neg_bit[0] <= (w_c0 == 3'b010) || (w_c0 == 3'b100);

            // Grupo 1
            s2_sel_p1[1] <= (w_c1 == 3'b001); s2_sel_p2[1] <= (w_c1 == 3'b011);
            s2_sel_m1[1] <= (w_c1 == 3'b010); s2_sel_m2[1] <= (w_c1 == 3'b100);
            s2_neg_bit[1] <= (w_c1 == 3'b010) || (w_c1 == 3'b100);

            // Grupo 2
            s2_sel_p1[2] <= (w_c2 == 3'b001); s2_sel_p2[2] <= (w_c2 == 3'b011);
            s2_sel_m1[2] <= (w_c2 == 3'b010); s2_sel_m2[2] <= (w_c2 == 3'b100);
            s2_neg_bit[2] <= (w_c2 == 3'b010) || (w_c2 == 3'b100);

            // Grupo 3
            s2_sel_p1[3] <= (w_c3 == 3'b001); s2_sel_p2[3] <= (w_c3 == 3'b011);
            s2_sel_m1[3] <= (w_c3 == 3'b010); s2_sel_m2[3] <= (w_c3 == 3'b100);
            s2_neg_bit[3] <= (w_c3 == 3'b010) || (w_c3 == 3'b100);

            // Grupo 4
            s2_sel_p1_pp4 <= (w_c4 == 3'b001); s2_sel_p2_pp4 <= (w_c4 == 3'b011);
            s2_sel_m1_pp4 <= (w_c4 == 3'b010); s2_sel_m2_pp4 <= (w_c4 == 3'b100);
            s2_neg_bit[4] <= (w_c4 == 3'b010) || (w_c4 == 3'b100);
        end
    end

    // ------------------------------------------------------------------------
    // ESTÁGIO 3: Seleção (AND-OR) e Montagem do Vetor de Correção
    // ------------------------------------------------------------------------
    reg signed [SUM_W-1:0] s3_pp0, s3_pp1, s3_pp2, s3_pp3, s3_pp4;
    reg [SUM_W-1:0] s3_correction; 
    reg s3_valid;
    
    reg signed [OP_W-1:0] w_pp0, w_pp1, w_pp2, w_pp3, w_pp4;

    always @* begin
        // Seleção via Lógica Booleana (Muito eficiente em LUTs de 4 entradas)
        // Grupo LO -> PP0, PP1
        w_pp0 = (s2_a_lo & {OP_W{s2_sel_p1[0]}}) | (s2_inv_a_lo & {OP_W{s2_sel_m1[0]}}) | 
                (s2_2a_lo & {OP_W{s2_sel_p2[0]}}) | (s2_inv_2a_lo & {OP_W{s2_sel_m2[0]}});
                
        w_pp1 = (s2_a_lo & {OP_W{s2_sel_p1[1]}}) | (s2_inv_a_lo & {OP_W{s2_sel_m1[1]}}) | 
                (s2_2a_lo & {OP_W{s2_sel_p2[1]}}) | (s2_inv_2a_lo & {OP_W{s2_sel_m2[1]}});

        // Grupo HI -> PP2, PP3, PP4
        w_pp2 = (s2_a_hi & {OP_W{s2_sel_p1[2]}}) | (s2_inv_a_hi & {OP_W{s2_sel_m1[2]}}) | 
                (s2_2a_hi & {OP_W{s2_sel_p2[2]}}) | (s2_inv_2a_hi & {OP_W{s2_sel_m2[2]}});
                
        w_pp3 = (s2_a_hi & {OP_W{s2_sel_p1[3]}}) | (s2_inv_a_hi & {OP_W{s2_sel_m1[3]}}) | 
                (s2_2a_hi & {OP_W{s2_sel_p2[3]}}) | (s2_inv_2a_hi & {OP_W{s2_sel_m2[3]}});
                
        w_pp4 = (s2_a_hi & {OP_W{s2_sel_p1_pp4}})| (s2_inv_a_hi & {OP_W{s2_sel_m1_pp4}})| 
                (s2_2a_hi & {OP_W{s2_sel_p2_pp4}})| (s2_inv_2a_hi & {OP_W{s2_sel_m2_pp4}});
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_pp0 <= 0; s3_pp1 <= 0; s3_pp2 <= 0; s3_pp3 <= 0; s3_pp4 <= 0; 
            s3_correction <= 0; s3_valid <= 0;
        end else begin
            s3_valid <= s2_valid;
            
            // Hardwired Shift: Apenas "fios", custo zero de lógica
            s3_pp0 <= w_pp0;
            s3_pp1 <= w_pp1 <<< 2;
            s3_pp2 <= w_pp2 <<< 4;
            s3_pp3 <= w_pp3 <<< 6;
            s3_pp4 <= w_pp4 <<< 8;

            // Vetor de Correção:
            // Consolida todos os bits "+1" em um único número para ser somado depois.
            // Os índices [0, 2, 4, 6, 8] correspondem ao LSB de cada PP deslocado.
            s3_correction <= 0; 
            s3_correction[0] <= s2_neg_bit[0]; 
            s3_correction[2] <= s2_neg_bit[1]; 
            s3_correction[4] <= s2_neg_bit[2]; 
            s3_correction[6] <= s2_neg_bit[3]; 
            s3_correction[8] <= s2_neg_bit[4]; 
        end
    end

    // ------------------------------------------------------------------------
    // ESTÁGIO 4: Árvore de Soma - Nível 1
    // ------------------------------------------------------------------------
    reg signed [SUM_W-1:0] s4_sumAB, s4_sumCD, s4_sumEF;
    reg s4_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_sumAB <= 0; s4_sumCD <= 0; s4_sumEF <= 0; s4_valid <= 0;
        end else begin
            s4_valid <= s3_valid;
            // Somando pares. 
            // O vetor de correção entra aqui como o 6º operando, "de carona" com PP4.
            s4_sumAB <= s3_pp0 + s3_pp1;
            s4_sumCD <= s3_pp2 + s3_pp3;
            s4_sumEF <= s3_pp4 + s3_correction; 
        end
    end

    // ------------------------------------------------------------------------
    // ESTÁGIO 5: Árvore de Soma - Nível 2
    // ------------------------------------------------------------------------
    reg signed [SUM_W-1:0] s5_total_AD, s5_pass_EF;
    reg s5_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5_total_AD <= 0; s5_pass_EF <= 0; s5_valid <= 0;
        end else begin
            s5_valid <= s4_valid;
            s5_total_AD <= s4_sumAB + s4_sumCD;
            s5_pass_EF  <= s4_sumEF;
        end
    end

    // ------------------------------------------------------------------------
    // ESTÁGIO 6: Soma Final (Caminho Crítico)
    // ------------------------------------------------------------------------
    reg signed [SUM_W-1:0] s6_final;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product   <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= s5_valid;
            if (s5_valid) begin
                // Soma de 24 bits usando a Carry Chain.
                // Como não há lógica combinacional complexa antes deste adder neste ciclo,
                // o sinal tem o período inteiro do clock para se propagar.
                s6_final = s5_total_AD + s5_pass_EF;
                product  <= s6_final[(2*WIDTH)-1:0];
            end
        end
    end

endmodule
`default_nettype wire
