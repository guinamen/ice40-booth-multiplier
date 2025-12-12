`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: booth_mult8_final
// Description: Versão com Isolamento de Entradas (Alta Fmax + Robustez)
// Latência: 1 ciclo (Input Capture) + 4 ciclos (Processing) = 5 ciclos Total
// ============================================================================
module booth_mult8 (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire signed [7:0]     multiplicand,
    input  wire signed [7:0]     multiplier,
    input  wire [1:0]            sign_mode,
    output wire signed [15:0]    product,
    output reg                   done
);
    localparam integer WIDTH = 8;
    localparam integer SHIFT_BITS = 9;
    localparam integer ACC_WIDTH = 11;
    localparam integer REG_WIDTH = 21;

    // ------------------------------------------------------------------------
    // ESTÁGIO 1: Input Registering (Isolamento)
    // ------------------------------------------------------------------------
    // Captura as entradas para garantir que o delay externo não afete o adder.
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
    // ESTÁGIO 2: Lógica Booth (Usa registros internos 'r_')
    // ------------------------------------------------------------------------
    reg active;
    reg [2:0] iter_shift;
    reg signed [REG_WIDTH-1:0] prod_reg;
    reg signed [ACC_WIDTH-1:0] m_3x_reg;
    reg signed [ACC_WIDTH-1:0] mcand_ext_reg;

    // Setup Combinacional (Baseado nos registros de entrada capturados)
    wire sign_bit_a = r_sign_mode[1] & r_multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){sign_bit_a}}, r_multiplicand };
    
    // Cálculo do 3x
    wire signed [ACC_WIDTH-1:0] calc_3x = mcand_extended + (mcand_extended <<< 1);

    wire sign_bit_b = r_sign_mode[0] & r_multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},
        {(SHIFT_BITS-WIDTH){sign_bit_b}},
        r_multiplier,
        1'b0
    };

    // Lógica do Loop (Inalterada da versão anterior)
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

    assign product = prod_reg[16:1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active         <= 1'b0;
            done           <= 1'b0;
            iter_shift     <= 3'b0;
            prod_reg       <= {REG_WIDTH{1'b0}};
            m_3x_reg       <= {ACC_WIDTH{1'b0}};
            mcand_ext_reg  <= {ACC_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;

            if (active) begin
                prod_reg   <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
                iter_shift <= iter_shift >> 1;
                
                if (iter_shift[0]) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end else if (r_start) begin // Usa o start registrado
                active        <= 1'b1;
                iter_shift    <= 3'b100;
                mcand_ext_reg <= mcand_extended; // Usa valores derivados dos inputs registrados
                m_3x_reg      <= calc_3x;
                prod_reg      <= prod_reg_init;
            end
        end
    end
endmodule
`default_nettype wire
