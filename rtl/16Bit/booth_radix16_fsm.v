`timescale 1ns / 1ps

/**
 * Módulo: booth_radix16
 * --------------------
 * Multiplicador assinado de 16 bits utilizando o algoritmo de Booth Radix-16.
 * 
 * Características:
 * - Processa 4 bits por iteração (Radix-16).
 * - Pipeline de 2 estágios para pré-cálculo de múltiplos (otimização de timing).
 * - Pipeline na decodificação de Booth para suportar frequências elevadas (>150 MHz).
 * - Latência total: 9 ciclos de clock.
 */
module booth_radix16 #(
    parameter WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,                  // Reset assíncrono (ativo baixo)
    input  wire start,                  // Sinal de início de operação
    input  wire signed [WIDTH-1:0] multiplicand,
    input  wire signed [WIDTH-1:0] multiplier,
    output reg  signed [2*WIDTH-1:0] product,
    output reg  done                    // Pulsa em 1 quando o cálculo termina
);

    //--------------------------------------------------------------------------
    // DEFINIÇÃO DE ESTADOS (FSM)
    //--------------------------------------------------------------------------
    localparam IDLE      = 3'd0;
    localparam PRECALC_1 = 3'd1; // Ciclo 1: Shifts para múltiplos de potência de 2
    localparam PRECALC_2 = 3'd2; // Ciclo 2: Somas/Subtrações para múltiplos ímpares
    localparam LOAD_PIPE = 3'd3; // Carrega o primeiro dígito no pipeline
    localparam COMPUTE   = 3'd4; // Loop de Acumulação e Shift (4 iterações)
    localparam FINISH    = 3'd5; // Disponibiliza o resultado final

    reg [2:0] state;
    reg [3:0] iter_oh;           // Controle de iterações via One-Hot (0001 -> 1000)

    //--------------------------------------------------------------------------
    // SINCRONIZAÇÃO DE RESET
    //--------------------------------------------------------------------------
    // Bridge de reset para evitar caminhos críticos em redes globais da FPGA
    reg rst_sync_n, rst_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {rst_sync_n, rst_q} <= 2'b00;
        else        {rst_sync_n, rst_q} <= {rst_q, 1'b1};
    end

    //--------------------------------------------------------------------------
    // REGISTRADORES INTERNOS
    //--------------------------------------------------------------------------
    reg signed [WIDTH-1:0] m_cap;           // Captura do multiplicando
    reg [WIDTH-1:0] q_cap;                 // Captura do multiplicador
    
    // Acumulador A (Parte Alta) e Q_low (Parte Baixa resultante)
    // WIDTH+5 bits para suportar M8 (WIDTH+3) e evitar overflow na soma parcial
    reg signed [WIDTH+4:0] A;
    reg [WIDTH-1:0] Q_low;
    
    reg [WIDTH-1:0] Q_sr;                  // Shift Register do multiplicador
    reg Q_neg1;                            // Bit auxiliar de Booth (Q_{-1})

    // Múltiplos pré-calculados (1M até 8M)
    reg signed [WIDTH+4:0] M1, M2, M3, M4, M5, M6, M7, M8;

    // Registradores do Pipeline de Decodificação
    reg signed [WIDTH+4:0] p_mux_reg;      // Múltiplo selecionado para o ciclo atual
    reg negate_reg;                        // Define se o múltiplo deve ser subtraído

    //--------------------------------------------------------------------------
    // LÓGICA DE SELEÇÃO BOOTH RADIX-16
    //--------------------------------------------------------------------------
    // A janela de Booth Radix-16 observa 5 bits: {bits[3:0], bit_anterior}
    wire [4:0] win = {Q_sr[3:0], Q_neg1};
    reg signed [WIDTH+4:0] next_p_mux;
    reg next_negate;

    always @(*) begin
        next_negate = win[4]; // MSB da janela define o sinal (regra de Booth)
        case (win)
            // Tabela Radix-16: Seleciona o múltiplo com base no dígito de Booth
            5'b00000, 5'b11111: next_p_mux = 0;   // 0
            5'b00001, 5'b00010, 
            5'b11110, 5'b11101: next_p_mux = M1;  // +/- 1
            5'b00011, 5'b00100, 
            5'b11100, 5'b11011: next_p_mux = M2;  // +/- 2
            5'b00101, 5'b00110, 
            5'b11010, 5'b11001: next_p_mux = M3;  // +/- 3
            5'b00111, 5'b01000, 
            5'b11000, 5'b10111: next_p_mux = M4;  // +/- 4
            5'b01001, 5'b01010, 
            5'b10110, 5'b10101: next_p_mux = M5;  // +/- 5
            5'b01011, 5'b01100, 
            5'b10100, 5'b10011: next_p_mux = M6;  // +/- 6
            5'b01101, 5'b01110, 
            5'b10010, 5'b10001: next_p_mux = M7;  // +/- 7
            5'b01111, 5'b10000: next_p_mux = M8;  // +/- 8
            default:            next_p_mux = 0;
        endcase
    end

    //--------------------------------------------------------------------------
    // UNIDADE ARITMÉTICA (ALU)
    //--------------------------------------------------------------------------
    // Implementa: sum = A + (negate ? -M : M)
    // A inversão é feita via complemento de 2 (~valor + 1)
    wire signed [WIDTH+4:0] p_val = negate_reg ? ~p_mux_reg : p_mux_reg;
    wire signed [WIDTH+4:0] sum   = A + p_val + (negate_reg ? 1'b1 : 1'b0);

    //--------------------------------------------------------------------------
    // MÁQUINA DE ESTADOS (FSM)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_sync_n) begin
            state      <= IDLE;
            done       <= 0;
            product    <= 0;
            A          <= 0;
            Q_low      <= 0;
            Q_sr       <= 0;
            Q_neg1     <= 0;
            p_mux_reg  <= 0;
            negate_reg <= 0;
            iter_oh    <= 4'b0000;
        end else begin
            case (state)
                
                // Aguarda o sinal de start
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        m_cap <= multiplicand;
                        q_cap <= multiplier;
                        state <= PRECALC_1;
                    end
                end

                // Passo 1 de pré-cálculo: Operações simples (shift)
                PRECALC_1: begin
                    M1 <= {{5{m_cap[WIDTH-1]}}, m_cap};
                    M2 <= {{5{m_cap[WIDTH-1]}}, m_cap} << 1;
                    M4 <= {{5{m_cap[WIDTH-1]}}, m_cap} << 2;
                    M8 <= {{5{m_cap[WIDTH-1]}}, m_cap} << 3;
                    
                    A      <= 0;
                    Q_sr   <= q_cap;
                    Q_neg1 <= 1'b0;
                    Q_low  <= 0;
                    state  <= PRECALC_2;
                end

                // Passo 2 de pré-cálculo: Operações complexas (soma/sub)
                PRECALC_2: begin
                    M3 <= M2 + M1;
                    M5 <= M4 + M1;
                    M6 <= M4 + M2;
                    M7 <= M8 - M1;
                    state <= LOAD_PIPE;
                end

                // Carrega o pipeline com o primeiro dígito de Booth
                LOAD_PIPE: begin
                    p_mux_reg  <= next_p_mux;
                    negate_reg <= next_negate;

                    Q_neg1     <= Q_sr[3]; // Salva o bit para a próxima janela
                    Q_sr       <= Q_sr >> 4;
                    iter_oh    <= 4'b0001;
                    state      <= COMPUTE;
                end

                // Loop de computação: Acumula e desloca 4 bits por ciclo
                COMPUTE: begin
                    // 1. Acumulação e Shift Aritmético (Preserva o sinal de 'sum')
                    A     <= sum >>> 4;
                    // 2. Coleta os 4 bits menos significativos que "saem" de A
                    Q_low <= {sum[3:0], Q_low[WIDTH-1:4]};

                    // 3. Avança o pipeline para o próximo dígito
                    p_mux_reg  <= next_p_mux;
                    negate_reg <= next_negate;
                    Q_neg1     <= Q_sr[3];
                    Q_sr       <= Q_sr >> 4;
                    
                    // 4. Controle de iteração One-Hot
                    iter_oh    <= {iter_oh[2:0], 1'b0};

                    if (iter_oh[3]) state <= FINISH;
                end

                // Finaliza e concatena o resultado de 32 bits
                FINISH: begin
                    // A[15:0] contém a parte alta final após o último shift
                    product <= {A[15:0], Q_low};
                    done <= 1;
                    if (!start) state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
