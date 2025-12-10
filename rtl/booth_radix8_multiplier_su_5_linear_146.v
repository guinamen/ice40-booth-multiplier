`timescale 1ns / 1ps
`default_nettype none
// ============================================================================
// Module: booth_mult8
// Description: Multiplicador Booth Radix-8 (8-bit) - 5 ciclos
// Optimization: Flattened Control Mux (Alta Frequência / Baixa Área)
// ============================================================================
module booth_mult8 (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire signed [7:0]     multiplicand,
    input  wire signed [7:0]     multiplier,
    input  wire [1:0]            sign_mode,
    output wire signed [15:0]    product,
    output wire                  done
);
    localparam integer WIDTH = 8;
    localparam integer SHIFT_BITS = 9;
    localparam integer ACC_WIDTH = 11;
    localparam integer REG_WIDTH = 21;

    reg active;
    reg signed [REG_WIDTH-1:0] prod_reg;
    reg [3:0] iter_shift;

    // Buffers de Setup (Mantidos mínimos para reduzir roteamento)
    reg signed [ACC_WIDTH-1:0] m_3x_reg;
    reg signed [ACC_WIDTH-1:0] mcand_ext_reg;

    // ------------------------------------------------------------------------
    // SETUP (Ciclo 1) - Caminho isolado
    // ------------------------------------------------------------------------
    wire sign_bit_a = sign_mode[1] & multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){sign_bit_a}}, multiplicand };

    // Pré-cálculo do 3x (Adder dedicado fora do loop principal)
    wire signed [ACC_WIDTH-1:0] calc_3x = mcand_extended + (mcand_extended <<< 1);

    wire sign_bit_b = sign_mode[0] & multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},
        {(SHIFT_BITS-WIDTH){sign_bit_b}},
        multiplier,
        1'b0
    };

    // ------------------------------------------------------------------------
    // BOOTH LOGIC (Ciclos 2-4) - Caminho Crítico Otimizado
    // ------------------------------------------------------------------------
    wire [3:0] booth_bits = prod_reg[3:0];
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    // Cálculo Paralelo dos Sinais de Seleção (Reduz profundidade lógica)
    reg sel_1x, sel_2x, sel_3x, sel_4x;
    always @(*) begin
        // Mapeia casos positivos e negativos para a magnitude absoluta
        sel_1x = (booth_bits == 4'b0001) || (booth_bits == 4'b0010) ||
                 (booth_bits == 4'b1101) || (booth_bits == 4'b1110);

        sel_2x = (booth_bits == 4'b0011) || (booth_bits == 4'b0100) ||
                 (booth_bits == 4'b1011) || (booth_bits == 4'b1100);

        sel_3x = (booth_bits == 4'b0101) || (booth_bits == 4'b0110) ||
                 (booth_bits == 4'b1001) || (booth_bits == 4'b1010);

        sel_4x = (booth_bits == 4'b0111) || (booth_bits == 4'b1000);
    end

    // Detecção rápida de inversão (Carry-In do subtrator)
    wire inv = booth_bits[3] & ~(&booth_bits[2:0]);

    // Múltiplos (Shifts são apenas fios/roteamento)
    wire signed [ACC_WIDTH-1:0] m_1x = mcand_ext_reg;
    wire signed [ACC_WIDTH-1:0] m_2x = mcand_ext_reg <<< 1;
    wire signed [ACC_WIDTH-1:0] m_4x = mcand_ext_reg <<< 2;

    // Mux "Achatado" (Combina seleção e dados em 1 nível de LUTs)
    reg signed [ACC_WIDTH-1:0] mag_sel;
    always @(*) begin
        mag_sel = ({ACC_WIDTH{sel_1x}} & m_1x) |
                  ({ACC_WIDTH{sel_2x}} & m_2x) |
                  ({ACC_WIDTH{sel_3x}} & m_3x_reg) |
                  ({ACC_WIDTH{sel_4x}} & m_4x);
    end

    // Soma Final: Inversão via XOR + Soma (Carry Chain)
    wire signed [ACC_WIDTH-1:0] operand_inv = mag_sel ^ {ACC_WIDTH{inv}};
    wire signed [ACC_WIDTH-1:0] sum_result  = acc_upper + operand_inv + { {(ACC_WIDTH-1){1'b0}}, inv };

    // ------------------------------------------------------------------------
    // Lógica Sequencial
    // ------------------------------------------------------------------------
    assign done = iter_shift[0] && active;
    assign product = prod_reg[16:1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active         <= 1'b0;
            iter_shift     <= 4'b0;
            prod_reg       <= {REG_WIDTH{1'b0}};
            m_3x_reg       <= {ACC_WIDTH{1'b0}};
            mcand_ext_reg  <= {ACC_WIDTH{1'b0}};
        end else begin
            if (active) begin
                if (iter_shift[0]) begin
                    active <= 1'b0;
                end else begin
                    // Shift Aritmético e atualização
                    prod_reg   <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
                    iter_shift <= iter_shift >> 1;
                end
            end else if (start) begin
                active        <= 1'b1;
                iter_shift    <= 4'b1000;
                mcand_ext_reg <= mcand_extended;
                m_3x_reg      <= calc_3x;
                prod_reg      <= prod_reg_init;
            end
        end
    end
endmodule

// ============================================================================
// Module: booth_radix8_multiplier (Top Level)
// Optimization: Split Adder Tree (18-bit Intermediate + 24-bit Final)
// ============================================================================
module booth_radix8_multiplier #(
    parameter integer WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire signed [WIDTH-1:0]      multiplicand,
    input  wire signed [WIDTH-1:0]      multiplier,
    input  wire [1:0]                   sign_mode,
    output reg  signed [2*WIDTH-1:0]    product,
    output reg                          done,
    output wire                         busy
);

    wire [7:0] a_low  = multiplicand[7:0];
    wire [7:0] a_high = multiplicand[15:8];
    wire [7:0] b_low  = multiplier[7:0];
    wire [7:0] b_high = multiplier[15:8];

    reg        mult_start;
    wire [3:0] mult_done;
    wire signed [15:0] p0, p1, p2, p3;

    localparam IDLE = 1'b0;
    localparam WAIT = 1'b1;

    reg state;
    reg [1:0] original_sign_mode;

    assign busy = (state != IDLE);

    // 4 Instâncias rodando em paralelo
    booth_mult8 mult0 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_low), .multiplier(b_low), .sign_mode(2'b00),
        .product(p0), .done(mult_done[0])
    );

    booth_mult8 mult1 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_high), .multiplier(b_low), .sign_mode({original_sign_mode[1], 1'b0}),
        .product(p1), .done(mult_done[1])
    );

    booth_mult8 mult2 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_low), .multiplier(b_high), .sign_mode({1'b0, original_sign_mode[0]}),
        .product(p2), .done(mult_done[2])
    );

    booth_mult8 mult3 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_high), .multiplier(b_high), .sign_mode(original_sign_mode),
        .product(p3), .done(mult_done[3])
    );

    // ------------------------------------------------------------------------
    // SOMA FINAL OTIMIZADA (Split Adder)
    // ------------------------------------------------------------------------
    reg signed [31:0] result_temp;

    // Bits de sinal para extensão correta
    wire s1 = p1[15] & original_sign_mode[1];
    wire s2 = p2[15] & original_sign_mode[0];

    // Estágio 1: Soma Intermediária (p1 + p2)
    // CRÍTICO: 18 bits para evitar overflow de soma de números positivos grandes
    wire signed [17:0] sum_p1_p2 = {{2{s1}}, p1} + {{2{s2}}, p2};

    // Estágio 2: Preparação da Base Superior (Bits 31..8 do resultado)
    wire signed [23:0] base_upper = {p3, p0[15:8]};

    // Estágio 3: Extensão de sinal da soma intermediária para casar com a base
    // Usa o bit [17] do sum_p1_p2 para estender o sinal corretamente
    wire signed [23:0] mid_extended = {{6{sum_p1_p2[17]}}, sum_p1_p2};

    // Estágio 4: Soma Final da Parte Alta
    wire signed [23:0] res_upper = base_upper + mid_extended;

    // Estágio 5: Concatenação Final (p0[7:0] passa direto, sem delay de adder)
    always @(*) begin
        result_temp = {res_upper, p0[7:0]};
    end

    // Máquina de Estados
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            mult_start         <= 1'b0;
            done               <= 1'b0;
            product            <= 32'b0;
            original_sign_mode <= 2'b00;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        original_sign_mode <= sign_mode;
                        mult_start         <= 1'b1;
                        state              <= WAIT;
                    end
                end
                WAIT: begin
                    mult_start <= 1'b0;
                    if (&mult_done) begin
                        product <= result_temp;
                        done    <= 1'b1;
                        state   <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
`default_nettype wire
