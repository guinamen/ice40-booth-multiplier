`timescale 1ns / 1ps
`default_nettype none

// =============================================================================
// MULTIPLICADOR BOOTH RADIX-4 DE 8 BITS
// =============================================================================
// Implementa multiplicação de inteiros com sinal usando o algoritmo de Booth
// Radix-4, que processa 2 bits por iteração, reduzindo o número de ciclos.
//
// Suporta operações: signed×signed, unsigned×unsigned, signed×unsigned
// =============================================================================

module booth_mult8 #(
    parameter integer WIDTH = 8  // Largura dos operandos (padrão: 8 bits)
)(
    // Sinais de controle
    input  wire                        clk,          // Clock do sistema
    input  wire                        rst_n,        // Reset assíncrono ativo embaixo
    input  wire                        start,        // Inicia a multiplicação

    // Operandos de entrada
    input  wire signed [WIDTH-1:0]     multiplicand, // Multiplicando (A)
    input  wire signed [WIDTH-1:0]     multiplier,   // Multiplicador (B)
    input  wire [1:0]                  sign_mode,    // [1]:sinal de A, [0]:sinal de B

    // Resultado
    output wire signed [(2*WIDTH)-1:0] product,      // Produto final (A × B)
    output reg                         done          // Sinaliza conclusão
);
    // =========================================================================
    // PARÂMETROS INTERNOS
    // =========================================================================
    localparam integer SHIFT_BITS = WIDTH + 1;      // Bits a deslocar por iteração
    localparam integer ACC_WIDTH  = WIDTH + 3;      // Largura do acumulador
    localparam integer REG_WIDTH  = (2*WIDTH) + 5;  // Largura total do registrador produto

    // =========================================================================
    // REGISTRADORES E SINAIS INTERNOS
    // =========================================================================

    // Registradores de dados
    reg signed [ACC_WIDTH-1:0] r_mcand_ext;  // Multiplicando estendido (1x)
    reg signed [ACC_WIDTH-1:0] m_3x_reg;     // Multiplicando pré-calculado (3x)
    reg signed [REG_WIDTH-1:0] prod_reg;     // Registrador de produto/acumulador

    // Controle de estado
    reg        active;       // Flag de multiplicação ativa
    reg [2:0]  iter_shift;   // Contador de iterações (shift register)

    // Sinais combinacionais do datapath
    wire [4:0]                  w_booth_ctrl;   // Controle decodificado de Booth
    wire signed [ACC_WIDTH-1:0] w_sum_result;   // Resultado da ALU

    // =========================================================================
    // SINAIS PARA TRATAMENTO DE SINAL DOS OPERANDOS
    // =========================================================================
    // Determina se cada operando é com sinal baseado em sign_mode
    wire w_sign_bit_a = sign_mode[1] & multiplicand[WIDTH-1];  // MSB de A se signed
    wire w_sign_bit_b = sign_mode[0] & multiplier[WIDTH-1];    // MSB de B se signed
   
    // =========================================================================
    // FUNÇÕES AUXILIARES
    // =========================================================================

    `include "functions.vh"


    // =========================================================================
    // DATAPATH COMBINACIONAL
    // =========================================================================

    // Decodifica janela de Booth dos 4 bits inferiores do registrador
    assign w_booth_ctrl = f_booth_decoder(prod_reg[3:0]);

    // Calcula nova soma: acumulador ± multiplicando escalado
    assign w_sum_result = f_alu_calc(
        prod_reg[REG_WIDTH-1 : SHIFT_BITS+1],  // Parte alta (acumulador)
        r_mcand_ext,                            // 1x multiplicando
        m_3x_reg,                               // 3x multiplicando
        w_booth_ctrl                            // Controles de Booth
    );

    // Extrai resultado final (descarta bits de controle)
    assign product = prod_reg[WIDTH*2:1];

    // =========================================================================
    // MÁQUINA DE ESTADOS E LÓGICA SEQUENCIAL
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset assíncrono: inicializa todos os registradores
            active      <= 1'b0;
            done        <= 1'b0;
            iter_shift  <= 3'b0;
            r_mcand_ext <= {ACC_WIDTH{1'b0}};
            m_3x_reg    <= {ACC_WIDTH{1'b0}};
            prod_reg    <= {REG_WIDTH{1'b0}};

        end else begin
            // Pulso de done dura apenas 1 ciclo
            done <= 1'b0;

            if (active) begin
                // -------------------------------------------------------------
                // ESTADO ATIVO: Processa iterações de Booth
                // -------------------------------------------------------------

                // Atualiza registrador: [novo_acc | parte_baixa >> 2]
                // Extensão de sinal de 3 bits para preservar aritmética signed
                prod_reg <= {
                    {3{w_sum_result[ACC_WIDTH-1]}},  // Extensão de sinal
                    w_sum_result,                     // Novo acumulador
                    prod_reg[SHIFT_BITS:3]            // Desloca 2 bits (Radix-4)
                };

                // Avança contador de iterações (shift right)
                iter_shift <= iter_shift >> 1;

                // Verifica conclusão (quando LSB do contador chega a 1)
                if (iter_shift[0]) begin
                    active <= 1'b0;
                    done   <= 1'b1;
                end

            end else if (start) begin
                // -------------------------------------------------------------
                // ESTADO IDLE + START: Inicialização da multiplicação
                // -------------------------------------------------------------

                // Pré-calcula valores necessários do multiplicando
                r_mcand_ext <= f_extend_mcand(multiplicand, w_sign_bit_a);
                m_3x_reg    <= f_calc_3x(multiplicand, w_sign_bit_a);

                // Inicializa registrador de produto com multiplicador
                prod_reg    <= f_init_prod_reg(multiplier, w_sign_bit_b);

                // Inicia processamento
                active      <= 1'b1;
                iter_shift  <= 3'b100;  // 4 iterações para 8 bits (100₂ >> ... >> 001₂)
            end
        end
    end

endmodule

// =============================================================================
// NOTAS DE USO
// =============================================================================
// sign_mode: [1]=sinal_A, [0]=sinal_B
//   2'b11 = signed × signed
//   2'b00 = unsigned × unsigned
//   2'b10 = signed × unsigned
//   2'b01 = unsigned × signed
//
// Latência: 4 ciclos de clock (para WIDTH=8)
// Throughput: 1 operação a cada 5 ciclos (4 + 1 setup)

`default_nettype wire
