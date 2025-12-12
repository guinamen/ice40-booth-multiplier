`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// ARQUIVO:   booth_mult8.v
// MÓDULO:    booth_mult8
// DESCRIÇÃO: Multiplicador Booth Radix-8 (8-bit Signed) de Alta Performance
// 
// CARACTERÍSTICAS:
//  - Latência Fixa: 5 Ciclos (1 Ciclo Input Capture + 4 Ciclos Processamento)
//  - Throughput:    ~32 MSPS @ 160MHz
//  - Arquitetura:   Iterativa (Radix-8 consome 3 bits por ciclo)
//  - Segurança:     Entradas registradas para isolamento de Timing (Blindado)
//  - Otimização:    Mux de controle "achatado" para mapeamento direto em LUT4
//
// DIAGRAMA DE TEMPO:
//  Ciclo 0: START = 1, Dados nas entradas
//  Ciclo 1: Captura interna (Input Registering)
//  Ciclo 2: Setup Aritmético e Inicialização
//  Ciclo 3: Iteração 1 (Bits 0-2)
//  Ciclo 4: Iteração 2 (Bits 3-5)
//  Ciclo 5: Iteração 3 (Bits 6-7) -> DONE = 1, PRODUCT Válido
// ============================================================================

module booth_mult8 (
    // Controle Global
    input  wire                  clk,
    input  wire                  rst_n,

    // Interface de Controle
    input  wire                  start,        // Inicia a multiplicação (pulso)
    output reg                   done,         // Indica fim e dado válido (pulso)

    // Dados de Entrada
    input  wire signed [7:0]     multiplicand, // Operando A
    input  wire signed [7:0]     multiplier,   // Operando B
    input  wire [1:0]            sign_mode,    // [1]=Signed A, [0]=Signed B

    // Dados de Saída
    output wire signed [15:0]    product       // Resultado (A * B)
);

    // ========================================================================
    // PARÂMETROS E DEFINIÇÕES
    // ========================================================================
    localparam integer WIDTH      = 8;
    localparam integer SHIFT_BITS = 9;  // 3 iterações x 3 bits (Radix-8)
    localparam integer ACC_WIDTH  = 11; // 8 bits + 3 bits de guarda (overflow protection)
    localparam integer REG_WIDTH  = 21; // Largura total do registrador de deslocamento

    // ========================================================================
    // ESTÁGIO 1: ISOLAMENTO DE ENTRADA (TIMING BARRIER)
    // ------------------------------------------------------------------------
    // Registramos todas as entradas aqui. Isso desacopla o caminho crítico 
    // interno do multiplicador de qualquer lógica externa lenta.
    // ========================================================================
    reg                  r_start;
    reg [1:0]            r_sign_mode;
    reg signed [7:0]     r_multiplicand;
    reg signed [7:0]     r_multiplier;

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

    // ========================================================================
    // SINAIS INTERNOS E REGISTRADORES DE ESTADO
    // ========================================================================
    reg active;                         // Flag de operação em andamento
    reg [2:0] iter_shift;               // Contador One-Hot (100 -> 010 -> 001)
    
    reg signed [REG_WIDTH-1:0] prod_reg;      // Registrador principal (Acumulador + Multiplicador)
    reg signed [ACC_WIDTH-1:0] m_3x_reg;      // Cache para valor 3x
    reg signed [ACC_WIDTH-1:0] mcand_ext_reg; // Cache para Multiplicando estendido

    // ========================================================================
    // LÓGICA DE SETUP (CYCLE 1 - Pós Registro)
    // ------------------------------------------------------------------------
    // Prepara os operandos, estende sinais e pré-calcula o valor '3x'.
    // O 3x é calculado via soma (A + 2A) fora do loop crítico.
    // ========================================================================
    
    // Extensão de sinal condicional baseada no modo configurado
    wire sign_bit_a = r_sign_mode[1] & r_multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){sign_bit_a}}, r_multiplicand };

    // Somador dedicado para o caso difícil do Radix-8 (3 * M)
    wire signed [ACC_WIDTH-1:0] calc_3x = mcand_extended + (mcand_extended <<< 1);

    // Inicialização do Registrador de Produto:
    // [Acumulador Zeros] + [Sinal Multiplicador] + [Multiplicador] + [Bit Implícito Booth]
    wire sign_bit_b = r_sign_mode[0] & r_multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},                  // Acumulador limpo
        {(SHIFT_BITS-WIDTH){sign_bit_b}},   // Padding de sinal
        r_multiplier,                       // Multiplicador
        1'b0                                // Bit implícito -1 (Start bit)
    };

    // ========================================================================
    // LÓGICA BOOTH COMBINACIONAL (Caminho Crítico)
    // ------------------------------------------------------------------------
    // Decodifica os 4 bits atuais (3 bits + 1 overlap) e seleciona a operação.
    // ========================================================================
    
    // Janela de inspeção do Booth
    wire [3:0] booth_bits = prod_reg[3:0];
    
    // Parte superior do registrador onde a soma acontece
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    // Decodificador Booth Radix-8 Paralelo
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

    // Detecção de Subtração (MSB da janela Booth)
    wire inv = booth_bits[3] & ~(&booth_bits[2:0]); 

    // Geração dos Múltiplos (Shifts são apenas roteamento, custo zero)
    wire signed [ACC_WIDTH-1:0] m_1x = mcand_ext_reg;
    wire signed [ACC_WIDTH-1:0] m_2x = mcand_ext_reg <<< 1;
    wire signed [ACC_WIDTH-1:0] m_4x = mcand_ext_reg <<< 2;

    // Multiplexador "Achatado" (Flattened)
    // Implementado via lógica AND-OR bit a bit para reduzir níveis de lógica
    reg signed [ACC_WIDTH-1:0] mag_sel;
    always @(*) begin
        mag_sel = ({ACC_WIDTH{sel_1x}} & m_1x) |
                  ({ACC_WIDTH{sel_2x}} & m_2x) |
                  ({ACC_WIDTH{sel_3x}} & m_3x_reg) |
                  ({ACC_WIDTH{sel_4x}} & m_4x);
    end

    // ALU: Inversão Condicional (XOR) + Soma + Carry In (inv)
    wire signed [ACC_WIDTH-1:0] operand_inv = mag_sel ^ {ACC_WIDTH{inv}};
    wire signed [ACC_WIDTH-1:0] sum_result  = acc_upper + operand_inv + { {(ACC_WIDTH-1){1'b0}}, inv };

    // ========================================================================
    // LÓGICA SEQUENCIAL CENTRAL
    // ------------------------------------------------------------------------
    // Controla o fluxo de dados, deslocamento e sinalização de término.
    // ========================================================================
    
    // O produto final reside nos bits [16:1] do registrador interno
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
            // 'done' é um pulso de 1 ciclo
            done <= 1'b0;

            if (active) begin
                // OPERAÇÃO E SHIFT SIMULTÂNEOS
                // Atualiza a parte superior com a soma e desloca tudo 3 bits à direita (>>> 3)
                prod_reg   <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
                iter_shift <= iter_shift >> 1;
                
                // Verifica fim da contagem (Bit LSB do One-Hot)
                if (iter_shift[0]) begin
                    active <= 1'b0;
                    done   <= 1'b1; // Produto válido neste exato ciclo
                end

            end else if (r_start) begin
                // INÍCIO DA OPERAÇÃO
                active        <= 1'b1;
                iter_shift    <= 3'b100;       // Carrega contador para 3 iterações
                
                // Carrega Caches (vindos dos registros de isolamento)
                mcand_ext_reg <= mcand_extended;
                m_3x_reg      <= calc_3x;
                prod_reg      <= prod_reg_init;
            end
        end
    end

endmodule
`default_nettype wire
