// tb_booth_mult8.v
// Testbench Verilog-2001 para module booth_mult8 (corrigido)
// - 4 configurações de sign_mode (2 bits): [1]=multiplicand signed, [0]=multiplier signed
// - Casos de borda + 500 testes randômicos por configuração
// - Verificação automática do produto esperado
// - Timeout esperando done
`timescale 1ns/1ps

module tb_booth_mult8 #(
    parameter integer DUT_SEL = 0
);

    // --- clock / reset / control signals ---
    reg clk;
    reg rst_n;
    reg start;

    // --- DUT inputs (8-bit each) ---
    reg [7:0] multiplicand_i;
    reg [7:0] multiplier_i;
    reg [1:0] sign_mode; // [1] -> multiplicand signed when 1, [0] -> multiplier signed when 1

    // --- DUT outputs ---
    wire signed [15:0] product;
    wire done;
   // ============================================================
    // Geração condicional do DUT
    // ============================================================
    generate
        if (DUT_SEL == 0) begin : GEN_DUT_A
    		booth_mult8_core dut (
		        .clk(clk),
		        .rst_n(rst_n),
		        .start(start),
		        .multiplicand(multiplicand_i),
		        .multiplier(multiplier_i),
		        .sign_mode(sign_mode),
		        .product(product),
		        .done(done)
    		);
	end
        else if (DUT_SEL == 1) begin : GEN_DUT_B
           booth_mult8_isolated dut (
		        .clk(clk),
		        .rst_n(rst_n),
		        .start(start),
		        .multiplicand(multiplicand_i),
		        .multiplier(multiplier_i),
		        .sign_mode(sign_mode),
		        .product(product),
		        .done(done)
    		);
        end
        else begin : GEN_DUT_INVALID
            initial begin
                $error("Valor invalido para DUT_SEL = %0d", DUT_SEL);
                $finish;
            end
        end
    endgenerate
    // Instantiate DUT (assumes module name and ports as provided)
   
    // --- testbench helpers / bookkeeping ---
    integer i;
    integer seed;
    integer timeout_cycles;
    integer pass_count;
    integer fail_count;
    integer total_tests;

    // Expected product (computed in testbench using integer arithmetic)
    reg signed [15:0] expected;
    integer Ai;
    integer Bi;
    integer Prod;

    // Clock generator
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 ns period
    end

    // Test sequence
    initial begin
        // initialize
        seed = 32'hDEADBEEF;
        rst_n = 0;
        start = 0;
        multiplicand_i = 8'h00;
        multiplier_i   = 8'h00;
        sign_mode = 2'b00;
        pass_count = 0;
        fail_count = 0;
        total_tests = 0;
        timeout_cycles = 200; // timeout per test (cycles) - ajuste se necessário

        // apply reset pulse (keep reset for a short time)
        #20;
        rst_n = 1; // release reset (assumes active-low)

        // Run test campaigns for each sign_mode
        run_all_sign_configs();

        // Summary
        $display("------------------------------------------------------------");
        $display("TEST SUMMARY: total=%0d  PASS=%0d  FAIL=%0d", total_tests, pass_count, fail_count);
        if (fail_count == 0) begin
            $display("RESULT: ALL TESTS PASSED");
        end else begin
            $display("RESULT: SOME TESTS FAILED");
        end
        $display("------------------------------------------------------------");

        // finish
        #50;
        $finish;
    end

    // Task to run tests for all 4 sign configurations
    task run_all_sign_configs;
        integer cfg;
        begin
            for (cfg = 0; cfg < 4; cfg = cfg + 1) begin
                sign_mode = cfg[1:0];
                $display("\n=== Running tests for sign_mode = %0b (multiplicand_signed=%0b, multiplier_signed=%0b) ===",
                         sign_mode, sign_mode[1], sign_mode[0]);

                // Run explicit edge cases first
                run_edge_cases_for_config();

                // Then run 500 random tests
                run_random_tests_for_config(500);
            end
        end
    endtask

    integer aidx, bidx;
    reg [7:0] edge_vals [0:11];
    // Task: run predefined edge cases for current sign_mode
    task run_edge_cases_for_config;
        begin
            // List of explicit edge values to test for each operand
            edge_vals[0] = 8'h00; // 0
            edge_vals[1] = 8'h01; // 1
            edge_vals[2] = 8'h7F; // 127
            edge_vals[3] = 8'h80; // -128 (if signed) or 128 (unsigned)
            edge_vals[4] = 8'hFF; // -1 (if signed) or 255 (unsigned)
            edge_vals[5] = 8'hFE; // -2 or 254
            edge_vals[6] = 8'h55; // pattern
            edge_vals[7] = 8'hAA; // pattern
            edge_vals[8] = 8'h0F;
            edge_vals[9] = 8'hF0;
            edge_vals[10]= 8'hC0;
            edge_vals[11]= 8'h3F;

            for (aidx = 0; aidx < 12; aidx = aidx + 1) begin
                for (bidx = 0; bidx < 12; bidx = bidx + 1) begin
                    multiplicand_i = edge_vals[aidx];
                    multiplier_i   = edge_vals[bidx];
                    total_tests = total_tests + 1;
                    run_single_test_and_check();
                end
            end
        end
    endtask

    // Task: run N random tests for current sign_mode
    task run_random_tests_for_config;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) begin
                multiplicand_i = $random(seed) & 8'hFF;
                multiplier_i   = $random(seed) & 8'hFF;
                total_tests = total_tests + 1;
                run_single_test_and_check();
            end
        end
    endtask

    // Task: apply start pulse, wait for done (with timeout), compute expected, compare and record result
    task run_single_test_and_check;
        integer cycles_waited;
        begin
            // compute expected using integer arithmetic with sign_mode interpretation
            if (sign_mode[1] == 1'b1) begin
                Ai = $signed(multiplicand_i);
            end else begin
                Ai = multiplicand_i;
            end

            if (sign_mode[0] == 1'b1) begin
                Bi = $signed(multiplier_i);
            end else begin
                Bi = multiplier_i;
            end

            // compute product in integer (32-bit signed)
            Prod = Ai * Bi;

            // expected is lower 16 bits (signed interpretation)
            expected = Prod[15:0];

            // Apply start pulse (one clock)
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // wait for done with timeout
            cycles_waited = 0;
            while (done !== 1'b1 && cycles_waited < timeout_cycles) begin
                @(posedge clk);
                cycles_waited = cycles_waited + 1;
            end

            if (done !== 1'b1) begin
                $display("ERROR: timeout waiting for done. sign_mode=%0b A=0x%02h B=0x%02h expected=0x%04h",
                         sign_mode, multiplicand_i, multiplier_i, expected);
                fail_count = fail_count + 1;
            end else begin
                // Compare DUT product to expected bitwise
                if (product !== expected) begin
                    $display("FAIL: sign_mode=%0b multiplicand=0x%02h multiplier=0x%02h | DUT=0x%04h expected=0x%04h Ai=%0d Bi=%0d Prod=%0d",
                             sign_mode, multiplicand_i, multiplier_i, product, expected, Ai, Bi, Prod);
                    fail_count = fail_count + 1;
                end else begin
                    pass_count = pass_count + 1;
                end
            end

            // small gap between tests
            @(posedge clk);
        end
    endtask

    // Monitor progress periodically
    initial begin
	$dumpfile("simulation.vcd");
	$dumpvars(0,tb_booth_mult8);
        forever begin
            #50000; // every some simulated time show progress
            $display("[PROGRESS] tests so far=%0d pass=%0d fail=%0d", total_tests, pass_count, fail_count);
        end
    end

endmodule

