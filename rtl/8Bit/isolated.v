`timescale 1ns / 1ps
`default_nettype none
module booth_mult8_isolated (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire signed [7:0]     multiplicand,
    input  wire signed [7:0]     multiplier,
    input  wire [1:0]            sign_mode,
    output wire signed [15:0]    product,
    output wire                  done
);

    // ------------------------------------------------------------------------
    // ESTÁGIO DE ISOLAMENTO (PIPELINE STAGE 0)
    // ------------------------------------------------------------------------
    reg r_start;
    reg [1:0] r_sign_mode;
    reg signed [7:0] r_multiplicand;
    reg signed [7:0] r_multiplier;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_start        <= 1'b0;
            r_sign_mode    <= 2'b00;
            r_multiplicand <= 8'd0;
            r_multiplier   <= 8'd0;
        end else begin
            r_start        <= start;
            r_sign_mode    <= sign_mode;
            r_multiplicand <= multiplicand;
            r_multiplier   <= multiplier;
        end
    end

    // ------------------------------------------------------------------------
    // INSTÂNCIA DO CORE
    // ------------------------------------------------------------------------
    // As entradas registradas são enviadas para o núcleo lógico.

    booth_mult8_core #(
        .WIDTH(8)
    ) u_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (r_start),        // Usa o sinal registrado
        .multiplicand (r_multiplicand), // Usa o sinal registrado
        .multiplier   (r_multiplier),   // Usa o sinal registrado
        .sign_mode    (r_sign_mode),    // Usa o sinal registrado
        .product      (product),
        .done         (done)
    );

endmodule
`default_nettype wire
