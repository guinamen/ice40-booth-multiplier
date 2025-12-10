`timescale 1ns / 1ps
`default_nettype none

// dsp_mul16x16
// Single-cycle multiply (registered result). Intended to be mapped to DSP block
// when synthesized with synth_ice40 -dsp.
//
// Interface: clocked start/done handshake (start pulses, done asserted one cycle later).
module booth_radix8_multiplier (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,           // pulse start
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    output reg  signed [31:0] product,
    output reg                done
);
    // request registers
    reg signed [15:0] a_r;
    reg signed [15:0] b_r;
    reg               req_r;

    // Hint attribute to encourage DSP mapping (Yosys respects some attributes).
    // If your toolchain requires a different attribute, adapt accordingly.
    (* use_dsp = "yes" *) wire signed [31:0] raw_prod = a_r * b_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r       <= 16'sd0;
            b_r       <= 16'sd0;
            req_r     <= 1'b0;
            product   <= 32'sd0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                // capture inputs this cycle
                a_r   <= a;
                b_r   <= b;
                req_r <= 1'b1;
            end else if (req_r) begin
                // product available next cycle (registered)
                product <= raw_prod;
                done    <= 1'b1;
                req_r   <= 1'b0;
            end
        end
    end
endmodule

