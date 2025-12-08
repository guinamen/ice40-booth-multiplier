`timescale 1ns / 1ps

module tb_booth_radix8_multiplier;

    // ========================================================================
    // Parâmetros
    // ========================================================================
    parameter WIDTH = 16;
    parameter CLK_PERIOD = 10;
    parameter NUM_RANDOM_TESTS = 10000;

    // ========================================================================
    // Sinais do DUT
    // ========================================================================
    reg                      clk;
    reg                      rst_n;
    reg                      start;
    reg  signed [WIDTH-1:0]  multiplicand;
    reg  signed [WIDTH-1:0]  multiplier;
    reg  [1:0]               sign_mode;
    wire signed [2*WIDTH-1:0] product;
    wire                     done;
    wire                     busy;

    // ========================================================================
    // Variáveis de Teste
    // ========================================================================
    integer test_count;
    integer error_count;
    integer pass_count;
    reg signed [2*WIDTH-1:0] expected;
    reg [63:0] a_unsigned, b_unsigned;

    // ========================================================================
    // Instanciação do DUT
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
    // Geração de Clock
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // Task: Reset do Sistema
    // ========================================================================
    task reset_system;
        begin
            rst_n = 0;
            start = 0;
            multiplicand = 0;
            multiplier = 0;
            sign_mode = 2'b00;
            repeat(3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // ========================================================================
    // Task: Executar Multiplicação
    // ========================================================================
    task run_multiplication;
        input signed [WIDTH-1:0] a;
        input signed [WIDTH-1:0] b;
        input [1:0] mode;
        output signed [2*WIDTH-1:0] result;
        begin
            @(posedge clk);
            multiplicand = a;
            multiplier = b;
            sign_mode = mode;
            start = 1;
            @(posedge clk);
            start = 0;

            // Aguarda conclusão
            wait(done);
            @(posedge clk);
            result = product;
        end
    endtask

    // ========================================================================
    // Function: Calcular Resultado Esperado
    // ========================================================================
    function signed [2*WIDTH-1:0] calc_expected;
        input signed [WIDTH-1:0] a;
        input signed [WIDTH-1:0] b;
        input [1:0] mode;
        reg signed [2*WIDTH-1:0] a_ext, b_ext;
        begin
            // Extensão baseada no modo
            case (mode)
                2'b00: begin // unsigned × unsigned
                    a_ext = {{WIDTH{1'b0}}, a};
                    b_ext = {{WIDTH{1'b0}}, b};
                end
                2'b01: begin // unsigned × signed
                    a_ext = {{WIDTH{1'b0}}, a};
                    b_ext = {{WIDTH{b[WIDTH-1]}}, b};
                end
                2'b10: begin // signed × unsigned
                    a_ext = {{WIDTH{a[WIDTH-1]}}, a};
                    b_ext = {{WIDTH{1'b0}}, b};
                end
                2'b11: begin // signed × signed
                    a_ext = {{WIDTH{a[WIDTH-1]}}, a};
                    b_ext = {{WIDTH{b[WIDTH-1]}}, b};
                end
            endcase
            calc_expected = a_ext * b_ext;
        end
    endfunction

    // ========================================================================
    // Task: Verificar Resultado
    // ========================================================================
    task check_result;
        input signed [WIDTH-1:0] a;
        input signed [WIDTH-1:0] b;
        input [1:0] mode;
        input signed [2*WIDTH-1:0] result;
        reg signed [2*WIDTH-1:0] exp;
        begin
            exp = calc_expected(a, b, mode);

            if (result !== exp) begin
                $display("ERROR [Test #%0d] Mode=%b", test_count, mode);
                $display("  A = %0d (0x%h)", a, a);
                $display("  B = %0d (0x%h)", b, b);
                $display("  Expected = %0d (0x%h)", exp, exp);
                $display("  Got      = %0d (0x%h)", result, result);
                $display("  Diff     = %0d", result - exp);
                error_count = error_count + 1;
            end else begin
                pass_count = pass_count + 1;
                if ((test_count % 1000) == 0)
                    $display("Test #%0d PASSED: %0d × %0d = %0d [mode=%b]",
                             test_count, a, b, result, mode);
            end
            test_count = test_count + 1;
        end
    endtask

    // ========================================================================
    // Processo Principal de Teste
    // ========================================================================
    initial begin
        $display("========================================");
        $display("  Booth Radix-8 Multiplier Testbench");
        $display("  WIDTH = %0d", WIDTH);
        $display("========================================");

        test_count = 0;
        error_count = 0;
        pass_count = 0;

        reset_system();

        // ====================================================================
        // TESTES DE CASOS PADRÃO
        // ====================================================================
        $display("\n[1] TESTES DE CASOS PADRÃO");
        $display("----------------------------");

        // Teste 1: Zeros
        run_multiplication(0, 0, 2'b11, expected);
        check_result(0, 0, 2'b11, expected);

        // Teste 2: Multiplicação por 1
        run_multiplication(1, 42, 2'b11, expected);
        check_result(1, 42, 2'b11, expected);

        // Teste 3: Multiplicação por -1
        run_multiplication(-1, 42, 2'b11, expected);
        check_result(-1, 42, 2'b11, expected);

        // Teste 4: Números positivos pequenos
        run_multiplication(15, 15, 2'b11, expected);
        check_result(15, 15, 2'b11, expected);

        // Teste 5: Números negativos
        run_multiplication(-15, 15, 2'b11, expected);
        check_result(-15, 15, 2'b11, expected);

        // Teste 6: Ambos negativos
        run_multiplication(-15, -15, 2'b11, expected);
        check_result(-15, -15, 2'b11, expected);

        // Teste 7: Valores máximos signed
        run_multiplication(16'h7FFF, 16'h7FFF, 2'b11, expected);
        check_result(16'h7FFF, 16'h7FFF, 2'b11, expected);

        // Teste 8: Valores mínimos signed
        run_multiplication(-16'h8000, 2, 2'b11, expected);
        check_result(-16'h8000, 2, 2'b11, expected);

        // Teste 9: Potências de 2
        run_multiplication(256, 128, 2'b11, expected);
        check_result(256, 128, 2'b11, expected);

        // Teste 10: Unsigned máximo
        run_multiplication(16'hFFFF, 16'hFFFF, 2'b00, expected);
        check_result(16'hFFFF, 16'hFFFF, 2'b00, expected);

        // ====================================================================
        // TESTES ALEATÓRIOS - SIGNED × SIGNED (mode = 2'b11)
        // ====================================================================
        $display("\n[2] TESTES ALEATÓRIOS: SIGNED × SIGNED");
        $display("---------------------------------------");
        repeat(NUM_RANDOM_TESTS) begin
            multiplicand = $random;
            multiplier = $random;
            run_multiplication(multiplicand, multiplier, 2'b11, expected);
            check_result(multiplicand, multiplier, 2'b11, expected);
        end

        // ====================================================================
        // TESTES ALEATÓRIOS - UNSIGNED × UNSIGNED (mode = 2'b00)
        // ====================================================================
        $display("\n[3] TESTES ALEATÓRIOS: UNSIGNED × UNSIGNED");
        $display("-------------------------------------------");
        repeat(NUM_RANDOM_TESTS) begin
            multiplicand = $random;
            multiplier = $random;
            run_multiplication(multiplicand, multiplier, 2'b00, expected);
            check_result(multiplicand, multiplier, 2'b00, expected);
        end

        // ====================================================================
        // TESTES ALEATÓRIOS - SIGNED × UNSIGNED (mode = 2'b10)
        // ====================================================================
        $display("\n[4] TESTES ALEATÓRIOS: SIGNED × UNSIGNED");
        $display("-----------------------------------------");
        repeat(NUM_RANDOM_TESTS) begin
            multiplicand = $random;
            multiplier = $random;
            run_multiplication(multiplicand, multiplier, 2'b10, expected);
            check_result(multiplicand, multiplier, 2'b10, expected);
        end

        // ====================================================================
        // TESTES ALEATÓRIOS - UNSIGNED × SIGNED (mode = 2'b01)
        // ====================================================================
        $display("\n[5] TESTES ALEATÓRIOS: UNSIGNED × SIGNED");
        $display("-----------------------------------------");
        repeat(NUM_RANDOM_TESTS) begin
            multiplicand = $random;
            multiplier = $random;
            run_multiplication(multiplicand, multiplier, 2'b01, expected);
            check_result(multiplicand, multiplier, 2'b01, expected);
        end

        // ====================================================================
        // TESTES DE BORDA (Edge Cases)
        // ====================================================================
        $display("\n[6] TESTES DE CASOS DE BORDA");
        $display("-----------------------------");

        // Teste com todos os bits 1 (unsigned)
        run_multiplication(16'hFFFF, 1, 2'b00, expected);
        check_result(16'hFFFF, 1, 2'b00, expected);

        // Teste com MSB set (interpretação diferente signed/unsigned)
        run_multiplication(16'h8000, 2, 2'b11, expected);
        check_result(16'h8000, 2, 2'b11, expected);

        run_multiplication(16'h8000, 2, 2'b00, expected);
        check_result(16'h8000, 2, 2'b00, expected);

        // Teste mixed sign com valores grandes
        run_multiplication(16'h7FFF, 16'hFFFF, 2'b10, expected);
        check_result(16'h7FFF, 16'hFFFF, 2'b10, expected);

        run_multiplication(16'hFFFF, 16'h7FFF, 2'b01, expected);
        check_result(16'hFFFF, 16'h7FFF, 2'b01, expected);

        // ====================================================================
        // RESUMO DOS TESTES
        // ====================================================================
        $display("\n========================================");
        $display("  RESUMO DOS TESTES");
        $display("========================================");
        $display("  Total de Testes: %0d", test_count);
        $display("  Testes Passou:   %0d", pass_count);
        $display("  Testes Falhou:   %0d", error_count);

        if (error_count == 0) begin
            $display("\n  ✓ TODOS OS TESTES PASSARAM!");
        end else begin
            $display("\n  ✗ ALGUNS TESTES FALHARAM!");
        end
        $display("========================================\n");

        #100;
        $finish;
    end

    // ========================================================================
    // Timeout de Segurança
    // ========================================================================
    initial begin
        #(CLK_PERIOD * 100000 * NUM_RANDOM_TESTS);
        $display("\nERROR: Timeout do testbench!");
        $finish;
    end

    // ========================================================================
    // Monitoramento opcional (comentado por padrão)
    // ========================================================================
    // initial begin
    //     $monitor("Time=%0t rst_n=%b start=%b busy=%b done=%b prod=%h",
    //              $time, rst_n, start, busy, done, product);
    // end

endmodule
