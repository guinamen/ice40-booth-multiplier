`timescale 1ns / 1ps
`default_nettype none

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
    localparam integer WIDTH      = 8;
    localparam integer SHIFT_BITS = 9;
    localparam integer ACC_WIDTH  = 11;
    localparam integer REG_WIDTH  = 21;

    // ------------------------------------------------------------------------
    // REGISTRADORES DE RETENÇÃO
    // ------------------------------------------------------------------------
    reg signed [7:0] r_mcand;
    reg        r_sign_mode;
    reg signed [ACC_WIDTH-1:0] m_3x_reg;

    // Pré-cálculo 3x
    wire s_bit_a_in = sign_mode[1] & multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_ext_in = { {(ACC_WIDTH-WIDTH){s_bit_a_in}}, multiplicand };
    wire signed [ACC_WIDTH-1:0] calc_3x_in   = mcand_ext_in + (mcand_ext_in <<< 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_mcand     <= 8'd0;
            r_sign_mode <= 2'b0;
            m_3x_reg    <= {ACC_WIDTH{1'b0}};
        end else if (start) begin
            r_mcand     <= multiplicand;
            r_sign_mode <= sign_mode[1];
            m_3x_reg    <= calc_3x_in;
        end
    end

    // ------------------------------------------------------------------------
    // DATAPATH
    // ------------------------------------------------------------------------
    reg active;
    reg [2:0] iter_shift;
    reg signed [REG_WIDTH-1:0] prod_reg;

    wire s_bit_a_stored = r_sign_mode & r_mcand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){s_bit_a_stored}}, r_mcand };

    // OTIMIZAÇÃO 3: Inicialização simplificada
    // Remove replicação redundante: {(SHIFT_BITS-WIDTH){...}} = {(9-8){...}} = {1{...}}
    wire s_bit_b_in = sign_mode[0] & multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},     // 11 zeros para acumulador
        s_bit_b_in,            // 1 bit de extensão de sinal (equivalente a {1{s_bit_b_in}})
        multiplier,            // 8 bits do multiplicador
        1'b0                   // 1 bit extra Booth
    };

    // ------------------------------------------------------------------------
    // ALU & DECODIFICADOR OTIMIZADO
    // ------------------------------------------------------------------------
    wire [3:0] booth_bits = prod_reg[3:0];
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    // Recodificação para reduzir tamanho do Case
    wire [2:0] recoded_bits;
    assign recoded_bits = booth_bits[2:0] ^ {3{booth_bits[3]}};

    reg sel_1x, sel_2x, sel_3x, sel_4x;

    always @(*) begin
        sel_1x = 1'b0;
        sel_2x = 1'b0;
        sel_3x = 1'b0;
        sel_4x = 1'b0;

        case (recoded_bits)
            3'b001, 3'b010: sel_1x = 1'b1;
            3'b011, 3'b100: sel_2x = 1'b1;
            3'b101, 3'b110: sel_3x = 1'b1;
            3'b111:         sel_4x = 1'b1;
            default:        ;
        endcase
    end

    // Detecção se devemos subtrair (número negativo ou parte negativa do Booth)
    // Cuidado: 1111 (zero) não deve subtrair.
    wire inv = booth_bits[3] & ~(&booth_bits[2:0]);

    reg signed [ACC_WIDTH-1:0] mag_sel;
    always @(*) begin
        mag_sel = ({ACC_WIDTH{sel_1x}} & mcand_extended) |
                  ({ACC_WIDTH{sel_2x}} & (mcand_extended <<< 1)) |
                  ({ACC_WIDTH{sel_3x}} & m_3x_reg) |
                  ({ACC_WIDTH{sel_4x}} & (mcand_extended <<< 2));
    end

    wire signed [ACC_WIDTH-1:0] operand_inv = mag_sel ^ {ACC_WIDTH{inv}};
    wire signed [ACC_WIDTH-1:0] sum_result  = acc_upper + operand_inv + { {(ACC_WIDTH-1){1'b0}}, inv };

    assign product = prod_reg[16:1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active     <= 1'b0;
            done       <= 1'b0;
            iter_shift <= 3'b0;
            prod_reg   <= {REG_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;

            if (active) begin
                prod_reg   <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
                iter_shift <= iter_shift >> 1;

                if (iter_shift[0]) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end else if (start) begin
                active     <= 1'b1;
                iter_shift <= 3'b100;
                prod_reg   <= prod_reg_init;
            end
        end
    end

endmodule
`default_nettype wire
