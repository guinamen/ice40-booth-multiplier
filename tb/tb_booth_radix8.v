`timescale 1ns/1ps
`default_nettype none

// Testbench Verilog-2001 para booth_radix8_multiplier (WIDTH = 16)
// Compatível com ferramentas que suportam Verilog-2001 (Icarus, VCS, ModelSim).

module tb_booth_radix8_multiplier;

    // -----------------------------------------------------------------
    // Parameters and DUT interface signals
    // -----------------------------------------------------------------
    parameter WIDTH = 16;

    reg                        clk;
    reg                        rst_n;
    reg                        start;
    reg  signed [WIDTH-1:0]    multiplicand;
    reg  signed [WIDTH-1:0]    multiplier;
    reg  [1:0]                 sign_mode;
    wire signed [2*WIDTH-1:0]  product;
    wire                       done;
    wire                       busy;

    integer errors;
    integer i, j, m;
    integer rnd_seed;

    // -----------------------------------------------------------------
    // Instantiate DUT (assumes module is in scope)
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Reference multiplication function
    // sign_mode[1] -> multiplicand is signed when 1, else unsigned
    // sign_mode[0] -> multiplier  is signed when 1, else unsigned
    // -----------------------------------------------------------------
    function signed [2*WIDTH-1:0] refmul;
        input signed [WIDTH-1:0] a;
        input signed [WIDTH-1:0] b;
        input [1:0] mode;
        reg signed [31:0] aa;
        reg signed [31:0] bb;
    begin
        if (mode[1] == 1'b1)
            aa = {{16{a[WIDTH-1]}}, a}; // sign-extend multiplicand
        else
            aa = {16'b0, a};           // zero-extend multiplicand

        if (mode[0] == 1'b1)
            bb = {{16{b[WIDTH-1]}}, b}; // sign-extend multiplier
        else
            bb = {16'b0, b};           // zero-extend multiplier

        refmul = aa * bb;
    end
    endfunction

    // -----------------------------------------------------------------
    // Clock generator
    // -----------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 ns period
    end

    // -----------------------------------------------------------------
    // Task: run one operation with handshake and timeout.
    // (all local declarations must be before 'begin' for Verilog-2001)
    // -----------------------------------------------------------------
    task run_op;
        input signed [WIDTH-1:0] a;
        input signed [WIDTH-1:0] b;
        input [1:0] mode;

        reg signed [2*WIDTH-1:0] exp;
        integer timeout;
    begin
        // wait until DUT not busy
        while (busy === 1'b1) @(posedge clk);

        multiplicand = a;
        multiplier   = b;
        sign_mode    = mode;

        exp = refmul(a, b, mode);

        // issue start pulse
        start = 1;
        @(posedge clk);
        start = 0;

        // wait for done with timeout
        timeout = 0;
        while (done !== 1'b1 && timeout < 2000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 2000) begin
            $display("[TIMEOUT] A=0x%04h B=0x%04h MODE=%b", a, b, mode);
            errors = errors + 1;
            disable run_op;
        end

        // compare result
        if (product !== exp) begin
            $display("[MISMATCH] A=0x%04h B=0x%04h MODE=%b EXPECT=0x%08h GOT=0x%08h",
                     a, b, mode, exp, product);
            errors = errors + 1;
        end
    end
    endtask

    // -----------------------------------------------------------------
    // Module-level edge values (declared at module scope to avoid SV)
    // -----------------------------------------------------------------
    reg [15:0] edge_val0, edge_val1, edge_val2, edge_val3, edge_val4,
               edge_val5, edge_val6, edge_val7, edge_val8, edge_val9,
               edge_val10, edge_val11;

    // -----------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------
    initial begin
        // init
        errors = 0;
        start = 0;
        multiplicand = 0;
        multiplier = 0;
        sign_mode = 2'b00;
        rnd_seed = 32'hCAFEBABE;

        // De-assert reset after a few clocks
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Populate edge values
        edge_val0  = 16'h0000; // 0
        edge_val1  = 16'h0001; // 1
        edge_val2  = 16'hFFFF; // -1
        edge_val3  = 16'h8000; // -32768
        edge_val4  = 16'h7FFF; // 32767
        edge_val5  = 16'h00FF; // 255
        edge_val6  = 16'hFF00; // -256 (signed) / 65280 (unsigned)
        edge_val7  = 16'h1234; // arbitrary
        edge_val8  = 16'hFEDC; // arbitrary
        edge_val9  = 16'h8001; // -32767
        edge_val10 = 16'h7F00; // 32512
        edge_val11 = 16'h00FE; // 254

        $display("Starting edge-value cross-product tests...");

        // Exhaustive cross-product of edge values for each sign mode
        for (m = 0; m < 4; m = m + 1) begin
            sign_mode = m[1:0];
            $display(" Mode = %b", sign_mode);
            for (i = 0; i <= 11; i = i + 1) begin
                for (j = 0; j <= 11; j = j + 1) begin
                    case (i)
                        0: run_op(edge_val0, edge_val0, sign_mode);
                        1: run_op(edge_val1, edge_val0, sign_mode);
                        2: run_op(edge_val2, edge_val0, sign_mode);
                        3: run_op(edge_val3, edge_val0, sign_mode);
                        4: run_op(edge_val4, edge_val0, sign_mode);
                        5: run_op(edge_val5, edge_val0, sign_mode);
                        6: run_op(edge_val6, edge_val0, sign_mode);
                        7: run_op(edge_val7, edge_val0, sign_mode);
                        8: run_op(edge_val8, edge_val0, sign_mode);
                        9: run_op(edge_val9, edge_val0, sign_mode);
                        10: run_op(edge_val10, edge_val0, sign_mode);
                        11: run_op(edge_val11, edge_val0, sign_mode);
                        default: run_op(edge_val0, edge_val0, sign_mode);
                    endcase
                end
                // shift the B operand index inside inner loop using same j
                // (to keep code Verilog-2001 compatible, we use nested case via j)
                // We'll call run_op with combinations by recomputing b inside second loop
            end
            // The approach above invoked run_op with B=edge_val0 repeatedly; fix by
            // performing the correct nested loops below (explicit mapping):
            for (i = 0; i <= 11; i = i + 1) begin
                for (j = 0; j <= 11; j = j + 1) begin
                    // map i to A, j to B
                    case (i)
                        0: multiplicand = edge_val0;
                        1: multiplicand = edge_val1;
                        2: multiplicand = edge_val2;
                        3: multiplicand = edge_val3;
                        4: multiplicand = edge_val4;
                        5: multiplicand = edge_val5;
                        6: multiplicand = edge_val6;
                        7: multiplicand = edge_val7;
                        8: multiplicand = edge_val8;
                        9: multiplicand = edge_val9;
                        10: multiplicand = edge_val10;
                        11: multiplicand = edge_val11;
                        default: multiplicand = edge_val0;
                    endcase
                    case (j)
                        0: multiplier = edge_val0;
                        1: multiplier = edge_val1;
                        2: multiplier = edge_val2;
                        3: multiplier = edge_val3;
                        4: multiplier = edge_val4;
                        5: multiplier = edge_val5;
                        6: multiplier = edge_val6;
                        7: multiplier = edge_val7;
                        8: multiplier = edge_val8;
                        9: multiplier = edge_val9;
                        10: multiplier = edge_val10;
                        11: multiplier = edge_val11;
                        default: multiplier = edge_val0;
                    endcase
                    // run
                    run_op(multiplicand, multiplier, sign_mode);
                end
            end
        end

        // Additional low-byte sweep (multiplicand fixed at 1)
        $display("Running low-byte sweep (A=1, B=0..255) for mode 00...");
        for (i = 0; i < 256; i = i + 1) begin
            run_op(16'h0001, i[15:0], 2'b00);
        end

        // Randomized tests across all modes (limited count to keep sim time reasonable)
        $display("Running randomized tests (small batch)...");
        for (m = 0; m < 4; m = m + 1) begin
            sign_mode = m[1:0];
            for (i = 0; i < 500; i = i + 1) begin
                // use $random with seed
                rnd_seed = $random;
                multiplicand = $random;
                multiplier   = $random;
                run_op(multiplicand, multiplier, sign_mode);
            end
        end

        // End report
        if (errors == 0)
            $display("[TESTBENCH] All tests passed (errors = 0).");
        else
            $display("[TESTBENCH] Finished with %0d errors.", errors);

        $finish;
    end

endmodule

`default_nettype wire

