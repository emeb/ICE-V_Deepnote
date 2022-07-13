/*
 * tb_sndgen.v - testbench for sound generator
 * 06-15-22 E. Brombaugh
 */

`timescale 1ns/1ps
`default_nettype none

module tb_sndgen;
	reg clk;
	reg reset;
	reg snd_sel;
	reg [3:0] we;
	reg [7:0] addr;
	reg [31:0] din;
	wire [1:0] pdm;
	
	initial
	begin
`ifdef icarus
  		$dumpfile("tb_sndgen.vcd");
		$dumpvars;
`endif
		
		// init inputs
		clk = 1'b1;
		reset = 1'b1;
		snd_sel = 1'b0;
		we = 4'b0000;
		addr = 8'h00;
		din = 32'd0;
	
		// release reset
		#100
		reset = 1'b0;
		
`ifdef icarus
        // stop after a while
		#10000000 $finish;
`endif		
	end
	
	// 24MHz clock
	always
		#20.8333 clk = ~clk;

	// UUT
	sndgen uut(
		.clk(clk),
		.reset(reset),
		.cs(snd_sel),
		.we(we),
		.addr(addr),
		.din(din),
		.pdm(pdm)
	);
endmodule
