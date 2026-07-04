`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ALUOP_AND 3'b000
`define ALUOP_OR 3'b001
`define ALUOP_XOR 3'b100
`define ALUOP_NOR 3'b101
`define ALUOP_ADD 3'b010
`define ALUOP_SUB 3'b110
`define ALUOP_SLT 3'b111
`define ALUOP_SLTU 3'b011

module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	
	wire op_and = ALUop == `ALUOP_AND;
	wire op_or = ALUop == `ALUOP_OR;
	wire op_xor = ALUop == `ALUOP_XOR;
	wire op_nor = ALUop == `ALUOP_NOR;
	wire op_add = ALUop == `ALUOP_ADD;
	wire op_sub = ALUop == `ALUOP_SUB;
	wire op_slt = ALUop == `ALUOP_SLT;
	wire op_sltu = ALUop == `ALUOP_SLTU;

	wire [`DATA_WIDTH - 1:0] and_res, or_res, xor_res, nor_res, add_res, slt_res, sltu_res;

	assign and_res = A & B;
	assign or_res = A | B;
	assign xor_res = A ^ B;
	assign nor_res = ~ or_res;
	wire complement_sign = (op_sub | op_slt) | op_sltu;
	wire carry_sign;
	wire [`DATA_WIDTH - 1:0] B_2 = complement_sign ? ~B:B;
	assign {carry_sign, add_res} = A + B_2 + complement_sign;
	assign CarryOut = carry_sign ^ op_sub;
	assign Overflow = (A[`DATA_WIDTH - 1] != add_res[`DATA_WIDTH - 1]) && (A[`DATA_WIDTH - 1] == B_2[`DATA_WIDTH - 1]);
	assign slt_res = {31'b0, add_res[31] ^ Overflow};
	assign sltu_res = {31'b0, ~ CarryOut};
	assign Result = 
		{32{op_and}} & and_res |
		{32{op_or}} & or_res |
		{32{op_xor}} & xor_res |
		{32{op_nor}} & nor_res |
		({32{op_add}} | {32{op_sub}}) & add_res |
		{32{op_slt}} & slt_res |
		{32{op_sltu}} & sltu_res;
	assign Zero = Result == 32'b0;

endmodule
