`timescale 1ns / 1ps

module tb_booth_radix8_multiplier;

    // ========================================================================
    // Sinais e Parâmetros
    // ========================================================================
    parameter WIDTH = 16;

    reg                  clk;
    reg                  rst_n;
    reg                  start;
    reg  [WIDTH-1:0]     multiplicand; // Tratado genericamente como reg, sinal interpretado pelo modo
    reg  [WIDTH-1:0]     multiplier;
    reg  [1:0]           sign_mode;    // [1]: Multiplicando, [0]: Multiplicador

    wire [2*WIDTH-1:0]   product;
    wire                 done;
    wire                 busy;

    // Contadores para estatísticas
    integer pass_count = 0;
    integer fail_count = 0;

    // ========================================================================
    // Instância do DUT (Device Under Test)
    // ========================================================================
    booth_radix8_multiplier #(
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .multiplicand(multiplicand),
        .multiplier(multiplier),
        .sign_mode(sign_mode),
        .product(product),
        .done(done),
        .busy(busy)
    );

    // ========================================================================
    // Geração de Clock (10ns período = 100MHz)
    // ========================================================================
    always #5 clk = ~clk;

    // ========================================================================
    // Procedimento de Teste Principal
    // ========================================================================
    initial begin
        // Configuração de arquivo de onda (para GTKWave/Simuladores)
        $dumpfile("booth_mult.vcd");
        $dumpvars(0, tb_booth_radix8_multiplier);

        // Inicialização
        clk = 0;
        rst_n = 0;
        start = 0;
        multiplicand = 0;
        multiplier = 0;
        sign_mode = 0;

        // Reset
        #20 rst_n = 1;
        #20;

        $display("=== Iniciando Testes do Multiplicador Booth Radix-8 (16-bit) ===");

        // --------------------------------------------------------------------
        // 1. Testes Básicos (Sanity Check)
        // --------------------------------------------------------------------
        $display("\n--- Testes Básicos ---");
        run_test(16'd10, 16'd5, 2'b00);   // 10 * 5 (Unsigned)
        run_test(16'd10, 16'd5, 2'b11);   // 10 * 5 (Signed)
        run_test(-16'd10, 16'd5, 2'b11);  // -10 * 5 (Signed)

        // --------------------------------------------------------------------
        // 2. Testes de Corner Cases (Casos de Borda)
        // --------------------------------------------------------------------
        $display("\n--- Testes de Corner Cases ---");

        // Zeros
        run_test(16'd0, 16'd1234, 2'b00);
        run_test(16'd5678, 16'd0, 2'b11);

        // Máximo Positivo (Signed) -> 32767 (0x7FFF)
        run_test(16'h7FFF, 16'h7FFF, 2'b11); // Max * Max
        run_test(16'h7FFF, 16'd1, 2'b11);

        // Máximo Negativo (Signed) -> -32768 (0x8000)
        // Este é um teste crítico para Booth, pois -Max não tem complemento de 2 positivo simétrico
        run_test(16'h8000, 16'd1, 2'b11);    // -32768 * 1
        run_test(16'h8000, 16'h7FFF, 2'b11); // -32768 * 32767
        run_test(16'h8000, 16'h8000, 2'b11); // -32768 * -32768 (Deve dar positivo grande)

        // Máximo Unsigned -> 65535 (0xFFFF)
        run_test(16'hFFFF, 16'hFFFF, 2'b00);
        run_test(16'hFFFF, 16'd0, 2'b00);

        // --------------------------------------------------------------------
        // 3. Testes de Modos Mistos
        // --------------------------------------------------------------------
        $display("\n--- Testes de Modos Mistos ---");
        // Mode 10: Multiplicando Signed, Multiplicador Unsigned
        // -10 (0xFFF6) * 10 (0x000A) = -100
        run_test(16'hFFF6, 16'h000A, 2'b10);

        // Mode 01: Multiplicando Unsigned, Multiplicador Signed
        // 10 (0x000A) * -10 (0xFFF6) = -100
        run_test(16'h000A, 16'hFFF6, 2'b01);

        // --------------------------------------------------------------------
        // 4. Testes Aleatórios
        // --------------------------------------------------------------------
        $display("\n--- Testes Aleatórios (200 iterações) ---");
        repeat (50) begin
            // Random Unsigned
            run_test($random, $random, 2'b00);
            // Random Signed
            run_test($random, $random, 2'b11);
            // Random Mixed
            run_test($random, $random, 2'b10);
            run_test($random, $random, 2'b01);
        end

        // ====================================================================
        // Resultado Final
        // ====================================================================
        $display("\n=======================================================");
        $display("RESULTADO FINAL:");
        $display("Passaram: %0d", pass_count);
        $display("Falharam: %0d", fail_count);
        $display("=======================================================");

        if (fail_count == 0)
            $display("SUCESSO: O design passou em todos os testes!");
        else
            $display("FALHA: Erros encontrados. Verifique o log.");

        $finish;
    end

    // ========================================================================
    // Task: Executa um teste individual
    // ========================================================================
    task run_test;
        input [WIDTH-1:0] in_a;
        input [WIDTH-1:0] in_b;
        input [1:0]       mode;

        reg signed [2*WIDTH-1:0] expected_product;

        // Variáveis temporárias estendidas para cálculo de referência correto
        reg signed [2*WIDTH-1:0] a_ext;
        reg signed [2*WIDTH-1:0] b_ext;

        begin
            // 1. Calcular o Resultado Esperado (Golden Model)
            // Estender os sinais baseado no modo antes de multiplicar

            // Tratamento do A (Multiplicando) - Mode[1]
            if (mode[1]) a_ext = $signed(in_a);      // Sign extend
            else         a_ext = $signed({16'b0, in_a}); // Zero extend

            // Tratamento do B (Multiplicador) - Mode[0]
            if (mode[0]) b_ext = $signed(in_b);      // Sign extend
            else         b_ext = $signed({16'b0, in_b}); // Zero extend

            expected_product = a_ext * b_ext;

            // 2. Aplicar estímulos ao DUT
            @(posedge clk);
            wait(!busy); // Garantir que não está ocupado (embora start force reinicio)

            multiplicand <= in_a;
            multiplier   <= in_b;
            sign_mode    <= mode;
            start        <= 1'b1;

            @(posedge clk);
            start        <= 1'b0;

            // 3. Esperar conclusão
            // O DUT leva alguns ciclos. Usamos wait(done)
            wait(done);
            @(negedge clk); // Verificar na borda de descida para estabilidade

            // 4. Verificar Resultado
            if (product !== expected_product) begin
                $display("ERRO no tempo %0t:", $time);
                $display("  Mode: %b | A: %h (%0d) | B: %h (%0d)",
                         mode, in_a, $signed(in_a), in_b, $signed(in_b));
                $display("  Esperado: %h (%0d)", expected_product, expected_product);
                $display("  Obtido:   %h (%0d)", product, product);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            // Pequeno atraso entre testes
            repeat(2) @(posedge clk);
        end
    endtask

endmodule
