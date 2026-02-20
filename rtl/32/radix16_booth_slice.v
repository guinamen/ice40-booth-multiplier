`timescale 1ns/1ps

// ================================================================
// RADIX-16 BOOTH SLICE — DIMENSIONAMENTO CORRETO
// ================================================================

module radix16_booth_slice #
(
    parameter WIDTH = 32
)
(
    input  wire signed [WIDTH-1:0]  a,
    input  wire        [4:0]        booth_bits,

    output wire signed [WIDTH+4:0]  sum,
    output wire signed [WIDTH+4:0]  carry
);

    localparam EXT = WIDTH + 5;

    // ------------------------------------------------------------
    // Extensão correta
    // ------------------------------------------------------------

    wire signed [EXT-1:0] a_ext =
        { {5{a[WIDTH-1]}}, a };

    wire signed [EXT-1:0] a_x2 = a_ext << 1;
    wire signed [EXT-1:0] a_x4 = a_ext << 2;
    wire signed [EXT-1:0] a_x8 = a_ext << 3;

    wire sign_bit = booth_bits[4];
    wire [3:0] m  = booth_bits[3:0];

    wire [EXT-1:0] ZERO = {EXT{1'b0}};

    // ------------------------------------------------------------
    // Parciais
    // ------------------------------------------------------------

    wire signed [EXT-1:0] p0 = m[0] ? a_ext : ZERO;
    wire signed [EXT-1:0] p1 = m[1] ? a_x2  : ZERO;
    wire signed [EXT-1:0] p2 = m[2] ? a_x4  : ZERO;
    wire signed [EXT-1:0] p3 = m[3] ? a_x8  : ZERO;

    // ------------------------------------------------------------
    // CSA 3:2 estágio 1
    // ------------------------------------------------------------

    wire signed [EXT-1:0] s1 =
        p0 ^ p1 ^ p2;

    wire signed [EXT-1:0] c1 =
        ((p0 & p1) |
         (p0 & p2) |
         (p1 & p2)) << 1;

    // ------------------------------------------------------------
    // CSA 3:2 estágio 2
    // ------------------------------------------------------------

    wire signed [EXT-1:0] s_pos =
        s1 ^ c1 ^ p3;

    wire signed [EXT-1:0] c_pos =
        ((s1 & c1) |
         (s1 & p3) |
         (c1 & p3)) << 1;

    // ------------------------------------------------------------
    // Negação correta em carry-save
    // -(s+c) = ~s + ~c + 2
    // ------------------------------------------------------------

    wire signed [EXT-1:0] mask =
        {EXT{sign_bit}};

    wire signed [EXT-1:0] s_inv =
        s_pos ^ mask;

    wire signed [EXT-1:0] c_inv =
        c_pos ^ mask;

    wire signed [EXT-1:0] correction =
        sign_bit ? {{(EXT-2){1'b0}}, 2'b10}
                 : ZERO;

    assign sum =
        s_inv ^ c_inv ^ correction;

    assign carry =
        ((s_inv & c_inv) |
         (s_inv & correction) |
         (c_inv & correction)) << 1;

endmodule
