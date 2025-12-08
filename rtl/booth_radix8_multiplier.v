// ============================================================================
// Module: booth_mult8
// Description: Otimized Booth Radix-8 (8-bit)
// Optimizations: 3M Precalc
// ============================================================================
module booth_mult8 (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire signed [7:0]     multiplicand,
    input  wire signed [7:0]     multiplier,
    input  wire [1:0]            sign_mode, // Usado apenas no setup para pré-cálculo
    output reg  signed [15:0]    product,
    output reg                   done
);
    localparam integer WIDTH = 8;
    localparam integer NUM_ITER = 3;
    localparam integer SHIFT_BITS = 9;
    localparam integer ACC_WIDTH = 11;
    localparam integer REG_WIDTH = 21;

    reg mcand_signed;
    reg active;
    reg signed [REG_WIDTH-1:0] prod_reg;

    // Registrador para armazenar 3*M (quebra caminho crítico)
    reg signed [ACC_WIDTH-1:0] m_3x_reg;

    wire [3:0] booth_bits = prod_reg[3:0];
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    // Extensão de sinal do multiplicando
    wire signed [ACC_WIDTH-1:0] mcand_ext = mcand_signed ?
        { {(ACC_WIDTH-WIDTH){multiplicand[WIDTH-1]}}, multiplicand } :
        { {(ACC_WIDTH-WIDTH){1'b0}}, multiplicand };

    // Lógica de Pré-cálculo do 3x (Input direto)
    wire signed [ACC_WIDTH-1:0] mcand_ext_input = sign_mode[1] ?
        { {(ACC_WIDTH-WIDTH){multiplicand[WIDTH-1]}}, multiplicand } :
        { {(ACC_WIDTH-WIDTH){1'b0}}, multiplicand };

    wire signed [ACC_WIDTH-1:0] calc_3x = mcand_ext_input + (mcand_ext_input <<< 1);

    // Múltiplos
    wire signed [ACC_WIDTH-1:0] m_1x = mcand_ext;
    wire signed [ACC_WIDTH-1:0] m_2x = m_1x <<< 1;
    wire signed [ACC_WIDTH-1:0] m_4x = m_1x <<< 2;

    // Decodificação Booth Radix-8
    wire sel_zero = (booth_bits == 4'b0000) || (booth_bits == 4'b1111);
    wire sel_m1   = (booth_bits == 4'b0001) || (booth_bits == 4'b0010);
    wire sel_m2   = (booth_bits == 4'b0011) || (booth_bits == 4'b0100);
    wire sel_m3   = (booth_bits == 4'b0101) || (booth_bits == 4'b0110);
    wire sel_m4   = (booth_bits == 4'b0111);

    wire sel_m1_neg = (booth_bits == 4'b1101) || (booth_bits == 4'b1110);
    wire sel_m2_neg = (booth_bits == 4'b1011) || (booth_bits == 4'b1100);
    wire sel_m3_neg = (booth_bits == 4'b1001) || (booth_bits == 4'b1010);
    wire sel_m4_neg = (booth_bits == 4'b1000);

    wire inv = sel_m1_neg || sel_m2_neg || sel_m3_neg || sel_m4_neg;

    // MUX Principal
    wire signed [ACC_WIDTH-1:0] selected_val =
        ({ACC_WIDTH{sel_m1 || sel_m1_neg}} & m_1x) |
        ({ACC_WIDTH{sel_m2 || sel_m2_neg}} & m_2x) |
        ({ACC_WIDTH{sel_m3 || sel_m3_neg}} & m_3x_reg) | // Usa registrador
        ({ACC_WIDTH{sel_m4 || sel_m4_neg}} & m_4x);

    wire signed [ACC_WIDTH-1:0] operand = sel_zero ? {ACC_WIDTH{1'b0}} :
                                          (inv ? ~selected_val : selected_val);

    // Soma
    wire signed [ACC_WIDTH-1:0] sum_result = acc_upper + operand + { {(ACC_WIDTH-1){1'b0}}, inv };

    reg [NUM_ITER:0] iter_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active       <= 1'b0;
            iter_shift   <= 4'b0;
            prod_reg     <= {REG_WIDTH{1'b0}};
            done         <= 1'b0;
            product      <= 16'b0;
            mcand_signed <= 1'b0;
            m_3x_reg     <= {ACC_WIDTH{1'b0}};
        end else begin
            if (active) begin
                if (iter_shift[0]) begin
                    active  <= 1'b0;
                    done    <= 1'b1;
                    product <= prod_reg[16:1];
                end else begin
                    // Shift Aritmético sempre (Necessário para Booth)
                    prod_reg   <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
                    iter_shift <= iter_shift >> 1;
                end
            end else begin
                done <= 1'b0;
                if (start) begin
                    active       <= 1'b1;
                    mcand_signed <= sign_mode[1];
                    iter_shift   <= 4'b1000;
                    m_3x_reg     <= calc_3x;

                    if (sign_mode[0]) begin
                        prod_reg <= {
                            {ACC_WIDTH{1'b0}},
                            {(SHIFT_BITS-WIDTH){multiplier[WIDTH-1]}},
                            multiplier,
                            1'b0
                        };
                    end else begin
                        prod_reg <= {
                            {ACC_WIDTH{1'b0}},
                            {(SHIFT_BITS-WIDTH){1'b0}},
                            multiplier,
                            1'b0
                        };
                    end
                end
            end
        end
    end
endmodule

// ============================================================================
// Module: booth_radix8_multiplier (Top)
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

    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam WAIT    = 2'd2;
    localparam FINISH  = 2'd3;

    reg [1:0] state;
    reg [1:0] original_sign_mode;

    // Busy controlado apenas pelo estado principal
    assign busy = (state != IDLE);

    // Mult 0: Low x Low (Sempre Unsigned)
    booth_mult8 mult0 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_low), .multiplier(b_low),
        .sign_mode(2'b00),
        .product(p0), .done(mult_done[0])
    );

    // Mult 1: High x Low (A_High herda sinal de A)
    booth_mult8 mult1 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_high), .multiplier(b_low),
        .sign_mode({original_sign_mode[1], 1'b0}),
        .product(p1), .done(mult_done[1])
    );

    // Mult 2: Low x High (B_High herda sinal de B)
    booth_mult8 mult2 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_low), .multiplier(b_high),
        .sign_mode({1'b0, original_sign_mode[0]}),
        .product(p2), .done(mult_done[2])
    );

    // Mult 3: High x High (Herdam sinais originais)
    booth_mult8 mult3 (
        .clk(clk), .rst_n(rst_n), .start(mult_start),
        .multiplicand(a_high), .multiplier(b_high),
        .sign_mode(original_sign_mode),
        .product(p3), .done(mult_done[3])
    );

    // Soma Combinacional Final
    reg signed [31:0] p0_ext, p1_ext, p2_ext, p3_ext;
    reg signed [31:0] result_temp;

    always @(*) begin
        // P0 (Low*Low) é sempre positivo/unsigned
        p0_ext = {16'b0, p0};

        // P1 e P2 dependem dos sinais originais
        if (original_sign_mode[1]) p1_ext = {{16{p1[15]}}, p1};
        else                       p1_ext = {16'b0, p1};

        if (original_sign_mode[0]) p2_ext = {{16{p2[15]}}, p2};
        else                       p2_ext = {16'b0, p2};

        // P3 depende de ambos
        if (original_sign_mode == 2'b11) p3_ext = {{16{p3[15]}}, p3};
        else                             p3_ext = {16'b0, p3};

        // Montagem do resultado
        result_temp = (p3_ext <<< 16) + (p2_ext <<< 8) + (p1_ext <<< 8) + p0_ext;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            mult_start <= 1'b0;
            done <= 1'b0;
            product <= 32'b0;
            original_sign_mode <= 2'b00;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    mult_start <= 1'b0;
                    if (start) begin
                        original_sign_mode <= sign_mode;
                        mult_start <= 1'b1;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    mult_start <= 1'b0;
                    state <= WAIT;
                end

                WAIT: begin
                    if (&mult_done) begin
                        state <= FINISH;
                    end
                end

                FINISH: begin
                    product <= result_temp;
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
`default_nettype wire
