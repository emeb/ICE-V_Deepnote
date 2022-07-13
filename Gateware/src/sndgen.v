/*
 * sndgen.v - sound generator for RISC-V soft system
 * 06-15-22 E. Brombaugh
 */

`default_nettype none

// low-level PDM encoder
module pdm_enc #(
	parameter integer DSZ = 16
)(
	input clk,
	input reset,
	input clk_en,
	input signed [DSZ-1:0] data,
	output pdm
);
	wire [DSZ-1:0] ob = data ^ {1'b1,{DSZ-1{1'b0}}};
	reg  [DSZ:0] sd_acc;

	always @(posedge clk)
	begin
		if(reset)
			sd_acc <= 0;
		else if(clk_en)
			sd_acc <= {1'b0,sd_acc[DSZ-1:0]} + {1'b0,ob};
	end

	assign pdm = sd_acc[DSZ];
endmodule
	
// 256x32 R/W memory for multiple oscillators
module bram_256x32(
	input clk,
	input sel,
	input [3:0] we,
	input [7:0] waddr,
	input [7:0] raddr,
	input [31:0] wdat,
	output reg [31:0] rdat
);
	// memory
	reg [31:0] ram[255:0];
	
	// write logic
	always @(posedge clk)
		if(sel)
		begin
			if(we[0])
				ram[waddr][7:0] <= wdat[7:0];
			if(we[1])
				ram[waddr][15:8] <= wdat[15:8];
			if(we[2])
				ram[waddr][23:16] <= wdat[23:16];
			if(we[3])
				ram[waddr][31:24] <= wdat[31:24];
		end
	
	// read logic
	always @(posedge clk)
		rdat <= ram[raddr];
endmodule
	

// top of sound generator
module sndgen(
	input clk,				// system clock
	input reset,			// system reset
	input cs,				// chip select
	input [3:0] we,			// write enable
	input [7:0] addr,		// register select
	input [31:0] din,		// data bus input
	inout [1:0] pdm			// stereo PDM output
);
	// 32-step sequencer
	reg [4:0] seq, seq_d1, seq_d2;
	reg sync_d3;
	always @(posedge clk)
		if(reset)
		begin
			seq <= 5'h00;
			seq_d1 <= 5'h00;
			seq_d2 <= 5'h00;
			sync_d3 <= 1'b0;
		end
		else
		begin
			seq <= seq + 1;
			seq_d1 <= seq;
			seq_d2 <= seq_d1;
			sync_d3 <= (seq_d2==5'h00);
		end
	
	// parameter storage
	wire [31:0] frq;	// valid @ seq_d1
	wire fsel = cs & ~addr[6];
	bram_256x32 ufrq(
		.clk(clk),
		.sel(fsel),
		.we(we),
		.waddr({3'b000,addr[4:0]}),
		.raddr({3'b000,seq}),
		.wdat(din),
		.rdat(frq)
	);
	
	wire [31:0] amp;	// valid @ seq_d2
	wire asel = cs & addr[6];
	bram_256x32 uamp(
		.clk(clk),
		.sel(asel),
		.we(we),
		.waddr({3'b000,addr[4:0]}),
		.raddr({3'b000,seq_d1}),
		.wdat(din),
		.rdat(amp)
	);
	
	// NCO bank
	wire [31:0] phs_in;	// valid @ seq_d1
	reg [31:0] phs;	// valid @ seq_d2
	bram_256x32 uphs(
		.clk(clk),
		.sel(1'b1),
		.we(4'b1111),
		.waddr({3'b000,seq_d2}),
		.raddr({3'b000,seq}),
		.wdat(phs),
		.rdat(phs_in)
	);
	always @(posedge clk)
		if(reset)
			phs <= 32'd0;
		else
			phs <= phs_in + frq;
	
	// wave shape
	wire signed [15:0] saw = phs[31:16];
	
	// bust out amplitude channels
	wire signed [15:0] la = amp[15:0], ra = amp[31:16];
		
	// gain
	reg signed [31:0] lg, rg; // valid @ sync_d3
	always @(posedge clk)
		if(reset)
		begin
			lg <= 32'd0;
			rg <= 32'd0;
		end
		else
		begin
			lg <= saw * la;
			rg <= saw * ra;
		end
	
	// mix accumulators
	wire signed [20:0]	lg_x = {{5{lg[30]}},lg[30:15]},
						rg_x = {{5{rg[30]}},rg[30:15]}; 
	reg signed [20:0] acc_l, acc_r;
	reg signed [15:0] mix_l, mix_r;
	wire signed [15:0] sat_l, sat_r;
	always @(posedge clk)
		if(reset)
		begin
			acc_l <= 21'h000000;
			acc_r <= 21'h000000;
			mix_l <= 16'h0000;
			mix_r <= 16'h0000;
		end
		else
		begin
			if(sync_d3)
			begin
				// dump
				acc_l <= lg_x + 21'h000010;
				acc_r <= rg_x + 21'h000010;
				mix_l <= sat_l;
				mix_r <= sat_r;
			end
			else
			begin
				// integrate
				acc_l <= lg_x + acc_l;
				acc_r <= rg_x + acc_r;
			end
		end
	
	// saturation
`define SAT_SHF 4
	sat #(.isz(32-`SAT_SHF), .osz(16))
		u_lsat(.in(acc_l[31:`SAT_SHF]), .out(sat_l));
	sat #(.isz(32-`SAT_SHF), .osz(16))
		u_rsat(.in(acc_r[31:`SAT_SHF]), .out(sat_r));
		
	// outputs
	//wire pdm_clk_en = 1'b1;
	reg pdm_clk_en;
	reg [7:0] pdm_clk_cnt;
	always @(posedge clk)
		if(reset)
		begin
			pdm_clk_en <= 1'b1;
			pdm_clk_cnt <= 8'h00;
		end
		else
		begin
			pdm_clk_cnt <= pdm_clk_cnt + 8'h01;
			//pdm_clk_en <= &pdm_clk_cnt[3:0];
			pdm_clk_en <= 1'b1;
		end
		
	pdm_enc #(.DSZ(16))
		updm_l(
			.clk(clk),
			.reset(reset),
			.clk_en(pdm_clk_en),
			.data(mix_l),
			.pdm(pdm[0])
		);
	pdm_enc #(.DSZ(16))
		updm_r(
			.clk(clk),
			.reset(reset),
			.clk_en(pdm_clk_en),
			.data(mix_r),
			.pdm(pdm[1])
		);
endmodule
