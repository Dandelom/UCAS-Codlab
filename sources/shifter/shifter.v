`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define SHIFTOP_LEFT 2'b00
`define SHIFTOP_ARITH_RIGHT 2'b11
`define SHIFTOP_LOGIC_RIGHT 2'b10

module shifter (
	input  [`DATA_WIDTH - 1:0] A,
	input  [              4:0] B,
	input  [              1:0] Shiftop,
	output [`DATA_WIDTH - 1:0] Result
);
	wire op_left = Shiftop == `SHIFTOP_LEFT;
	wire op_arith_right = Shiftop == `SHIFTOP_ARITH_RIGHT;
	wire op_logic_right = Shiftop == `SHIFTOP_LOGIC_RIGHT;
	
	wire [`DATA_WIDTH - 1:0] res_left, res_arith_right, res_logic_right;

	assign res_left = A << B;
	assign res_arith_right = $signed(A) >>> B;
	assign res_logic_right = A >> B;

	assign Result = 
		{32{op_left}} & res_left |
		{32{op_arith_right}} & res_arith_right |
		{32{op_logic_right}} & res_logic_right;

endmodule
