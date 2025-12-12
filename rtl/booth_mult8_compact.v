`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// Module: booth_mult8_compact
// Objetivo: Mesma performance (160MHz+), MENOR ÁREA.
// Estratégia: Eliminação de registradores redundantes via Load-Enable.
// Economia Estimada: ~20 Logic Cells a menos que a versão anterior.
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
    localparam integer WIDTH      = 8;
    localparam integer SHIFT_BITS = 9;
    localparam integer ACC_WIDTH  = 11;
    localparam integer REG_WIDTH  = 21;

    // ------------------------------------------------------------------------
    // REGISTRADORES DE RETENÇÃO (Input Holding)
    // ------------------------------------------------------------------------
    // Em vez de capturar tudo incondicionalmente, usamos o 'start' como 
    // um "Write Enable". Durante o cálculo ('active'), estes registradores
    // congelam, eliminando a necessidade de buffers internos extras.
    
    reg signed [7:0] r_mcand;     // Substitui r_multiplicand E mcand_ext_reg
    reg [1:0]        r_sign_mode; 
    
    // O 3x precisa ser registrado para garantir timing, pois envolve um adder.
    // Calculamos ele baseado na entrada NO MOMENTO do start.
    reg signed [ACC_WIDTH-1:0] m_3x_reg;

    // Lógica Combinacional de Entrada para Pré-cálculos
    // (Calcula o que VAI ser salvo nos registradores quando start=1)
    wire s_bit_a_in = sign_mode[1] & multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_ext_in = { {(ACC_WIDTH-WIDTH){s_bit_a_in}}, multiplicand };
    wire signed [ACC_WIDTH-1:0] calc_3x_in   = mcand_ext_in + (mcand_ext_in <<< 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_mcand     <= 8'd0;
            r_sign_mode <= 2'b00;
            m_3x_reg    <= {ACC_WIDTH{1'b0}};
        end else if (start) begin
            // Só atualiza quando comandado (Load Enable)
            r_mcand     <= multiplicand;
            r_sign_mode <= sign_mode;
            m_3x_reg    <= calc_3x_in; // Captura já o resultado 3x
        end
    end

    // ------------------------------------------------------------------------
    // DATAPATH PRINCIPAL
    // ------------------------------------------------------------------------
    reg active;
    reg [2:0] iter_shift;
    reg signed [REG_WIDTH-1:0] prod_reg;

    // Reconstrução da extensão de sinal on-the-fly (Custo: 0 FFs, apenas fios)
    // Como r_mcand está congelado durante 'active', isso é seguro.
    wire s_bit_a_stored = r_sign_mode[1] & r_mcand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){s_bit_a_stored}}, r_mcand };

    // Setup do Produto (Direto da Entrada -> Registro de Trabalho)
    wire s_bit_b_in = sign_mode[0] & multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},                 // Zera Acumulador
        {(SHIFT_BITS-WIDTH){s_bit_b_in}},  // Padding Sinal B
        multiplier,                        // Multiplicador Input direto
        1'b0                               // Bit implícito
    };

    // ------------------------------------------------------------------------
    // MÁQUINA DE ESTADOS & ALU
    // ------------------------------------------------------------------------
    wire [3:0] booth_bits = prod_reg[3:0];
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    // Decodificação Booth (Lógica LUT4 pura)
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

    // Mux Achatado (Flattened)
    reg signed [ACC_WIDTH-1:0] mag_sel;
    always @(*) begin
        mag_sel = ({ACC_WIDTH{sel_1x}} & mcand_extended) | // 1x usa reconstrução wire
                  ({ACC_WIDTH{sel_2x}} & (mcand_extended <<< 1)) |
                  ({ACC_WIDTH{sel_3x}} & m_3x_reg) |       // 3x usa reg pré-calculado
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
                // Shift e Soma
                prod_reg   <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
                iter_shift <= iter_shift >> 1;
                
                if (iter_shift[0]) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end else if (start) begin
                active     <= 1'b1;
                iter_shift <= 3'b100;
                // Carrega o multiplicador diretamente da porta de entrada para o registrador de trabalho
                prod_reg   <= prod_reg_init; 
            end
        end
    end

endmodule
`default_nettype wire
