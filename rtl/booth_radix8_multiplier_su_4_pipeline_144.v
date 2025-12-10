`timescale 1ns / 1ps
`default_nettype none

module booth_core_4cycle (
    input  wire                  clk,
    input  wire                  load,
    input  wire signed [7:0]     multiplicand,
    input  wire signed [7:0]     multiplier,
    input  wire [1:0]            sign_mode,
    output wire signed [15:0]    product,
    output wire                  valid_out
);
    localparam integer WIDTH = 8;
    localparam integer SHIFT_BITS = 9;
    localparam integer ACC_WIDTH = 11;
    localparam integer REG_WIDTH = 21;

    reg signed [REG_WIDTH-1:0] prod_reg;
    reg [2:0] cycle_cnt;
    reg active;

    reg signed [ACC_WIDTH-1:0] m_3x_reg;
    reg signed [ACC_WIDTH-1:0] mcand_ext_reg;

    wire sign_bit_a = sign_mode[1] & multiplicand[WIDTH-1];
    wire signed [ACC_WIDTH-1:0] mcand_extended = { {(ACC_WIDTH-WIDTH){sign_bit_a}}, multiplicand };
    wire signed [ACC_WIDTH-1:0] calc_3x = mcand_extended + (mcand_extended <<< 1);

    wire sign_bit_b = sign_mode[0] & multiplier[WIDTH-1];
    wire [REG_WIDTH-1:0] prod_reg_init = {
        {ACC_WIDTH{1'b0}},
        {(SHIFT_BITS-WIDTH){sign_bit_b}},
        multiplier,
        1'b0
    };

    wire [3:0] booth_bits = prod_reg[3:0];
    wire signed [ACC_WIDTH-1:0] acc_upper = prod_reg[REG_WIDTH-1 : SHIFT_BITS+1];

    reg sel_1x, sel_2x, sel_3x, sel_4x;
    always @(*) begin
        sel_1x = (booth_bits == 4'b0001) || (booth_bits == 4'b0010) || (booth_bits == 4'b1101) || (booth_bits == 4'b1110);
        sel_2x = (booth_bits == 4'b0011) || (booth_bits == 4'b0100) || (booth_bits == 4'b1011) || (booth_bits == 4'b1100);
        sel_3x = (booth_bits == 4'b0101) || (booth_bits == 4'b0110) || (booth_bits == 4'b1001) || (booth_bits == 4'b1010);
        sel_4x = (booth_bits == 4'b0111) || (booth_bits == 4'b1000);
    end

    wire inv = booth_bits[3] & ~(&booth_bits[2:0]);
    wire signed [ACC_WIDTH-1:0] m_1x = mcand_ext_reg;
    wire signed [ACC_WIDTH-1:0] m_2x = mcand_ext_reg <<< 1;
    wire signed [ACC_WIDTH-1:0] m_4x = mcand_ext_reg <<< 2;

    reg signed [ACC_WIDTH-1:0] mag_sel;
    always @(*) begin
        mag_sel = ({ACC_WIDTH{sel_1x}} & m_1x) | ({ACC_WIDTH{sel_2x}} & m_2x) |
                  ({ACC_WIDTH{sel_3x}} & m_3x_reg) | ({ACC_WIDTH{sel_4x}} & m_4x);
    end

    wire signed [ACC_WIDTH-1:0] operand_inv = mag_sel ^ {ACC_WIDTH{inv}};
    wire signed [ACC_WIDTH-1:0] sum_result  = acc_upper + operand_inv + { {(ACC_WIDTH-1){1'b0}}, inv };

    assign valid_out = (cycle_cnt == 3) && active;
    assign product   = prod_reg[16:1];

    always @(posedge clk) begin
        if (load) begin
            active        <= 1'b1;
            cycle_cnt     <= 0;
            mcand_ext_reg <= mcand_extended;
            m_3x_reg      <= calc_3x;
            prod_reg      <= prod_reg_init;
        end else if (active) begin
            prod_reg <= { {3{sum_result[ACC_WIDTH-1]}}, sum_result, prod_reg[SHIFT_BITS:3] };
            if (cycle_cnt == 3) active <= 1'b0;
            else cycle_cnt <= cycle_cnt + 1;
        end
    end
endmodule

module booth_radix8_multiplier #(
    parameter integer WIDTH = 16
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire signed [WIDTH-1:0]      multiplicand,
    input  wire signed [WIDTH-1:0]      multiplier,
    input  wire [1:0]                   sign_mode,
    output reg  signed [2*WIDTH-1:0]    product,
    output reg                          done,
    output wire                         busy
);

    // 1. INPUT STAGE
    reg r_start_in;
    reg signed [WIDTH-1:0] r_mcand_in, r_mult_in;
    reg [1:0] r_sign_mode_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_start_in <= 1'b0;
            r_mcand_in <= 0; r_mult_in <= 0; r_sign_mode_in <= 0;
        end else begin
            r_start_in <= start;
            if (start) begin
                r_mcand_in     <= multiplicand;
                r_mult_in      <= multiplier;
                r_sign_mode_in <= sign_mode;
            end
        end
    end

    // 2. DATA BUFFER
    reg signed [WIDTH-1:0] buf_mcand, buf_mult;
    reg [1:0] buf_sign_mode;
    reg buf_valid;

    wire core_ready;
    wire fire_core;

    // CORREÇÃO: Busy agora considera dados em trânsito no registrador de entrada (r_start_in).
    // Se o buffer já tem dados, ou se acabamos de receber um dado novo (r_start_in), estamos ocupados.
    // Isso garante que o testbench pare de enviar até que o buffer esvazie.
    assign busy = buf_valid || r_start_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_valid <= 1'b0;
            buf_mcand <= 0; buf_mult <= 0; buf_sign_mode <= 0;
        end else begin
            if (r_start_in) begin
                if (!buf_valid || core_ready) begin
                    buf_mcand     <= r_mcand_in;
                    buf_mult      <= r_mult_in;
                    buf_sign_mode <= r_sign_mode_in;
                    buf_valid     <= 1'b1;
                end
            end else if (fire_core) begin
                buf_valid <= 1'b0;
            end
        end
    end

    // 3. CORE SEQUENCER
    reg [2:0] core_timer;
    reg       core_active;

    assign core_ready = (!core_active) || (core_timer == 3);
    assign fire_core = buf_valid && core_ready;

    reg [1:0] active_sign_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_active <= 0;
            core_timer  <= 0;
            active_sign_mode <= 0;
        end else begin
            if (fire_core) begin
                core_active <= 1;
                core_timer  <= 0;
                active_sign_mode <= buf_sign_mode;
            end else if (core_active) begin
                if (core_timer == 3) core_active <= 0;
                else core_timer <= core_timer + 1;
            end
        end
    end

    // 4. INSTANCE CORES
    wire signed [15:0] w_p0, w_p1, w_p2, w_p3;
    wire core_done_pulse;

    booth_core_4cycle u0 (.clk(clk), .load(fire_core), .multiplicand(buf_mcand[7:0]),  .multiplier(buf_mult[7:0]),  .sign_mode(2'b00), .product(w_p0), .valid_out(core_done_pulse));
    booth_core_4cycle u1 (.clk(clk), .load(fire_core), .multiplicand(buf_mcand[15:8]), .multiplier(buf_mult[7:0]),  .sign_mode({buf_sign_mode[1], 1'b0}), .product(w_p1), .valid_out());
    booth_core_4cycle u2 (.clk(clk), .load(fire_core), .multiplicand(buf_mcand[7:0]),  .multiplier(buf_mult[15:8]), .sign_mode({1'b0, buf_sign_mode[0]}), .product(w_p2), .valid_out());
    booth_core_4cycle u3 (.clk(clk), .load(fire_core), .multiplicand(buf_mcand[15:8]), .multiplier(buf_mult[15:8]), .sign_mode(buf_sign_mode), .product(w_p3), .valid_out());

    // 5. OUTPUT RECONSTRUCTION
    reg signed [17:0] pipe_sum_p1_p2;
    reg signed [23:0] pipe_base;
    reg [7:0]         pipe_p0_low;
    reg               pipe_valid;

    wire s1 = w_p1[15] & active_sign_mode[1];
    wire s2 = w_p2[15] & active_sign_mode[0];
    wire signed [17:0] calc_sum_p1_p2 = {{2{s1}}, w_p1} + {{2{s2}}, w_p2};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid <= 0;
            pipe_sum_p1_p2 <= 0; pipe_base <= 0; pipe_p0_low <= 0;
            product <= 0; done <= 0;
        end else begin
            done <= 0;
            if (core_done_pulse) begin
                pipe_sum_p1_p2 <= calc_sum_p1_p2;
                pipe_base      <= {w_p3, w_p0[15:8]};
                pipe_p0_low    <= w_p0[7:0];
                pipe_valid     <= 1;
            end else begin
                pipe_valid <= 0;
            end

            if (pipe_valid) begin
                product[31:8] <= pipe_base + {{6{pipe_sum_p1_p2[17]}}, pipe_sum_p1_p2};
                product[7:0]  <= pipe_p0_low;
                done          <= 1;
            end
        end
    end
endmodule
`default_nettype wire

