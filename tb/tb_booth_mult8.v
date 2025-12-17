`timescale 1ns/1ps

// ============================================================================
// TESTBENCH RIGOROSO E EXAUSTIVO
// Valida 100% das combinações possíveis de entrada (8-bit)
// ============================================================================
module tb_booth_rigorous;

    // --- Sinais do DUT ---
    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] mcand_in;
    reg [7:0] mult_in;
    reg [1:0] sign_mode;

    wire signed [15:0] product;
    wire done;

    // --- Controle de Teste ---
    reg signed [15:0] expected;
    integer errors = 0;
    integer tests_run = 0;
    integer start_time;
    
    // Configurações
    // 2 = Pipelined (Alvo principal)
    // 0 = Core Simples
    parameter DUT_TYPE = 2; 

    // --- Instanciação do DUT ---
    generate
        if (DUT_TYPE == 2) begin
            booth_mult8_core_pipelined dut (
                .clk(clk), .rst_n(rst_n), .start(start),
                .multiplicand(mcand_in), .multiplier(mult_in),
                .sign_mode(sign_mode), .product(product), .done(done)
            );
        end 
	else if (DUT_TYPE == 1) begin
    	   booth_mult8_isolated  dut (
                .clk(clk), .rst_n(rst_n), .start(start),
                .multiplicand(mcand_in), .multiplier(mult_in),
                .sign_mode(sign_mode), .product(product), .done(done)
            );
 
	end
	else begin
            // Caso queira testar o V3
            booth_mult8_core dut (
                .clk(clk), .rst_n(rst_n), .start(start),
                .multiplicand(mcand_in), .multiplier(mult_in),
                .sign_mode(sign_mode), .product(product), .done(done)
            );
        end
    endgenerate

    // --- Clock (Alta Frequência simulada) ---
    initial clk = 0;
    always #2.23 clk = ~clk; // ~224 MHz

    // --- Modelo Dourado (Referência) ---
    function signed [15:0] calc_golden;
        input [7:0] a, b;
        input [1:0] mode;
        reg signed [15:0] a_s, b_s; // Expande para garantir sinal correto
    begin
        // Interpretação correta dos operandos antes da multiplicação
        // Se mode[1] (A Signed), interpreta como signed, senão, 0-extended
        if (mode[1]) a_s = $signed(a); else a_s = $signed({1'b0, a});
        
        // Se mode[0] (B Signed), interpreta como signed, senão, 0-extended
        if (mode[0]) b_s = $signed(b); else b_s = $signed({1'b0, b});
        
        calc_golden = a_s * b_s;
    end
    endfunction

    // --- Fluxo Principal ---
    initial begin
        $dumpfile("rigorous_wave.vcd");
        $dumpvars(0, tb_booth_rigorous);
        
        // Inicialização
        rst_n = 0; start = 0; mcand_in = 0; mult_in = 0; sign_mode = 0;
        #50;
        rst_n = 1;
        #20;

        $display("\n============================================================");
        $display(" INICIANDO TESTE DE ESTRESSE EXAUSTIVO (100%% COBERTURA)");
        $display(" Total esperado: 262.144 transacoes");
        $display("============================================================\n");

        start_time = $time;

        // 1. MODO UNSIGNED x UNSIGNED (00)
        run_exhaustive_sweep(2'b00, "Unsigned x Unsigned");

        // 2. MODO UNSIGNED x SIGNED (01)
        run_exhaustive_sweep(2'b01, "Unsigned x Signed");

        // 3. MODO SIGNED x UNSIGNED (10)
        run_exhaustive_sweep(2'b10, "Signed x Unsigned");

        // 4. MODO SIGNED x SIGNED (11)
        run_exhaustive_sweep(2'b11, "Signed x Signed");

        // 5. TESTE ALEATÓRIO MASSIVO (Extra Check)
        $display("\n--- Executando 50.000 Testes Aleatorios (Random Stress) ---");
        run_random_stress(50000);

        // Relatório Final
        $display("\n============================================================");
        $display(" FIM DA SIMULACAO");
        $display(" Tempo Total de Simulacao: %0t", $time);
        $display(" Total de Testes: %0d", tests_run);
        $display(" Erros Encontrados: %0d", errors);
        $display("============================================================");

        if (errors == 0) 
            $display("\n>>> STATUS: APROVADO COM LOUVOR (HARDWARE PERFEITO) <<<\n");
        else 
            $display("\n>>> STATUS: FALHA CRITICA DETECTADA <<<\n");

        $finish;
    end

    // --- Tarefa: Varredura Exaustiva (0..255 x 0..255) ---
    task run_exhaustive_sweep;
        input [1:0] mode;
        input [8*20:1] name;
        integer i, j;
    begin
        $display(">>> Testando Todos os Casos: %s (Mode %b)", name, mode);
        sign_mode = mode;
        
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 256; j = j + 1) begin
                
                // Configura e pulsa
                @(posedge clk);
                mcand_in <= i[7:0];
                mult_in  <= j[7:0];
                start    <= 1;
                @(posedge clk);
                start    <= 0;

                // Espera Handshake
                @(posedge done);
                
                // Verifica
                expected = calc_golden(i[7:0], j[7:0], mode);
                
                // Delay delta para estabilização
                #1; 
                if (product !== expected) begin
                    $display("ERRO CRITICO! Mode: %b | A: 0x%h (%0d) | B: 0x%h (%0d)", mode, i[7:0], $signed(i[7:0]), j[7:0], $signed(j[7:0]));
                    $display("    Esperado: 0x%h (%0d)", expected, expected);
                    $display("    Obtido:   0x%h (%0d)", product, product);
                    errors = errors + 1;
                    
                    // Se encontrar erro, para imediatamente para não inundar o log
                    $display("Execucao abortada devido a erro.");
                    $finish; 
                end
                
                tests_run = tests_run + 1;
            end
            
            // Barra de progresso simples a cada linha de matriz
            if (i % 64 == 0) $write(".");
        end
        $display(" [OK]");
    end
    endtask

    // --- Tarefa: Random Stress ---
    task run_random_stress;
        input integer count;
        integer k;
        reg [7:0] ra, rb;
        reg [1:0] rm;
    begin
        for (k = 0; k < count; k = k + 1) begin
            @(posedge clk);
            ra = $random;
            rb = $random;
            rm = $random; // Random mode too
            
            mcand_in <= ra;
            mult_in  <= rb;
            sign_mode <= rm;
            start <= 1;
            @(posedge clk);
            start <= 0;

            @(posedge done);
            
            expected = calc_golden(ra, rb, rm);
            #1;
            if (product !== expected) begin
                $display("ERRO RANDOM! Mode: %b A:%h B:%h | Exp:%h Obt:%h", rm, ra, rb, expected, product);
                errors = errors + 1;
                $finish;
            end
            tests_run = tests_run + 1;
        end
        $display("Random Stress Completo.");
    end
    endtask

endmodule
