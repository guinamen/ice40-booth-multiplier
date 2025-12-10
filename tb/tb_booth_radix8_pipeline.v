`timescale 1ns / 1ps

module tb_booth_pipeline;

    // Sinais
    reg clk;
    reg rst_n;
    reg start;
    reg signed [15:0] multiplicand;
    reg signed [15:0] multiplier;
    reg [1:0] sign_mode;
    
    wire signed [31:0] product;
    wire done;
    wire busy;

    // Instanciação do DUT (Device Under Test)
    booth_radix8_multiplier #( .WIDTH(16) ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .multiplicand(multiplicand), .multiplier(multiplier), .sign_mode(sign_mode),
        .product(product), .done(done), .busy(busy)
    );

    // ========================================================================
    // GERAÇÃO DE VCD (ADICIONADO AQUI)
    // ========================================================================
    initial begin
        $dumpfile("booth_pipeline.vcd"); // Nome do arquivo de saída
        $dumpvars(0, tb_booth_pipeline); // 0 = Salva todos os sinais recursivamente
    end

    // Estruturas de Teste
    parameter FIFO_DEPTH = 5000; 
    reg signed [31:0] fifo_expected [0:FIFO_DEPTH-1];
    integer           fifo_id       [0:FIFO_DEPTH-1];
    integer write_ptr, read_ptr, error_count, tx_count;

    always #3.333 clk = ~clk; 

    // Task de Estímulo
    task drive_transaction;
        input signed [15:0] in_a;
        input signed [15:0] in_b;
        input [1:0]         in_mode;
        
        reg signed [31:0] op_a_32;
        reg signed [31:0] op_b_32;
        begin
            // Espera Busy
            while (busy) @(negedge clk);

            // Calcula Expected
            if (in_mode[1]) op_a_32 = {{16{in_a[15]}}, in_a};
            else            op_a_32 = {16'b0, in_a};
            
            if (in_mode[0]) op_b_32 = {{16{in_b[15]}}, in_b};
            else            op_b_32 = {16'b0, in_b};
            
            fifo_expected[write_ptr] = op_a_32 * op_b_32;
            fifo_id[write_ptr]       = tx_count;
            write_ptr = (write_ptr + 1) % FIFO_DEPTH;
            tx_count = tx_count + 1;

            // Envia ao DUT
            start        <= 1'b1;
            multiplicand <= in_a;
            multiplier   <= in_b;
            sign_mode    <= in_mode;
            @(negedge clk);
            start <= 1'b0;
        end
    endtask

    // Monitor
    always @(posedge clk) begin
        if (done) begin
            if (read_ptr == write_ptr) begin
                $display("ERRO: Done inesperado (FIFO vazia)");
                error_count = error_count + 1;
            end else begin
                if (product !== fifo_expected[read_ptr]) begin
                    $display("ERRO [ID %0d]: Esperado %d, Recebido %d", 
                        fifo_id[read_ptr], fifo_expected[read_ptr], product);
                    error_count = error_count + 1;
                end
                read_ptr = (read_ptr + 1) % FIFO_DEPTH;
            end
        end
    end

    integer i;
    reg signed [15:0] ra, rb;

    initial begin
        clk = 0; rst_n = 0; start = 0;
        write_ptr = 0; read_ptr = 0; error_count = 0; tx_count = 0;

        #20 rst_n = 1; #20;

        $display("=== INICIO TESTE COM VCD ===");
        
        // 1. Casos de Canto
        drive_transaction(16'd10, 16'd10, 2'b11); 
        drive_transaction(16'd32767, 16'd1, 2'b11);    
        drive_transaction(-16'd32768, 16'd1, 2'b11);   

        // 2. Burst (Pipeline Stress)
        for (i = 0; i < 5000; i = i + 1) begin
            ra = $random; rb = $random;
            drive_transaction(ra, rb, 2'b11);
        end

        #2000;
        
        if (read_ptr != write_ptr) $display("TIMEOUT: Itens pendentes na FIFO.");
        
        if (error_count == 0 && read_ptr == write_ptr) 
            $display("SUCESSO: VCD gerado. Abra 'booth_pipeline.vcd' no GTKWave.");
        else 
            $display("FALHA: %0d erros encontrados.", error_count);
            
        $finish;
    end
endmodule
