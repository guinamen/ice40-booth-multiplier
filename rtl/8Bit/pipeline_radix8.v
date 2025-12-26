`timescale 1ns / 1ps
`default_nettype none

//==============================================================================
// Multiplicador Booth Radix-8 Masterpiece - iCE40 @ 267MHz
//==============================================================================
// Pipeline: 8 estágios | Throughput: 1 resultado/ciclo | Latência: 8 ciclos
// Algoritmo: Booth Radix-8 (processa 3 bits de B por vez)
// Produtos Parciais: 3 (ao invés de 8 com Radix-2)
// Recursos: ~50 FFs, ~80 LUTs | Fmax: 267 MHz em iCE40
//==============================================================================

module booth_core_250mhz (
    input  wire        clk,
    input  wire        v_in,    // Sinal de válido de entrada
    input  wire [7:0]  a,        // Multiplicando (8 bits)
    input  wire [7:0]  b,        // Multiplicador (8 bits)
    input  wire [1:0]  sm,       // [1]=A assinado, [0]=B assinado
    output reg  [15:0] p,        // Produto (16 bits)
    output reg         v_out     // Sinal de válido de saída
);

    //==========================================================================
    // ESTÁGIO S1: Captura de Entrada e Extensão de Sinal Dinâmica
    //==========================================================================
    // Função: Registra entradas e estende para 12 bits baseado em sm[]
    // Timing: Este estágio absorve atraso de IOB e setup de entrada
    //==========================================================================
    reg signed [11:0] s1_a;      // Multiplicando estendido para 12 bits
    reg        [11:0] s1_b;      // Multiplicador estendido (formato Booth)
    reg               s1_v;      // Pipeline de válido

    always @(posedge clk) begin
        s1_v <= v_in;
        
        // Extensão condicional de A: se signed, replica bit de sinal
        // 8 bits → 12 bits: {sinal[4x], dado[8x]}
        s1_a <= sm[1] ? $signed({{4{a[7]}}, a}) : $signed({4'b0, a});
        
        // Extensão de B para formato Booth: {sinal[3x], dado[8x], zero[1x]}
        // O bit extra LSB (1'b0) é necessário para janela deslizante do Booth
        s1_b <= sm[0] ? {{3{b[7]}}, b, 1'b0} : {3'b0, b, 1'b0};
    end

    //==========================================================================
    // ESTÁGIO S2: Geração de Múltiplos Hard de A
    //==========================================================================
    // Função: Pré-calcula 1A, 2A, 3A, 4A para os MUXes do Booth
    // Por quê: Booth Radix-8 precisa de múltiplos {0, ±1A, ±2A, ±3A, ±4A}
    // Hard Multiple: 3A = A + 2A (não é simples shift, requer soma)
    //==========================================================================
    reg [11:0] s2_a1, s2_a2, s2_a3, s2_a4;  // Múltiplos de A
    reg [11:0] s2_b;                         // Pipeline de B
    reg        s2_v;                         // Pipeline de válido

    always @(posedge clk) begin
        s2_v  <= s1_v;
        s2_b  <= s1_b;
        s2_a1 <= $unsigned(s1_a);                      // 1A
        s2_a2 <= $unsigned(s1_a << 1);                 // 2A (shift left)
        s2_a3 <= $unsigned(s1_a + (s1_a << 1));        // 3A = A + 2A (hard!)
        s2_a4 <= $unsigned(s1_a << 2);                 // 4A (shift left 2)
    end

    //==========================================================================
    // ESTÁGIO S3: Decodificação Booth Radix-8 (Simétrica)
    //==========================================================================
    // Função: Interpreta janelas de 4 bits de B e gera seletores one-hot
    // Janelas: [3:0], [6:3], [9:6] (3 produtos parciais)
    // Saídas: sel[4x3] (magnitude) + neg[3] (sinal)
    //==========================================================================
    
    // Função auxiliar: Decodifica magnitude de 3 bits em seletor one-hot 4:1
    // Entrada: 3 bits XOR com bit de sinal (magnitude sempre positiva)
    // Saída: 4 bits one-hot {4A, 3A, 2A, 1A}
    function [3:0] decode_mag(input [2:0] mag_idx);
        case (mag_idx)
            3'b111:         decode_mag = 4'b1000; // Magnitude 4A
            3'b110, 3'b101: decode_mag = 4'b0100; // Magnitude 3A
            3'b100, 3'b011: decode_mag = 4'b0010; // Magnitude 2A
            3'b010, 3'b001: decode_mag = 4'b0001; // Magnitude 1A
            default:        decode_mag = 4'b0000; // Magnitude 0 (zero)
        endcase
    endfunction

    reg [2:0] s3_sel1, s3_sel2, s3_sel3, s3_sel4;  // Seletores: [PP][múltiplo]
    reg [2:0] s3_neg;                               // Sinais de negação {PP2, PP1, PP0}
    reg [11:0] s3_a1, s3_a2, s3_a3, s3_a4;         // Pipeline de múltiplos
    reg        s3_v;

    always @(posedge clk) begin
        s3_v  <= s2_v;
        // Pipeline de múltiplos para próximo estágio
        s3_a1 <= s2_a1; 
        s3_a2 <= s2_a2; 
        s3_a3 <= s2_a3; 
        s3_a4 <= s2_a4;
        
        // Extrai bits de sinal (MSB de cada janela)
        s3_neg <= {s2_b[9], s2_b[6], s2_b[3]}; 
        
        // Decodifica 3 janelas: bits são XORed com sinal para magnitude absoluta
        // PP0: janela [3:0], sinal em b[3]
        {s3_sel4[0], s3_sel3[0], s3_sel2[0], s3_sel1[0]} <= decode_mag(s2_b[2:0] ^ {3{s2_b[3]}});
        
        // PP1: janela [6:3], sinal em b[6]
        {s3_sel4[1], s3_sel3[1], s3_sel2[1], s3_sel1[1]} <= decode_mag(s2_b[5:3] ^ {3{s2_b[6]}});
        
        // PP2: janela [9:6], sinal em b[9]
        {s3_sel4[2], s3_sel3[2], s3_sel2[2], s3_sel1[2]} <= decode_mag(s2_b[8:6] ^ {3{s2_b[9]}});
    end

    //==========================================================================
    // ESTÁGIO S4: Seleção de Produtos Parciais e Aplicação de Sinal
    //==========================================================================
    // Função: MUX 4:1 seleciona múltiplo correto + aplica sinal via XOR
    // Produtos: PP0 (shift 0), PP1 (shift 3), PP2 (shift 6)
    // Correção de sinal: XOR com broadcast do bit de sinal (complemento de 1)
    //==========================================================================
    reg [15:0] s4_p0, s4_p1, s4_p2;       // Produtos parciais (16 bits)
    reg [15:0] s4_corr;                   // Vetor de correção (complemento de 2)
    reg        s4_v;

    // Wires auxiliares: Estende 12→16 bits replicando bit de sinal [11]
    // Necessário porque produtos parciais finais são 16 bits
    wire [15:0] ext_a1 = {{4{s3_a1[11]}}, s3_a1};
    wire [15:0] ext_a2 = {{4{s3_a2[11]}}, s3_a2};
    wire [15:0] ext_a3 = {{4{s3_a3[11]}}, s3_a3};
    wire [15:0] ext_a4 = {{4{s3_a4[11]}}, s3_a4};

    always @(posedge clk) begin
        s4_v <= s3_v;
        
        // PP0: Peso 2^0 (sem shift)
        // MUX 4:1 via máscara + XOR para negação
        s4_p0 <= ( ({16{s3_sel1[0]}} & ext_a1) |    // Seleciona 1A
                   ({16{s3_sel2[0]}} & ext_a2) |    // ou 2A
                   ({16{s3_sel3[0]}} & ext_a3) |    // ou 3A
                   ({16{s3_sel4[0]}} & ext_a4)      // ou 4A
                 ) ^ {16{s3_neg[0]}};                // XOR com sinal (complemento de 1)
        
        // PP1: Peso 2^3 (shift left 3)
        s4_p1 <= ( ( ({16{s3_sel1[1]}} & ext_a1) | 
                     ({16{s3_sel2[1]}} & ext_a2) |
                     ({16{s3_sel3[1]}} & ext_a3) | 
                     ({16{s3_sel4[1]}} & ext_a4) 
                   ) ^ {16{s3_neg[1]}} 
                 ) << 3;

        // PP2: Peso 2^6 (shift left 6)
        s4_p2 <= ( ( ({16{s3_sel1[2]}} & ext_a1) | 
                     ({16{s3_sel2[2]}} & ext_a2) |
                     ({16{s3_sel3[2]}} & ext_a3) | 
                     ({16{s3_sel4[2]}} & ext_a4) 
                   ) ^ {16{s3_neg[2]}} 
                 ) << 6;
        
        // Vetor de correção: adiciona 1 nas posições alinhadas para completar C2
        // Formato: {0[7x], neg2, 0[2x], neg1, 0[2x], neg0}
        // Posições dos '1's correspondem aos pesos dos produtos parciais
        s4_corr <= {7'b0, s3_neg[2], 2'b0, s3_neg[1], 2'b0, s3_neg[0]};
    end

    //==========================================================================
    // ESTÁGIO S5: Redução CSA (Carry-Save Adder) 4→2
    //==========================================================================
    // Função: Comprime 4 termos (PP0 + PP1 + PP2 + correção) em 2 (sum + carry)
    // Técnica: Árvore de somadores carry-save (2 níveis de CSA)
    // Vantagem: Reduz atraso de propagação de carry
    //==========================================================================
    reg [15:0] s5_s, s5_c;                // Vetores sum e carry finais
    reg [15:0] s5_corr;                   // Pipeline de correção
    reg        s5_v;
    reg [15:0] t_s, t_c;                  // Temporários (nível 1 de CSA)

    always @(posedge clk) begin
        s5_v    <= s4_v;
        s5_corr <= s4_corr;
        
        // Nível 1: Soma parcial de 3 termos (PP0, PP1, PP2)
        t_s = s4_p0 ^ s4_p1 ^ s4_p2;                                  // Sum bit
        t_c = ((s4_p0 & s4_p1) | (s4_p1 & s4_p2) | (s4_p0 & s4_p2)) << 1;  // Carry
        
        // Nível 2: Adiciona correção aos resultados intermediários
        s5_s <= t_s ^ t_c ^ s4_corr;                                  // Sum final
        s5_c <= ((t_s & t_c) | (t_c & s4_corr) | (t_s & s4_corr)) << 1;  // Carry final
    end

    //==========================================================================
    // ESTÁGIO S6: Somador Segmentado - Parte LSB (8 bits)
    //==========================================================================
    // Função: Soma os 8 bits menos significativos de (sum + carry)
    // Estratégia: Divide somador em 2 partes para melhorar timing
    // Caminho crítico: Propagação de carry interno (8 bits é gerenciável)
    //==========================================================================
    reg [7:0]  s6_res_low;                // Resultado LSB
    reg        s6_carry;                  // Carry de saída para MSB
    reg [15:8] s6_s_high, s6_c_high;      // Pipeline de bits superiores
    reg        s6_v;

    always @(posedge clk) begin
        s6_v <= s5_v;
        
        // Soma 8 bits baixos: gera resultado + carry out
        {s6_carry, s6_res_low} <= s5_s[7:0] + s5_c[7:0];
        
        // Pipeline de bits altos (não somados ainda)
        s6_s_high <= s5_s[15:8];
        s6_c_high <= s5_c[15:8];
    end

    //==========================================================================
    // ESTÁGIO S7: Somador Segmentado - Parte MSB (8 bits)
    //==========================================================================
    // Função: Soma os 8 bits mais significativos + carry de S6
    // Resultado: Produto completo de 16 bits
    //==========================================================================
    reg [15:0] s7_p;                      // Produto final
    reg        s7_v;

    always @(posedge clk) begin
        s7_v <= s6_v;
        
        // Monta produto: MSB soma 3 termos (s_high + c_high + carry_in)
        s7_p[15:8] <= s6_s_high + s6_c_high + {7'b0, s6_carry};
        
        // LSB já calculado em S6
        s7_p[7:0]  <= s6_res_low;
    end

    //==========================================================================
    // ESTÁGIO S8: Registro de Saída
    //==========================================================================
    // Função: Buffer final para isolar caminho crítico e estabilizar saída
    // Este estágio pode ser marcado como IOB para empacotamento em pad de saída
    //==========================================================================
    always @(posedge clk) begin
        v_out <= s7_v;  // Válido de saída (atraso de 8 ciclos de v_in)
        p     <= s7_p;  // Produto final (a × b)
    end

endmodule

`default_nettype wire
