`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: booth_mult8
// Status: MANTIDO (Design compacto e eficiente)
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

    reg signed [ACC_WIDTH-1:0] m_3x_reg;
    reg signed [ACC_WIDTH-1:0] mcand_ext_reg;

    wire sign_bit_a = sign_mode[1] & multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){sign_bit_a}}, multiplicand };
    wire signed [ACC_WIDTH-1:0] calc_3x = mcand_extended + (mcand_extended <<< 1);

    wire sign_bit_b = sign_mode[0] & multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},
        {(SHIFT_BITS-WIDTH){sign_bit_b}},
        multiplier,
        1'b0
    };

    wire [3:0] booth_bits = prod_reg[3:0];
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    reg sel_1x, sel_2x, sel_3x, sel_4x;
    always @(*) begin
        sel_1x = (booth_bits == 4'b0001) || (booth_bits == 4'b0010) ||
                 (booth_bits == 4'b1101) || (booth_bits == 4'b1110);
        sel_2x = (booth_bits == 4'b0011) || (booth_bits == 4'b0100) ||
                 (booth_bits == 4'b1011) || (booth_bits == 4'b1100);
        sel_3x = (booth_bits == 4'b0101) || (booth_bits == 4'b0110) ||
                 (booth_bits == 4'b1001) || (booth_bits == 4'b1010);
        sel_4x = (booth_bits == 4'b0111) || (booth_bits == 4'b1000);
    end

    wire inv = booth_bits[3] & ~(&booth_bits[2:0]);
    wire signed [ACC_WIDTH-1:0] m_1x = mcand_ext_reg;
    wire signed [ACC_WIDTH-1:0] m_2x = mcand_ext_reg <<< 1;
    wire signed [ACC_WIDTH-1:0] m_4x = mcand_ext_reg <<< 2;

    reg signed [ACC_WIDTH-1:0] mag_sel;
    always @(*) begin
        mag_sel = ({ACC_WIDTH{sel_1x}} & m_1x) |
                  ({ACC_WIDTH{sel_2x}} & m_2x) |
                  ({ACC_WIDTH{sel_3x}} & m_3x_reg) |
                  ({ACC_WIDTH{sel_4x}} & m_4x);
    end

    wire signed [ACC_WIDTH-1:0] operand_inv = mag_sel ^ {ACC_WIDTH{inv}};
    wire signed [ACC_WIDTH-1:0] sum_result  = acc_upper + operand_inv + { {(ACC_WIDTH-1){1'b0}}, inv };

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
// Optimization: INPUT REGISTERS + PIPELINED ADDER
// ============================================================================
module booth_radix8_multiplier_7 #(
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

    // ------------------------------------------------------------------------
    // 1. INPUT REGISTERS (Critical for High Fmax)
    // Isola os pinos de IO da lógica interna. 
    // Resolve o atraso de "start_SB_LUT4..."
    // ------------------------------------------------------------------------
    reg r_start;
    reg signed [WIDTH-1:0] r_mcand, r_mult;
    reg [1:0] r_sign_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_start <= 1'b0;
            r_mcand <= {WIDTH{1'b0}};
            r_mult  <= {WIDTH{1'b0}};
            r_sign_mode <= 2'b00;
        end else begin
            r_start <= start;
            if (start) begin
                r_mcand <= multiplicand;
                r_mult  <= multiplier;
                r_sign_mode <= sign_mode;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 2. PARALLEL MULTIPLIERS
    // ------------------------------------------------------------------------
    wire [7:0] a_low  = r_mcand[7:0];
    wire [7:0] a_high = r_mcand[15:8];
    wire [7:0] b_low  = r_mult[7:0];
    wire [7:0] b_high = r_mult[15:8];

    wire [3:0] mult_done;
    wire signed [15:0] w_p0, w_p1, w_p2, w_p3;

    // Instâncias usam os sinais REGISTRADOS (r_*)
    booth_mult8 mult0 (
        .clk(clk), .rst_n(rst_n), .start(r_start),
        .multiplicand(a_low), .multiplier(b_low), .sign_mode(2'b00),
        .product(w_p0), .done(mult_done[0])
    );

    booth_mult8 mult1 (
        .clk(clk), .rst_n(rst_n), .start(r_start),
        .multiplicand(a_high), .multiplier(b_low), .sign_mode({r_sign_mode[1], 1'b0}),
        .product(w_p1), .done(mult_done[1])
    );

    booth_mult8 mult2 (
        .clk(clk), .rst_n(rst_n), .start(r_start),
        .multiplicand(a_low), .multiplier(b_high), .sign_mode({1'b0, r_sign_mode[0]}),
        .product(w_p2), .done(mult_done[2])
    );

    booth_mult8 mult3 (
        .clk(clk), .rst_n(rst_n), .start(r_start),
        .multiplicand(a_high), .multiplier(b_high), .sign_mode(r_sign_mode),
        .product(w_p3), .done(mult_done[3])
    );

    // ------------------------------------------------------------------------
    // 3. CONTROL & PIPELINED ADDER TREE
    // Removemos a FSM complexa e usamos um sinal de controle simples.
    // ------------------------------------------------------------------------
    
    // Registradores de Pipeline (Stage 1 da soma)
    reg signed [17:0] pipe_sum_p1_p2;
    reg signed [23:0] pipe_base;
    reg [7:0]         pipe_p0_low;
    reg               pipe_valid;

    // Lógica Combinacional do Estágio 1
    // Nota: Como r_sign_mode é registrado na entrada, ele é estável aqui
    wire s1 = w_p1[15] & r_sign_mode[1];
    wire s2 = w_p2[15] & r_sign_mode[0];
    
    // Calcula p1+p2 assim que os dados chegam dos multiplicadores
    wire signed [17:0] calc_sum_p1_p2 = {{2{s1}}, w_p1} + {{2{s2}}, w_p2};

    // Controle de estado simplificado
    // mult_busy indica se estamos processando. 
    // Como os 4 terminam juntos, olhamos apenas um ou o AND.
    reg mult_active;
    
    assign busy = mult_active || pipe_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_active    <= 1'b0;
            pipe_valid     <= 1'b0;
            done           <= 1'b0;
            product        <= 32'b0;
            pipe_sum_p1_p2 <= 18'b0;
            pipe_base      <= 24'b0;
            pipe_p0_low    <= 8'b0;
        end else begin
            done <= 1'b0; // Pulso de 1 ciclo

            // Lógica de ativação baseada no registrador interno r_start
            if (r_start) begin
                mult_active <= 1'b1;
            end

            // Quando a multiplicação termina (sinal done dos submódulos)
            // Capturamos os dados para o registrador de pipeline
            if (mult_active && mult_done[0]) begin
                // STAGE 1: Captura e Primeira Soma
                pipe_sum_p1_p2 <= calc_sum_p1_p2;
                pipe_base      <= {w_p3, w_p0[15:8]};
                pipe_p0_low    <= w_p0[7:0];
                
                pipe_valid     <= 1'b1;
                mult_active    <= 1'b0;
            end else begin
                pipe_valid <= 1'b0;
            end

            // STAGE 2: Soma Final e Saída
            if (pipe_valid) begin
                // A extensão de sinal aqui (bit 17) é barata pois pipe_sum_p1_p2 é um Flip-Flop
                product[31:8] <= pipe_base + {{6{pipe_sum_p1_p2[17]}}, pipe_sum_p1_p2};
                product[7:0]  <= pipe_p0_low;
                done          <= 1'b1;
            end
        end
    end

endmodule
`default_nettype wire
