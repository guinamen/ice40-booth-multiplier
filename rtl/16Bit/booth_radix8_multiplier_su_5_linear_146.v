`timescale 1ns / 1ps
`default_nettype none

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
