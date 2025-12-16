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
