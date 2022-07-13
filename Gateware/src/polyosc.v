// Polyphonic oscillator for ICE-V
// 07-11-22 E. Brombaugh

`default_nettype none

`define DIV 14'd9999

module polyosc(
	// 12MHz external osc
	input clk_12MHz,
	
	// RISCV serial
	input rx,
	output tx,
	
	// RISCV SPI
	inout	spi0_mosi,		// SPI core 0
			spi0_miso,
			spi0_sclk,
			spi0_cs0,
	output	spi0_nwp,
			spi0_nhld,
			
	// RGB output
    output RGB0, RGB1, RGB2, // RGB LED outs
	
	// SPI slave port
	input SPI_CSL,
	input SPI_MOSI,
	output SPI_MISO,
	input SPI_SCLK,
	
	// PDM output to filter/amp PMOD
	output PMOD1_1, PMOD1_3, PMOD1_5,
	output PMOD3_1, PMOD3_3, PMOD3_5
);
	// This should be unique so firmware knows who it's talking to
	parameter DESIGN_ID = 32'hC1EF0000;

	//------------------------------
	// Clock PLL
	//------------------------------
	// Fin=12, FoutA=24, FoutB=48
	wire clk, clk24, pll_lock;
	SB_PLL40_2F_PAD #(
		.DIVR(4'b0000),
		.DIVF(7'b0111111),	// 24/48
		.DIVQ(3'b100),
		.FILTER_RANGE(3'b001),
		.FEEDBACK_PATH("SIMPLE"),
		.DELAY_ADJUSTMENT_MODE_FEEDBACK("FIXED"),
		.FDA_FEEDBACK(4'b0000),
		.DELAY_ADJUSTMENT_MODE_RELATIVE("FIXED"),
		.FDA_RELATIVE(4'b0000),
		.SHIFTREG_DIV_MODE(2'b00),
		.PLLOUT_SELECT_PORTA("GENCLK_HALF"),
		.PLLOUT_SELECT_PORTB("GENCLK"),
		.ENABLE_ICEGATE_PORTA(1'b0),
		.ENABLE_ICEGATE_PORTB(1'b0)
	)
	pll_inst (
		.PACKAGEPIN(clk_12MHz),
		.PLLOUTCOREA(),
		.PLLOUTGLOBALA(clk24),
		.PLLOUTCOREB(),
		.PLLOUTGLOBALB(clk),
		.EXTFEEDBACK(),
		.DYNAMICDELAY(8'h00),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		.LATCHINPUTVALUE(),
		.LOCK(pll_lock),
		.SDI(),
		.SDO(),
		.SCLK()
	);
	
	//------------------------------
	// reset generator waits > 10us
	//------------------------------
	reg [9:0] reset_cnt;
	reg reset, reset24;    
	always @(posedge clk or negedge pll_lock)
	begin
		if(!pll_lock)
		begin
			reset_cnt <= 10'h000;
			reset <= 1'b1;
		end
		else
		begin
			if(reset_cnt != 10'h3ff)
			begin
				reset_cnt <= reset_cnt + 10'h001;
				reset <= 1'b1;
			end
			else
				reset <= 1'b0;
		end
	end
	
	always @(posedge clk24 or negedge pll_lock)
		if(!pll_lock)
			reset24 <= 1'b1;
		else
			reset24 <= reset;
	
	//------------------------------
	// Internal SPI slave port
	//------------------------------
	wire [31:0] wdat;
	reg [31:0] rdat;
	wire [6:0] addr;
	wire re, we;
	spi_slave
		uspi(.clk(clk), .reset(reset),
			.spiclk(SPI_SCLK), .spimosi(SPI_MOSI),
			.spimiso(SPI_MISO), .spicsl(SPI_CSL),
			.we(we), .re(re), .wdat(wdat), .addr(addr), .rdat(rdat));
		
	//------------------------------
	// Writeable registers
	//------------------------------
	reg [31:0] gpio_torisc;
	always @(posedge clk)
	begin
		if(reset)
		begin
			gpio_torisc <= 32'd0;
		end
		else if(we)
		begin
			case(addr)
				7'h02: gpio_torisc <= wdat;
			endcase
		end
	end

	//------------------------------
	// readback
	//------------------------------
	wire [31:0] gpio_fromrisc;
	always @(*)
	begin
		case(addr)
			7'h00: rdat = DESIGN_ID;
			7'h01: rdat = gpio_fromrisc;
			7'h02: rdat = gpio_torisc;
			default: rdat = 32'd0;
		endcase
	end
	
	// RISC-V CPU based serial I/O
	wire [1:0] pdm;
	wire [7:0] red, grn, blu;
	system u_riscv(
		.clk24(clk24),
		.reset(reset24),
		.RX(rx),
		.TX(tx),
		.spi0_mosi(spi0_mosi),
		.spi0_miso(spi0_miso),
		.spi0_sclk(spi0_sclk),
		.spi0_cs0(spi0_cs0),
		.pdm(pdm),
		.gp_in0(gpio_torisc),
		.gp_in1(32'h0),
		.gp_in2(32'h0),
		.gp_in3(32'h0),
		.gp_out0(gpio_fromrisc),
		.gp_out1({red,grn,blu}),
		.gp_out2(),
		.gp_out3()
	);
	
	// hook up rest of SPI flash port
	assign spi0_nwp = 1'b1;
	assign spi0_nhld = 1'b1;
		
	// hook up PDM
	assign PMOD1_1 = pdm[0];
	assign PMOD1_3 = pdm[1];
	assign PMOD1_5 = 1'b1;
	assign PMOD3_1 = pdm[0];
	assign PMOD3_3 = pdm[1];
	assign PMOD3_5 = 1'b1;
	
	//------------------------------
	// PWM dimming for the RGB DRV 
	//------------------------------
	reg [7:0] pwm_cnt;
	reg r_pwm, g_pwm, b_pwm;
	always @(posedge clk)
		if(reset)
		begin
			pwm_cnt <= 8'd0;
		end
		else
		begin
			pwm_cnt <= pwm_cnt + 1;
			r_pwm <= pwm_cnt < red;
			g_pwm <= pwm_cnt < grn;
			b_pwm <= pwm_cnt < blu;
		end
	
	//------------------------------
	// Instantiate RGB DRV 
	//------------------------------
	SB_RGBA_DRV #(
		.CURRENT_MODE("0b1"),
		.RGB0_CURRENT("0b000001"),
		.RGB1_CURRENT("0b000001"),
		.RGB2_CURRENT("0b000001")
	) RGBA_DRIVER (
		.CURREN(1'b1),
		.RGBLEDEN(1'b1),
		.RGB0PWM(r_pwm),
		.RGB1PWM(g_pwm),
		.RGB2PWM(b_pwm),
		.RGB0(RGB0),
		.RGB1(RGB1),
		.RGB2(RGB2)
	);
endmodule
