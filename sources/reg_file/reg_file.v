`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 5

module reg_file(
	input                       clk,
	input  [`ADDR_WIDTH - 1:0]  waddr,
	input  [`ADDR_WIDTH - 1:0]  raddr1,
	input  [`ADDR_WIDTH - 1:0]  raddr2,
	input                       wen,
	input  [`DATA_WIDTH - 1:0]  wdata,
	output [`DATA_WIDTH - 1:0]  rdata1,
	output [`DATA_WIDTH - 1:0]  rdata2
);

	reg [`DATA_WIDTH - 1:0] rf [0:31];

		always @(posedge clk) begin
		rf [0] <= 0;
		if(waddr != 0 && wen == 1)
			rf[waddr] <= wdata;
	end
	
	wire bypass1 = wen && (waddr == raddr1);
	wire bypass2 = wen && (waddr == raddr2);

	assign rdata1 = (rf[raddr1] & {32{~bypass1}}) | (wdata & {32{bypass1}});
	assign rdata2 = (rf[raddr2] & {32{~bypass2}}) | (wdata & {32{bypass2}});

endmodule
