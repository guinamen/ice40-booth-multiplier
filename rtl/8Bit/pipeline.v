`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Multiplicador Booth Radix-4 Otimizado para 250MHz
//==============================================================================
// Implementa multiplicação 8x8 bits usando algoritmo de Booth Radix-4
// com pipeline de 6 estágios otimizado para FPGAs iCE40
//
// Características:
// - Latência: 6 ciclos de clock
// - Throughput: 1 resultado por ciclo (fully pipelined)
// - Suporta multiplicação signed/unsigned via controle 'sm'
// - Usa técnica XOR+correção para negação eficiente
//
// Autor: Otimizado para iCE40 @ 250MHz
//==============================================================================

module booth_core_250mhz (
    input  wire        clk,      // Clock principal
    input  wire        v_in,     // Valid input - indica dado válido na entrada
    input  wire [7:0]  a,        // Operando A (multiplicando)
    input  wire [7:0]  b,        // Operando B (multiplicador)
    input  wire [1:0]  sm,       // Sign Mode: [1]=A signed, [0]=B signed
    output reg  [15:0] p,        // Produto (resultado da multiplicação)
    output reg         v_out     // Valid output - indica resultado válido
);

    //==========================================================================
    // ESTÁGIO 1: Captura de Entrada e Extensão de Sinal
    //==========================================================================
    // Captura os operandos e estende para 10/11 bits conforme necessário
    // - Extensão de sinal para operandos signed
    // - Zero-extension para operandos unsigned
    // - Adiciona bit extra no LSB de B para algoritmo de Booth
    
    reg signed [9:0]  s1_a;      // A estendido para 10 bits
    reg        [10:0] s1_b;      // B estendido para 11 bits (inclui bit 0 extra)
    reg               s1_v;      // Valid pipeline
    
    always @(posedge clk) begin
        // Extensão de A: signed (replica MSB) ou unsigned (adiciona zeros)
        s1_a <= sm[1] ? $signed({{2{a[7]}}, a}) : $signed({2'b00, a});
        
        // Extensão de B: signed/unsigned + bit LSB=0 para Booth
        // Formato final: [sign_ext, sign_ext, b[7:0], 1'b0]
        s1_b <= {(sm[0] ? {2{b[7]}} : 2'b00), b, 1'b0};
        
        s1_v <= v_in;
    end
    
    //==========================================================================
    // ESTÁGIO 2: Geração de Sinais de Controle Booth
    //==========================================================================
    // Pré-calcula os valores necessários (A e 2A) e gera os sinais de
    // controle para seleção dos produtos parciais usando Booth Radix-4
    //
    // Booth Radix-4 examina triplets de bits [b[i+1], b[i], b[i-1]]:
    //   000, 111 → 0    (sem alteração)
    //   001, 010 → +A   (adiciona A)
    //   011      → +2A  (adiciona 2A)
    //   100      → -2A  (subtrai 2A)
    //   101, 110 → -A   (subtrai A)
    
    reg signed [9:0]  s2_p1;     // Armazena A
    reg signed [9:0]  s2_p2;     // Armazena 2A (shift left)
    reg [4:0]         s2_sel1x;  // Seleção de A (5 produtos parciais)
    reg [4:0]         s2_sel2x;  // Seleção de 2A (5 produtos parciais)
    reg [4:0]         s2_neg;    // Bit de negação (5 produtos parciais)
    reg               s2_v;      // Valid pipeline
    
    always @(posedge clk) begin
        s2_v  <= s1_v;
        s2_p1 <= s1_a;           // Mantém A
        s2_p2 <= s1_a << 1;      // Calcula 2A
        
        // Decodificação Booth para PP0 (bits [2:0] de s1_b)
        s2_sel1x[0] <= s1_b[0] ^ s1_b[1];                                    // Seleciona A
        s2_sel2x[0] <= (s1_b[2] ^ s1_b[1]) & ~(s1_b[1] ^ s1_b[0]);         // Seleciona 2A
        s2_neg[0]   <= s1_b[2];                                             // Bit de sinal
        
        // Decodificação Booth para PP1 (bits [4:2] de s1_b)
        s2_sel1x[1] <= s1_b[2] ^ s1_b[3];
        s2_sel2x[1] <= (s1_b[4] ^ s1_b[3]) & ~(s1_b[3] ^ s1_b[2]);
        s2_neg[1]   <= s1_b[4];
        
        // Decodificação Booth para PP2 (bits [6:4] de s1_b)
        s2_sel1x[2] <= s1_b[4] ^ s1_b[5];
        s2_sel2x[2] <= (s1_b[6] ^ s1_b[5]) & ~(s1_b[5] ^ s1_b[4]);
        s2_neg[2]   <= s1_b[6];
        
        // Decodificação Booth para PP3 (bits [8:6] de s1_b)
        s2_sel1x[3] <= s1_b[6] ^ s1_b[7];
        s2_sel2x[3] <= (s1_b[8] ^ s1_b[7]) & ~(s1_b[7] ^ s1_b[6]);
        s2_neg[3]   <= s1_b[8];
        
        // Decodificação Booth para PP4 (bits [10:8] de s1_b)
        s2_sel1x[4] <= s1_b[8] ^ s1_b[9];
        s2_sel2x[4] <= (s1_b[10] ^ s1_b[9]) & ~(s1_b[9] ^ s1_b[8]);
        s2_neg[4]   <= s1_b[10];
    end
    
    //==========================================================================
    // ESTÁGIO 3: Geração de Produtos Parciais (Partial Products)
    //==========================================================================
    // Seleciona entre 0, A ou 2A para cada produto parcial e aplica inversão
    // XOR quando necessário (em vez de complemento de 2 completo)
    //
    // TÉCNICA DE OTIMIZAÇÃO:
    // Em vez de calcular complemento de 2 (-A = ~A + 1), usamos apenas
    // inversão XOR (~A) neste estágio. A correção (+1) será adicionada
    // no estágio S4 através de um vetor de correção. Isso economiza lógica
    // e reduz o caminho crítico.
    
    reg [9:0]         s3_pp0;    // Produto parcial 0 (peso 2^0)
    reg [9:0]         s3_pp1;    // Produto parcial 1 (peso 2^2)
    reg [9:0]         s3_pp2;    // Produto parcial 2 (peso 2^4)
    reg [9:0]         s3_pp3;    // Produto parcial 3 (peso 2^6)
    reg [9:0]         s3_pp4;    // Produto parcial 4 (peso 2^8)
    reg [4:0]         s3_neg;    // Bits de negação (para correção em S4)
    reg               s3_v;      // Valid pipeline
    
    always @(posedge clk) begin
        s3_v   <= s2_v;
        s3_neg <= s2_neg;  // Propaga bits de negação para correção posterior
        
        // Para cada produto parcial:
        // 1. Seleciona entre A (sel1x) ou 2A (sel2x) usando OR
        // 2. Aplica inversão XOR se neg=1
        // Nota: sel1x e sel2x são mutuamente exclusivos por construção
        
        s3_pp0 <= (({10{s2_sel1x[0]}} & s2_p1) | ({10{s2_sel2x[0]}} & s2_p2)) ^ {10{s2_neg[0]}};
        s3_pp1 <= (({10{s2_sel1x[1]}} & s2_p1) | ({10{s2_sel2x[1]}} & s2_p2)) ^ {10{s2_neg[1]}};
        s3_pp2 <= (({10{s2_sel1x[2]}} & s2_p1) | ({10{s2_sel2x[2]}} & s2_p2)) ^ {10{s2_neg[2]}};
        s3_pp3 <= (({10{s2_sel1x[3]}} & s2_p1) | ({10{s2_sel2x[3]}} & s2_p2)) ^ {10{s2_neg[3]}};
        s3_pp4 <= (({10{s2_sel1x[4]}} & s2_p1) | ({10{s2_sel2x[4]}} & s2_p2)) ^ {10{s2_neg[4]}};
    end
    
    //==========================================================================
    // ESTÁGIO 4: Primeiro Nível de Redução (Árvore de Somadores)
    //==========================================================================
    // Alinha os produtos parciais nas posições corretas e realiza a primeira
    // camada de soma. Também adiciona o vetor de correção para converter
    // as inversões XOR do estágio S3 em complemento de 2 são corretas.
    //
    // Árvore de soma balanceada:
    //   - sum01: PP0 + PP1 (alinhado em 2 bits)
    //   - sum23: PP2 + PP3 (alinhados em 4 e 6 bits)
    //   - pp4_corr: PP4 + vetor de correção
    
    reg signed [19:0] s4_sum01;     // Soma de PP0 e PP1
    reg signed [19:0] s4_sum23;     // Soma de PP2 e PP3
    reg signed [19:0] s4_pp4_corr;  // PP4 + vetor de correção
    reg               s4_v;         // Valid pipeline
    
    always @(posedge clk) begin
        s4_v <= s3_v;
        
        // Soma PP0 + PP1 (PP1 deslocado 2 bits à esquerda)
        // Sign extension para 20 bits
        s4_sum01 <= $signed({{10{s3_pp0[9]}}, s3_pp0}) + 
                    $signed({{8{s3_pp1[9]}}, s3_pp1, 2'b00});
        
        // Soma PP2 + PP3 (PP2 em 4 bits, PP3 em 6 bits)
        s4_sum23 <= $signed({{6{s3_pp2[9]}}, s3_pp2, 4'b0000}) + 
                    $signed({{4{s3_pp3[9]}}, s3_pp3, 6'b000000});
        
        // PP4 (deslocado 8 bits) + Vetor de Correção
        // O vetor de correção adiciona +1 nas posições apropriadas para
        // converter a inversão XOR (~A) em complemento de 2 (-A = ~A + 1)
        // Cada bit s3_neg[i] indica se PP[i] foi invertido
        // Correção: bit na posição 2*i para cada PP[i] negado
        s4_pp4_corr <= $signed({{2{s3_pp4[9]}}, s3_pp4, 8'b00000000}) +
                       $signed({11'b0, s3_neg[4], 1'b0, s3_neg[3], 1'b0, 
                               s3_neg[2], 1'b0, s3_neg[1], 1'b0, s3_neg[0]});
    end
    
    //==========================================================================
    // ESTÁGIO 5: Segundo Nível de Redução
    //==========================================================================
    // Reduz de 3 termos para 2 termos, preparando para soma final
    
    reg signed [19:0] s5_sumA;   // Soma dos dois primeiros grupos
    reg signed [19:0] s5_sumB;   // PP4 corrigido
    reg               s5_v;      // Valid pipeline
    
    always @(posedge clk) begin
        s5_v    <= s4_v;
        s5_sumA <= s4_sum01 + s4_sum23;  // Combina os primeiros 4 PPs
        s5_sumB <= s4_pp4_corr;           // Mantém PP4+correção
    end
    
    //==========================================================================
    // ESTÁGIO 6: Soma Final e Saída
    //==========================================================================
    // Combina os dois termos restantes e gera o resultado final de 16 bits
    
    always @(posedge clk) begin
        v_out <= s5_v;
        p     <= s5_sumA[15:0] + s5_sumB[15:0];  // Trunca para 16 bits
    end

endmodule

//==============================================================================
// NOTAS DE IMPLEMENTAÇÃO
//==============================================================================
// 
// 1. BOOTH RADIX-4:
//    - Reduz 5 produtos parciais (em vez de 8 para Radix-2)
//    - Cada PP processa 2 bits do multiplicador
//
// 2. TÉCNICA XOR + CORREÇÃO:
//    - Inversão XOR é mais rápida que complemento de 2 completo
//    - Vetor de correção adiciona os +1 necessários em S4
//    - Economiza lógica e melhora timing
//
// 3. ÁRVORE DE SOMA BALANCEADA:
//    - 3 somadores em S4 (em paralelo)
//    - 2 somadores em S5 (reduz para 2 termos)
//    - 1 somador em S6 (resultado final)
//    - Profundidade logarítmica minimiza latência
//
// 4. OTIMIZAÇÕES PARA iCE40:
//    - Loop for desenrolado (evita confusão em síntese)
//    - Registradores intermediários bem balanceados
//    - Aproveitamento de LUT4 para lógica Booth
//
//==============================================================================
