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

module booth_mult8_core #(
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
    // FUNÇÕES AUXILIARES
    // =========================================================================

    // -------------------------------------------------------------------------
    // Calcula 3×multiplicando (otimização Booth: 3A = A + 2A)
    // -------------------------------------------------------------------------
    function automatic [ACC_WIDTH-1:0] f_calc_3x;
        input [WIDTH-1:0] val_in;  // Valor de entrada
        input             s_bit;   // Bit de sinal para extensão
        reg [ACC_WIDTH-1:0] val_ext;
    begin
        // Estende o valor com sinal
        val_ext = { {(ACC_WIDTH-WIDTH){s_bit}}, val_in };
        // Calcula 3x = x + (x << 1)
        f_calc_3x = val_ext + (val_ext <<< 1);
    end
    endfunction

    // -------------------------------------------------------------------------
    // Estende o multiplicando com bit de sinal
    // -------------------------------------------------------------------------
    function automatic [ACC_WIDTH-1:0] f_extend_mcand;
        input [WIDTH-1:0] val_in;  // Valor a estender
        input             s_bit;   // Bit de sinal
    begin
        f_extend_mcand = { {(ACC_WIDTH-WIDTH){s_bit}}, val_in };
    end
    endfunction

    // -------------------------------------------------------------------------
    // Inicializa o registrador de produto com o multiplicador
    // Formato: [ACC_bits | sign_bit | multiplier | 0]
    // -------------------------------------------------------------------------
    function automatic [REG_WIDTH-1:0] f_init_prod_reg;
        input [WIDTH-1:0] mult_in;  // Multiplicador
        input             s_bit;    // Bit de sinal
    begin
        f_init_prod_reg = {
            {ACC_WIDTH{1'b0}},  // Parte alta zerada (acumulador)
            s_bit,              // Bit de sinal estendido
            mult_in,            // Multiplicador
            1'b0                // Bit extra para janela de Booth
        };
    end
    endfunction

    // -------------------------------------------------------------------------
    // DECODIFICADOR BOOTH RADIX-4
    // Analisa janela de 4 bits e gera sinais de controle
    // -------------------------------------------------------------------------
    // Codificação da saída [4:0]:
    //   [4]   = sinal da operação (1=subtração, 0=adição)
    //   [3:0] = magnitude one-hot (0=±0, 1=±1x, 2=±2x, 3=±3x, 4=±4x)
    // -------------------------------------------------------------------------
    function automatic [4:0] f_booth_decoder;
        input [3:0] window;     // Janela de 4 bits [i+2:i-1]
        reg [2:0] recoded;
    begin
        // Recodificação: inverte bits se MSB=1 (número negativo)
        recoded = window[2:0] ^ {3{window[3]}};

        // Determina sinal: subtração se negativo e não é -0
        f_booth_decoder[4] = window[3] & ~(&window[2:0]);

        // Inicializa magnitude
        f_booth_decoder[3:0] = 4'b0000;

        // Decodifica magnitude baseado nos bits recodificados
        case (recoded)
            3'b001, 3'b010: f_booth_decoder[0] = 1'b1;  // ±1x
            3'b011, 3'b100: f_booth_decoder[1] = 1'b1;  // ±2x
            3'b101, 3'b110: f_booth_decoder[2] = 1'b1;  // ±3x
            3'b111:         f_booth_decoder[3] = 1'b1;  // ±4x
            default:        ;                            // 0x (nada)
        endcase
    end
    endfunction

    // -------------------------------------------------------------------------
    // UNIDADE ARITMÉTICA (ALU)
    // Executa: acumulador ± (magnitude do multiplicando)
    // -------------------------------------------------------------------------
    function automatic [ACC_WIDTH-1:0] f_alu_calc;
        input [ACC_WIDTH-1:0] acc_val;  // Valor atual do acumulador
        input [ACC_WIDTH-1:0] val_1x;   // Multiplicando (1x)
        input [ACC_WIDTH-1:0] val_3x;   // Multiplicando pré-calculado (3x)
        input [4:0]           ctrl;     // Controle do decodificador Booth

        reg [ACC_WIDTH-1:0] magnitude;      // Magnitude selecionada
        reg [ACC_WIDTH-1:0] operand_final;  // Operando com sinal aplicado
        reg                 inv;            // Flag de inversão (subtração)
    begin
        inv = ctrl[4];  // Extrai bit de sinal

        // Seleciona magnitude usando multiplexador one-hot
        magnitude = ({ACC_WIDTH{ctrl[0]}} & val_1x)            |  // 1x
                    ({ACC_WIDTH{ctrl[1]}} & (val_1x <<< 1))    |  // 2x
                    ({ACC_WIDTH{ctrl[2]}} & val_3x)            |  // 3x
                    ({ACC_WIDTH{ctrl[3]}} & (val_1x <<< 2));      // 4x

        // Aplica complemento de 2 se subtração (inv XOR + carry)
        operand_final = magnitude ^ {ACC_WIDTH{inv}};

        // Soma: acc + operando + carry_in(=inv)
        f_alu_calc = acc_val + operand_final + { {(ACC_WIDTH-1){1'b0}}, inv };
    end
    endfunction

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
