`timescale 1ns / 1ps

module tb_booth_split_adder;

    parameter WIDTH = 8;
    parameter CLK_PERIOD = 3.0; // 333 MHz

    reg clk, rst_n, valid_in;
    reg signed [WIDTH-1:0] mcand, mult;
    reg [1:0] sign_mode;
    wire signed [(2*WIDTH)-1:0] product;
    wire valid_out;

    reg signed [(2*WIDTH)-1:0] expected_fifo [0:63];
    reg [5:0] wr_ptr, rd_ptr;
    integer errors = 0;
    integer tests = 0;

    booth_mult8_split_adder #(.WIDTH(WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .multiplicand(mcand), .multiplier(mult), .sign_mode(sign_mode),
        .product(product), .valid_out(valid_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    function signed [(2*WIDTH)-1:0] calc_gold;
        input signed [WIDTH-1:0] a, b;
        input [1:0] mode;
        reg signed [31:0] a_32, b_32; 
    begin
        if (mode[1]) a_32 = a;        else a_32 = {24'b0, a}; 
        if (mode[0]) b_32 = b;        else b_32 = {24'b0, b};
        calc_gold = a_32 * b_32;
    end
    endfunction

    task send_transaction;
        input signed [WIDTH-1:0] a, b;
        input [1:0] mode;
    begin
        @(posedge clk);
        valid_in  <= 1;
        mcand     <= a;
        mult      <= b;
        sign_mode <= mode;
        expected_fifo[wr_ptr] <= calc_gold(a, b, mode);
        wr_ptr <= (wr_ptr + 1) & 6'h3F;
    end
    endtask

    initial begin
        clk = 0; rst_n = 0; valid_in = 0; wr_ptr = 0; rd_ptr = 0;
        #(CLK_PERIOD*12); rst_n = 1; #(CLK_PERIOD*12);

        $display("=== TESTE SPLIT ADDER (Ultra High Speed) ===");
        
        send_transaction(8'hFF, 8'hFF, 2'b00); 
        send_transaction(8'h80, 8'h80, 2'b11); 
        
        repeat(1000) begin
            send_transaction($random, $random, $random);
        end

        @(posedge clk); valid_in <= 0;
        repeat(20) @(posedge clk);

        if (errors == 0) $display("=== SUCESSO: %0d transacoes passaram ===", tests);
        else             $display("=== FALHA: %0d erros ===", errors);
        $finish;
    end

    always @(posedge clk) begin
        if (valid_out) begin
            if (product !== expected_fifo[rd_ptr]) begin
                $display("ERRO: Got %d, Exp %d", product, expected_fifo[rd_ptr]);
                errors = errors + 1;
            end
            rd_ptr <= (rd_ptr + 1) & 6'h3F;
            tests <= tests + 1;
        end
    end
    
    initial begin
        $dumpfile("booth_split.vcd");
        $dumpvars(0, tb_booth_split_adder);
    end

endmodule
