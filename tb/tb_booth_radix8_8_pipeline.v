`timescale 1ns / 1ps

module tb_booth_handshake;

    // ------------------------------------------------------------------------
    // Sinais
    // ------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg start;                  // ADICIONADO: Sinal Start
    reg signed [7:0] mcand_in;
    reg signed [7:0] mult_in;
    reg [1:0] sign_mode_in;

    wire signed [15:0] product_out;
    wire done;                  // ADICIONADO: Sinal Done

    integer errors = 0;
    integer tests_run = 0;

    localparam MODE_UU = 2'b00;
    localparam MODE_US = 2'b01;
    localparam MODE_SU = 2'b10;
    localparam MODE_SS = 2'b11;

    // ------------------------------------------------------------------------
    // DUT (Device Under Test)
    // ------------------------------------------------------------------------
    booth_mult8_core_pipelined dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),          // CONECTADO
        .multiplicand(mcand_in),
        .multiplier(mult_in),
        .sign_mode(sign_mode_in),
        .product(product_out),
        .done(done)             // CONECTADO
    );

    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #2.23 clk = ~clk; 

    // ------------------------------------------------------------------------
    // Golden Model (Cálculo Esperado)
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
    // Sequência de Teste Principal
    // ------------------------------------------------------------------------
    reg [7:0] corners [0:7];
    initial begin
        $dumpfile("booth_handshake.vcd");
        $dumpvars(0, tb_booth_handshake);

        // Casos de canto (Corner cases)
        corners[0]=8'h00; corners[1]=8'h01; corners[2]=8'h7F; corners[3]=8'h80;
        corners[4]=8'hFF; corners[5]=8'hAA; corners[6]=8'h55; corners[7]=8'h02;

        // Inicialização
        rst_n = 0; start = 0; mcand_in = 0; mult_in = 0; sign_mode_in = 0;
        #20; 
        @(posedge clk); 
        rst_n = 1;
        #20;

        $display("=== INICIANDO VERIFICACAO (HANDSHAKE) ===");
        run_phase(MODE_UU, "UU (Unsigned x Unsigned)");
        run_phase(MODE_US, "US (Unsigned x Signed)");
        run_phase(MODE_SU, "SU (Signed x Unsigned)");
        run_phase(MODE_SS, "SS (Signed x Signed)");

        if (errors == 0)
            $display("\nSUCESSO TOTAL: %0d testes passaram.", tests_run);
        else
            $display("\nFALHA: %0d erros encontrados.", errors);

        $finish;
    end

    // Tarefa para rodar um grupo de testes
    task run_phase;
        input [1:0] mode;
        input [25*8:1] name; // String name
        integer i, j;
    begin
        $display("Testando %s...", name);
        // Teste exaustivo dos corners
        for(i=0;i<8;i=i+1) 
            for(j=0;j<8;j=j+1) 
                check_transaction(corners[i], corners[j], mode);
        
        // Testes aleatórios
        for(i=0;i<50;i=i+1) 
            check_transaction($random, $random, mode);
    end
    endtask

    // ------------------------------------------------------------------------
    // Transação Individual (O SEGREDO ESTÁ AQUI)
    // ------------------------------------------------------------------------
    task check_transaction;
        input [7:0] a, b;
        input [1:0] mode;
        reg signed [15:0] expected;
    begin
        // 1. Configura as entradas
        @(posedge clk);
        mcand_in <= a; 
        mult_in <= b; 
        sign_mode_in <= mode;
        
        // 2. Pulsa o START
        start <= 1;
        @(posedge clk);
        start <= 0;

        // 3. Espera pelo DONE (Handshake)
        // O hardware leva vários ciclos. Esperamos até 'done' subir.
        @(posedge done); 
        
        // 4. Verifica o resultado (na borda seguinte para estabilizar)
        expected = calc_expected(a, b, mode);
        
        // Pequeno delay delta para garantir leitura correta
        #1; 
        if (product_out !== expected) begin
            $display("ERRO | Mode %b | A: %h (%d) B: %h (%d)", mode, a, $signed(a), b, $signed(b));
            $display("       Exp: %h (%d) | Obt: %h (%d)", expected, expected, product_out, product_out);
            errors = errors + 1;
        end
        tests_run = tests_run + 1;
        
        // Espera um ciclo antes da próxima transação (opcional)
        @(posedge clk);
    end
    endtask

endmodule
