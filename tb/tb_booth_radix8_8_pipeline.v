`timescale 1ns / 1ps

module tb_booth_mult8_pipeline_opt;

    // ------------------------------------------------------------------------
    // Sinais e Constantes
    // ------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg signed [7:0] mcand_in;
    reg signed [7:0] mult_in;
    reg [1:0] sign_mode_in;
    
    wire signed [15:0] product_out;

    integer errors = 0;
    integer tests_run = 0;

    localparam MODE_UU = 2'b00;
    localparam MODE_US = 2'b01;
    localparam MODE_SU = 2'b10;
    localparam MODE_SS = 2'b11;

    // ATENÇÃO: Latência atualizada para 4 ciclos (Retiming para 223 MHz)
    localparam LATENCY = 4;

    // Arrays para pipeline de verificação
    reg signed [15:0] expected_pipe [0:LATENCY];
    reg [15:0]        debug_a_pipe  [0:LATENCY];
    reg [15:0]        debug_b_pipe  [0:LATENCY];
    reg [1:0]         debug_mode_pipe [0:LATENCY];
    reg               valid_pipe    [0:LATENCY];

    // ------------------------------------------------------------------------
    // GERAÇÃO DE VCD
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("booth_opt_223mhz.vcd");
        $dumpvars(0, tb_booth_mult8_pipeline_opt);
    end

    // ------------------------------------------------------------------------
    // Instanciação do DUT Otimizado
    // ------------------------------------------------------------------------
    booth_mult8_pipeline_opt dut (
        .clk(clk),
        .rst_n(rst_n),
        .multiplicand(mcand_in),
        .multiplier(mult_in),
        .sign_mode(sign_mode_in),
        .product(product_out)
    );

    // ------------------------------------------------------------------------
    // Clock (Simulando alta frequência, embora funcionalmente não mude a lógica)
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #2.23 clk = ~clk; // ~224 MHz period (apenas cosmético na simulação funcional)

    // ------------------------------------------------------------------------
    // Golden Model
    // ------------------------------------------------------------------------
    function signed [15:0] calc_expected;
        input [7:0] a, b;
        input [1:0] mode;
        reg signed [8:0] a_conv, b_conv;
        reg signed [17:0] res;
    begin
        if (mode[1]) a_conv = $signed(a); else a_conv = $signed({1'b0, a});
        if (mode[0]) b_conv = $signed(b); else b_conv = $signed({1'b0, b});
        res = a_conv * b_conv;
        calc_expected = res[15:0];
    end
    endfunction

    // ------------------------------------------------------------------------
    // Verificação e Shift Register
    // ------------------------------------------------------------------------
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (k=0; k<=LATENCY; k=k+1) valid_pipe[k] <= 0;
        end else begin
            // 1. Verificação (LATENCY-1 devido ao atraso do NBA <=)
            if (valid_pipe[LATENCY-1]) begin
                if (product_out !== expected_pipe[LATENCY-1]) begin
                    $display("ERRO Time %0t | Mode %b | A: %h B: %h", $time, 
                             debug_mode_pipe[LATENCY-1], debug_a_pipe[LATENCY-1], debug_b_pipe[LATENCY-1]);
                    $display("    Exp: %h (%d) | Obt: %h (%d)", 
                             expected_pipe[LATENCY-1], expected_pipe[LATENCY-1], 
                             product_out, product_out);
                    errors = errors + 1;
                end
                tests_run = tests_run + 1;
            end

            // 2. Shift Register
            for (k = LATENCY; k > 0; k = k - 1) begin
                expected_pipe[k]   <= expected_pipe[k-1];
                debug_a_pipe[k]    <= debug_a_pipe[k-1];
                debug_b_pipe[k]    <= debug_b_pipe[k-1];
                debug_mode_pipe[k] <= debug_mode_pipe[k-1];
                valid_pipe[k]      <= valid_pipe[k-1];
            end

            // 3. Load Input
            expected_pipe[0]   <= calc_expected(mcand_in, mult_in, sign_mode_in);
            debug_a_pipe[0]    <= {8'b0, mcand_in};
            debug_b_pipe[0]    <= {8'b0, mult_in};
            debug_mode_pipe[0] <= sign_mode_in;
            valid_pipe[0]      <= 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // Sequência de Teste
    // ------------------------------------------------------------------------
    reg [7:0] corners [0:7];
    initial begin
        corners[0]=8'h00; corners[1]=8'h01; corners[2]=8'h7F; corners[3]=8'h80;
        corners[4]=8'hFF; corners[5]=8'hAA; corners[6]=8'h55; corners[7]=8'h02;

        rst_n = 0; mcand_in = 0; mult_in = 0; sign_mode_in = 0;
        #20; @(posedge clk); rst_n = 1;

        $display("=== INICIANDO VERIFICACAO (LATENCY=4) ===");
        run_phase(MODE_UU, "UU");
        run_phase(MODE_US, "US");
        run_phase(MODE_SU, "SU");
        run_phase(MODE_SS, "SS");

        repeat(6) @(posedge clk); // Drain pipe (4+2 ciclos)
        
        if (errors == 0) 
            $display("\nSUCESSO TOTAL: %0d testes passaram. Arquitetura Solida!", tests_run);
        else 
            $display("\nFALHA: %0d erros encontrados.", errors);
            
        $finish;
    end

    task run_phase;
        input [1:0] mode;
        input [15:0] name;
        integer i, j;
    begin
        $display("Testando %s...", name);
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) drive(corners[i], corners[j], mode);
        for(i=0;i<100;i=i+1) drive($random, $random, mode);
    end
    endtask

    task drive;
        input [7:0] a, b;
        input [1:0] m;
    begin
        mcand_in <= a; mult_in <= b; sign_mode_in <= m;
        @(posedge clk);
    end
    endtask

endmodule
