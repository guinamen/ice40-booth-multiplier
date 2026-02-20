module radix16_booth_slice #
(
    parameter WIDTH = 32
)
(
    input  wire [WIDTH-1:0]  a,
    input  wire [4:0]        booth_bits,   // {sign, b3,b2,b1,b0}

    output wire [WIDTH+3:0]  sum,
    output wire [WIDTH+3:0]  carry
);

    // ============================================================
    // 1. Extensão de sinal
    // ============================================================

    wire [WIDTH+3:0] a_ext = { {4{a[WIDTH-1]}}, a };
    wire [WIDTH+3:0] a_x2  = a_ext << 1;
    wire [WIDTH+3:0] a_x4  = a_ext << 2;
    wire [WIDTH+3:0] a_x8  = a_ext << 3;

    // ============================================================
    // 2. Decodificação booleana mínima da magnitude
    // ============================================================

    wire sign_bit = booth_bits[4];

    wire b3 = booth_bits[3];
    wire b2 = booth_bits[2];
    wire b1 = booth_bits[1];
    wire b0 = booth_bits[0];

    wire m0 = b1 ^ b0;

    wire c1 = b1 & b0;
    wire m1 = b2 ^ c1;

    wire c2 = b2 & c1;
    wire m2 = b3 ^ c2;

    wire m3 = b3 & c2;

    // ============================================================
    // 3. Seleção por mascaramento (sem mux)
    // ============================================================

    wire [WIDTH+3:0] part0 = { (WIDTH+4){m0} } & a_ext;
    wire [WIDTH+3:0] part1 = { (WIDTH+4){m1} } & a_x2;
    wire [WIDTH+3:0] part2 = { (WIDTH+4){m2} } & a_x4;
    wire [WIDTH+3:0] part3 = { (WIDTH+4){m3} } & a_x8;

    // ============================================================
    // 4. Compressão CSA (4 operandos → 2 vetores)
    // ============================================================

    wire [WIDTH+3:0] s1, c1_csa;
    wire [WIDTH+3:0] s2, c2_csa;

    // nível 1
    assign s1 = part0 ^ part1 ^ part2;
    assign c1_csa = ((part0 & part1) |
                     (part0 & part2) |
                     (part1 & part2)) << 1;

    // nível 2
    assign s2 = s1 ^ c1_csa ^ part3;
    assign c2_csa = ((s1 & c1_csa) |
                     (s1 & part3)  |
                     (c1_csa & part3)) << 1;

    // ============================================================
    // 5. Aplicação do sinal (XOR + correção)
    // ============================================================

    wire [WIDTH+3:0] sign_mask = { (WIDTH+4){sign_bit} };

    wire [WIDTH+3:0] op_sum   = s2 ^ sign_mask;
    wire [WIDTH+3:0] op_carry = c2_csa ^ sign_mask;

    wire [WIDTH+3:0] correction =
        { {(WIDTH+3){1'b0}}, sign_bit };

    // CSA final (3:2)

    assign sum = op_sum ^ op_carry ^ correction;

    assign carry =
        ((op_sum & op_carry) |
         (op_sum & correction) |
         (op_carry & correction)) << 1;

endmodule
