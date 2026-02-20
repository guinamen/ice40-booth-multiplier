module radix8_booth_slice #
(
    parameter WIDTH = 32
)
(
    input  wire [WIDTH-1:0]  a,
    input  wire [3:0]        booth_bits,   // {sign,b2,b1,b0}

    output wire [WIDTH+2:0]  sum,
    output wire [WIDTH+2:0]  carry
);

    // ============================================================
    // 1. Extensão de sinal
    // ============================================================

    wire [WIDTH+2:0] a_ext = { {3{a[WIDTH-1]}}, a };
    wire [WIDTH+2:0] a_x2  = a_ext << 1;
    wire [WIDTH+2:0] a_x4  = a_ext << 2;

    // ============================================================
    // 2. Magnitude mínima (radix-8)
    // ============================================================

    wire sign_bit = booth_bits[3];

    wire b2 = booth_bits[2];
    wire b1 = booth_bits[1];
    wire b0 = booth_bits[0];

    wire m0 = b1 ^ b0;
    wire c1 = b1 & b0;
    wire m1 = b2 ^ c1;
    wire m2 = b2 & c1;

    // ============================================================
    // 3. Seleção por mascaramento
    // ============================================================

    wire [WIDTH+2:0] part0 = { (WIDTH+3){m0} } & a_ext;
    wire [WIDTH+2:0] part1 = { (WIDTH+3){m1} } & a_x2;
    wire [WIDTH+2:0] part2 = { (WIDTH+3){m2} } & a_x4;

    // ============================================================
    // 4. CSA da magnitude positiva
    // ============================================================

    wire [WIDTH+2:0] s_pos;
    wire [WIDTH+2:0] c_pos;

    assign s_pos = part0 ^ part1 ^ part2;

    assign c_pos =
        ((part0 & part1) |
         (part0 & part2) |
         (part1 & part2)) << 1;

    // ============================================================
    // 5. Aplicação correta do sinal em carry-save
    // ============================================================

    wire [WIDTH+2:0] mask = { (WIDTH+3){sign_bit} };

    // inverte ambos
    wire [WIDTH+2:0] s_inv = s_pos ^ mask;
    wire [WIDTH+2:0] c_inv = c_pos ^ mask;

    // correção = 2 quando negativo
    wire [WIDTH+2:0] correction =
        sign_bit ? {{(WIDTH+1){1'b0}}, 2'b10} :
                   {(WIDTH+3){1'b0}};

    // CSA final
    assign sum = s_inv ^ c_inv ^ correction;

    assign carry =
        ((s_inv & c_inv) |
         (s_inv & correction) |
         (c_inv & correction)) << 1;

endmodule
