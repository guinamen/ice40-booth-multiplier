`timescale 1ns / 1ps

// Defina a largura aqui para testar
`define TEST_WIDTH 32

module tb_booth_generic;

    reg clk;
    reg rst_n;
    reg signed [`TEST_WIDTH-1:0] mcand_in;
    reg signed [`TEST_WIDTH-1:0] mult_in;
    reg [1:0] sign_mode_in;
    
    wire signed [(2*`TEST_WIDTH)-1:0] product_out;

    integer errors = 0;
    integer tests_run = 0;
    
    localparam LATENCY = 7;
    
    // Arrays largos o suficiente para armazenar resultados de 32 bits (64 out)
    reg signed [(2*`TEST_WIDTH)-1:0] expected_pipe [0:LATENCY];
    reg [`TEST_WIDTH-1:0]            debug_a_pipe  [0:LATENCY];
    reg [`TEST_WIDTH-1:0]            debug_b_pipe  [0:LATENCY];
    reg [1:0]                        debug_mode_pipe [0:LATENCY];
    reg                              valid_pipe    [0:LATENCY];

    // DUT Genérico
    booth_mult_generic #(.WIDTH(`TEST_WIDTH)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .multiplicand(mcand_in),
        .multiplier(mult_in),
        .sign_mode(sign_mode_in),
        .product(product_out)
    );

    initial clk = 0; 
    always #5 clk = ~clk;

    // Golden Model Genérico
    function signed [(2*`TEST_WIDTH)-1:0] calc_expected;
        input [`TEST_WIDTH-1:0] a, b;
        input [1:0] mode;
        reg signed [`TEST_WIDTH:0] a_conv, b_conv; // +1 bit para sign handling seguro
        reg signed [(2*`TEST_WIDTH)+1:0] res;
    begin
        if (mode[1]) a_conv = $signed(a); else a_conv = $signed({1'b0, a});
        if (mode[0]) b_conv = $signed(b); else b_conv = $signed({1'b0, b});
        res = a_conv * b_conv;
        calc_expected = res[(2*`TEST_WIDTH)-1:0];
    end
    endfunction

    // Lógica de verificação (Idêntica, só mudam as larguras)
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            for(k=0; k<=LATENCY; k=k+1) valid_pipe[k] <= 0;
        end else begin
            if (valid_pipe[LATENCY-1]) begin
                if (product_out !== expected_pipe[LATENCY-1]) begin
                    $display("ERRO em %0d bits: A=%h B=%h | Exp=%h Rec=%h", 
                             `TEST_WIDTH, debug_a_pipe[LATENCY-1], debug_b_pipe[LATENCY-1],
                             expected_pipe[LATENCY-1], product_out);
                    errors = errors + 1;
                end
                tests_run = tests_run + 1;
            end
            for (k = LATENCY; k > 0; k = k - 1) begin
                expected_pipe[k]   <= expected_pipe[k-1];
                debug_a_pipe[k]    <= debug_a_pipe[k-1];
                debug_b_pipe[k]    <= debug_b_pipe[k-1];
                debug_mode_pipe[k] <= debug_mode_pipe[k-1];
                valid_pipe[k]      <= valid_pipe[k-1];
            end
            expected_pipe[0]   <= calc_expected(mcand_in, mult_in, sign_mode_in);
            debug_a_pipe[0]    <= mcand_in;
            debug_b_pipe[0]    <= mult_in;
            debug_mode_pipe[0] <= sign_mode_in;
            valid_pipe[0]      <= 1'b1;
        end
    end

    initial begin
        $dumpfile("simulacao.vcd");   // nome do arquivo
	$dumpvars(0, tb_booth_generic);   
        rst_n = 0;
        #20; @(posedge clk); rst_n = 1;
        $display("Iniciando Teste Genérico com WIDTH=%0d", `TEST_WIDTH);
        
        // Testes Aleatórios
        repeat(1000) begin
            mcand_in <= $random;
            mult_in <= $random;
            sign_mode_in <= $random;
            @(posedge clk);
        end
        
        repeat(10) @(posedge clk);
        if (errors == 0) $display("SUCESSO: %0d testes passaram.", tests_run);
        else $display("FALHAS: %0d erros.", errors);
        $finish;
    end
endmodule
