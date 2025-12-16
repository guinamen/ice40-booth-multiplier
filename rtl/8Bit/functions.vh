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

// =========================================================================
// FUNÇÕES ARITMÉTICAS MODULARIZADAS
// =========================================================================

// -------------------------------------------------------------------------
// 1. FUNÇÃO BASE (KERNEL) - O que há de comum
// Realiza apenas a seleção (MUX) e a inversão (XOR)
// -------------------------------------------------------------------------
function automatic [ACC_WIDTH-1:0] f_booth_mux_inv;
    input [ACC_WIDTH-1:0] val_1x;
    input [ACC_WIDTH-1:0] val_3x;
    input [4:0]           ctrl;   // {inv, sel_4x, sel_3x, sel_2x, sel_1x}
    reg [ACC_WIDTH-1:0]   magnitude;
begin
    // Lógica de Seleção (Mux One-Hot)
    magnitude = ({ACC_WIDTH{ctrl[0]}} & val_1x)          | // 1x
                ({ACC_WIDTH{ctrl[1]}} & (val_1x <<< 1))  | // 2x
                ({ACC_WIDTH{ctrl[2]}} & val_3x)          | // 3x
                ({ACC_WIDTH{ctrl[3]}} & (val_1x <<< 2));   // 4x

    // Lógica de Inversão (Complemento de 1)
    // Se ctrl[4] for 1, inverte todos os bits.
    f_booth_mux_inv = magnitude ^ {ACC_WIDTH{ctrl[4]}};
end
endfunction

// -------------------------------------------------------------------------
// 2. FUNÇÃO SELECT OP (Para Pipeline)
// Wrapper simples: Apenas retorna o operando preparado.
// -------------------------------------------------------------------------
function automatic [ACC_WIDTH-1:0] f_select_op;
    input [ACC_WIDTH-1:0] val_1x;
    input [ACC_WIDTH-1:0] val_3x;
    input [4:0]           ctrl;
begin
    // Reutiliza a lógica comum
    f_select_op = f_booth_mux_inv(val_1x, val_3x, ctrl);
end
endfunction

// -------------------------------------------------------------------------
// 3. FUNÇÃO ALU CALC (Para Ciclo Único / V3)
// Obtém o operando da função base e realiza a soma completa.
// -------------------------------------------------------------------------
function automatic [ACC_WIDTH-1:0] f_alu_calc;
    input [ACC_WIDTH-1:0] acc_val;
    input [ACC_WIDTH-1:0] val_1x;
    input [ACC_WIDTH-1:0] val_3x;
    input [4:0]           ctrl;
    reg [ACC_WIDTH-1:0]   operand_prepared;
begin
    // Passo 1: Obtém o operando (Mux + Inversão) da função comum
    operand_prepared = f_booth_mux_inv(val_1x, val_3x, ctrl);

    // Passo 2: Soma Final (Acumulador + Operando + Carry In)
    // O bit 'ctrl[4]' (inv) age como o +1 do Complemento de 2
    f_alu_calc = acc_val + operand_prepared + { {(ACC_WIDTH-1){1'b0}}, ctrl[4] };
end
endfunction
