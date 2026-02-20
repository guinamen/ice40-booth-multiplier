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
    // 2. Decodificação booleana mínima da magnitude
    // ============================================================

    wire sign_bit = booth_bits[3];

    wire b2 = booth_bits[2];
    wire b1 = booth_bits[1];
    wire b0 = booth_bits[0];

    // magnitude bits

    wire m0 = b1 ^ b0;

    wire c1 = b1 & b0;
    wire m1 = b2 ^ c1;

    wire m2 = b2 & c1;

    // ============================================================
    // 3. Seleção por mascaramento (sem mux)
    // ============================================================

    wire [WIDTH+2:0] part0 = { (WIDTH+3){m0} } & a_ext;
    wire [WIDTH+2:0] part1 = { (WIDTH+3){m1} } & a_x2;
    wire [WIDTH+2:0] part2 = { (WIDTH+3){m2} } & a_x4;

    // ============================================================
    // 4. Compressão CSA (3 operandos → 2 vetores)
    // ============================================================

    wire [WIDTH+2:0] s1;
    wire [WIDTH+2:0] c1_csa;

    assign s1 = part0 ^ part1 ^ part2;

    assign c1_csa =
        ((part0 & part1) |
         (part0 & part2) |
         (part1 & part2)) << 1;

    // ============================================================
    // 5. Aplicação do sinal (XOR + correção)
    // ============================================================

    wire [WIDTH+2:0] sign_mask = { (WIDTH+3){sign_bit} };

    wire [WIDTH+2:0] op_sum   = s1 ^ sign_mask;
    wire [WIDTH+2:0] op_carry = c1_csa ^ sign_mask;

    wire [WIDTH+2:0] correction =
        { {(WIDTH+2){1'b0}}, sign_bit };

    // CSA final (3:2)

    assign sum = op_sum ^ op_carry ^ correction;

    assign carry =
        ((op_sum & op_carry) |
         (op_sum & correction) |
         (op_carry & correction)) << 1;

endmodule
