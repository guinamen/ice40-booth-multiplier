`timescale 1ns / 1ps
`default_nettype none

module booth_mult8_core_pipelined #(
    parameter integer WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire signed [WIDTH-1:0] multiplicand,
    input  wire signed [WIDTH-1:0] multiplier,
    input  wire [1:0]            sign_mode,
    output wire signed [(2*WIDTH)-1:0] product,
    output reg                   done
);

    localparam integer SHIFT_BITS = WIDTH + 1;
    localparam integer ACC_WIDTH  = WIDTH + 3;
    localparam integer REG_WIDTH  = (2*WIDTH) + 5;

    // Estados da Máquina de Estados Finita (FSM)
    localparam [1:0] S_IDLE    = 2'b00;
    localparam [1:0] S_PREP_OP = 2'b01; // Decodifica e busca operando
    localparam [1:0] S_ACCUM   = 2'b10; // Soma e desloca

    reg [1:0] state;

    // ------------------------------------------------------------------------
    // FUNÇÕES (Reutilizadas)
    // ------------------------------------------------------------------------
    function automatic [ACC_WIDTH-1:0] f_calc_3x;
        input [WIDTH-1:0] val_in;
        input             s_bit;
        reg [ACC_WIDTH-1:0] val_ext;
    begin
        val_ext = { {(ACC_WIDTH-WIDTH){s_bit}}, val_in };
        f_calc_3x = val_ext + (val_ext <<< 1);
    end
    endfunction

    function automatic [ACC_WIDTH-1:0] f_extend_mcand;
        input [WIDTH-1:0] val_in;
        input             s_bit;
    begin
        f_extend_mcand = { {(ACC_WIDTH-WIDTH){s_bit}}, val_in };
    end
    endfunction

    function automatic [REG_WIDTH-1:0] f_init_prod_reg;
        input [WIDTH-1:0] mult_in;
        input             s_bit;
    begin
        f_init_prod_reg = {
            {ACC_WIDTH{1'b0}},
            s_bit,
            mult_in,
            1'b0
        };
    end
    endfunction

    function automatic [4:0] f_booth_decoder;
        input [3:0] window;
        reg [2:0] recoded;
    begin
        recoded = window[2:0] ^ {3{window[3]}};
        f_booth_decoder[4]   = window[3] & ~(&window[2:0]); // Inv bit
        f_booth_decoder[3:0] = 4'b0000;
        case (recoded)
            3'b001, 3'b010: f_booth_decoder[0] = 1'b1;
            3'b011, 3'b100: f_booth_decoder[1] = 1'b1;
            3'b101, 3'b110: f_booth_decoder[2] = 1'b1;
            3'b111:         f_booth_decoder[3] = 1'b1;
            default:        ;
        endcase
    end
    endfunction

    // Nova Função: Apenas seleciona o operando (SEM SOMAR)
    function automatic [ACC_WIDTH-1:0] f_select_op;
        input [ACC_WIDTH-1:0] val_1x;
        input [ACC_WIDTH-1:0] val_3x;
        input [4:0]           ctrl;
        reg [ACC_WIDTH-1:0]   magnitude;
    begin
        // Apenas Mux, sem soma. Muito rápido.
        magnitude = ({ACC_WIDTH{ctrl[0]}} & val_1x) |
                    ({ACC_WIDTH{ctrl[1]}} & (val_1x <<< 1)) |
                    ({ACC_WIDTH{ctrl[2]}} & val_3x) |
                    ({ACC_WIDTH{ctrl[3]}} & (val_1x <<< 2));

        // Aplica inversão condicional (Complemento de 1)
        f_select_op = magnitude ^ {ACC_WIDTH{ctrl[4]}};
    end
    endfunction

    // ------------------------------------------------------------------------
    // REGISTRADORES
    // ------------------------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] r_mcand_ext;
    reg signed [ACC_WIDTH-1:0] m_3x_reg;
    reg signed [REG_WIDTH-1:0] prod_reg;
    reg [2:0]                  iter_shift;

    // Registradores do Pipeline (O segredo da velocidade)
    reg signed [ACC_WIDTH-1:0] r_pipe_operand; // Guarda o valor a ser somado
    reg                        r_pipe_inv;     // Guarda o bit de carry/inversão

    // Wires auxiliares
    wire w_sign_bit_a = sign_mode[1] & multiplicand[WIDTH-1];
    wire w_sign_bit_b = sign_mode[0] & multiplier[WIDTH-1];

    wire [4:0] w_booth_ctrl = f_booth_decoder(prod_reg[3:0]);

    // O somador final (simples e limpo)
    wire signed [ACC_WIDTH-1:0] w_sum_result =
        prod_reg[REG_WIDTH-1 : SHIFT_BITS+1] + // Acumulador atual
        r_pipe_operand +                       // Operando capturado no ciclo anterior
        { {(ACC_WIDTH-1){1'b0}}, r_pipe_inv }; // Bit de carry in

    assign product = prod_reg[WIDTH*2:1];

    // ------------------------------------------------------------------------
    // FSM PIPELINED
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            done            <= 1'b0;
            iter_shift      <= 3'b0;
            r_mcand_ext     <= {ACC_WIDTH{1'b0}};
            m_3x_reg        <= {ACC_WIDTH{1'b0}};
            prod_reg        <= {REG_WIDTH{1'b0}};
            r_pipe_operand  <= {ACC_WIDTH{1'b0}};
            r_pipe_inv      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        // Pré-cálculos iniciais (Igual à versão anterior)
                        r_mcand_ext <= f_extend_mcand(multiplicand, w_sign_bit_a);
                        m_3x_reg    <= f_calc_3x(multiplicand, w_sign_bit_a);
                        prod_reg    <= f_init_prod_reg(multiplier, w_sign_bit_b);

                        iter_shift  <= 3'b100;
                        state       <= S_PREP_OP; // Vai para preparação
                    end
                end

                S_PREP_OP: begin
                    // CICLO 1: Apenas olha os bits e carrega o operando.
                    // Não faz nenhuma soma aqui. Caminho crítico = Mux.
                    r_pipe_operand <= f_select_op(r_mcand_ext, m_3x_reg, w_booth_ctrl);
                    r_pipe_inv     <= w_booth_ctrl[4]; // Bit de inversão

                    state <= S_ACCUM;
                end

                S_ACCUM: begin
                    // CICLO 2: Apenas soma e desloca.
                    // Caminho crítico = Somador + Shift (muito rápido no iCE40).
                    prod_reg   <= { {3{w_sum_result[ACC_WIDTH-1]}}, w_sum_result, prod_reg[SHIFT_BITS:3] };
                    iter_shift <= iter_shift >> 1;

                    if (iter_shift[0]) begin // Última iteração?
                        // Se era o bit 1 (que virou 0 após shift), terminamos
                        // Mas espera, iter_shift >> 1 acontece AO MESMO TEMPO.
                        // Se iter_shift atual for 1, o próximo será 0.
                    end

                    // Lógica de loop correta:
                    if (iter_shift[0]) begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end else begin
                        state <= S_PREP_OP; // Volta para buscar o próximo operando
                    end
                end
            endcase
        end
    end
endmodule
`default_nettype wire
