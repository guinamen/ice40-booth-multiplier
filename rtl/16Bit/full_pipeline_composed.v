`timescale 1ns / 1ps
`default_nettype none

module booth_16x16_fast_simple (
    input  wire        clk,
    input  wire        v_in,
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [1:0]  sm,   // [1]:A signed, [0]:B signed
    output reg  [31:0] p,
    output reg         v_out
);

    //==========================================================================
    // ESTÁGIO 0: INPUT BUFFER
    //==========================================================================
    reg [15:0] r0_a, r0_b; reg [1:0] r0_sm; reg r0_v;
    always @(posedge clk) begin r0_a <= a; r0_b <= b; r0_sm <= sm; r0_v <= v_in; end

    //==========================================================================
    // ESTÁGIO 1-6: CORES 8x8 (6 Ciclos)
    //==========================================================================
    wire [15:0] p_ll, p_lh, p_hl, p_hh;
    wire v_cores;

    booth_core_250mhz core_ll (.clk(clk), .v_in(r0_v), .a(r0_a[7:0]), .b(r0_b[7:0]), .sm(2'b00), .p(p_ll), .v_out(v_cores));
    booth_core_250mhz core_lh (.clk(clk), .v_in(r0_v), .a(r0_a[7:0]), .b(r0_b[15:8]), .sm({1'b0, r0_sm[0]}), .p(p_lh), .v_out());
    booth_core_250mhz core_hl (.clk(clk), .v_in(r0_v), .a(r0_a[15:8]), .b(r0_b[7:0]), .sm({r0_sm[1], 1'b0}), .p(p_hl), .v_out());
    booth_core_250mhz core_hh (.clk(clk), .v_in(r0_v), .a(r0_a[15:8]), .b(r0_b[15:8]), .sm(r0_sm), .p(p_hh), .v_out());

    //==========================================================================
    // ESTÁGIO 7: PONTE DE REGISTRO
    //==========================================================================
    reg [15:0] r7_ll, r7_lh, r7_hl, r7_hh; reg r7_v;
    always @(posedge clk) begin
        r7_v <= v_cores;
        r7_ll <= p_ll; r7_lh <= p_lh; r7_hl <= p_hl; r7_hh <= p_hh;
    end

    //==========================================================================
    // ESTÁGIO 8-11: ESCADA DE SOMA SISTÓLICA (8-bit per cycle)
    //==========================================================================
    // Esta parte substitui o somador de 32-bit por somas de 8-bit.

    reg [16:0] r8_mid;     // LH + HL (peso 2^8)
    reg [15:0] r8_ll, r8_hh; reg r8_v;

    reg [7:0]  r9_p0, r9_p1; reg [8:0] r9_c1; reg [15:0] r9_mid, r9_hh; reg r9_v;
    reg [7:0]  r10_p0, r10_p1, r10_p2; reg [8:0] r10_c2; reg [7:0] r10_hh8; reg r10_v;

    always @(posedge clk) begin
        // Estágio 8: Soma os produtos parciais centrais (Peso 2^8)
        r8_v   <= r7_v;
        r8_mid <= r7_lh + r7_hl;
        r8_ll  <= r7_ll; r8_hh  <= r7_hh;

        // Estágio 9: Extrai Byte 0 e soma Byte 1
        r9_v   <= r8_v;
        r9_p0  <= r8_ll[7:0];
        {r9_c1, r9_p1} <= r8_ll[15:8] + r8_mid[7:0];
        r9_mid <= r8_mid[15:8]; r9_hh <= r8_hh;

        // Estágio 10: Extrai Byte 1 e soma Byte 2
        r10_v   <= r9_v;
        r10_p0  <= r9_p0; r10_p1 <= r9_p1;
        {r10_c2, r10_p2} <= r9_mid[7:0] + r9_hh[7:0] + r9_c1[8];
        r10_hh8 <= r9_hh[15:8] + r9_mid[8];

        // Estágio 11: Resultado Final (Soma Byte 3)
        v_out <= r10_v;
        p[7:0]   <= r10_p0;
        p[15:8]  <= r10_p1;
        p[23:16] <= r10_p2;
        p[31:24] <= r10_hh8 + r10_c2[8];
    end

endmodule
