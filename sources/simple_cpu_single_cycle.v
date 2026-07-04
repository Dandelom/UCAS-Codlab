`timescale 10ns / 1ns

`define OPCODE_LUI	7'b0110111
`define OPCODE_AUIPC	7'b0010111
`define OPCODE_JAL	7'b1101111
`define OPCODE_JALR	7'b1100111
`define OPCODE_BRANCH	7'b1100011
`define OPCODE_LOAD	7'b0000011
`define OPCODE_STORE	7'b0100011
`define OPCODE_IMM	7'b0010011
`define OPCODE_CALC	7'b0110011
`define DATA_WIDTH 32
`define ADDR_WIDTH 5
`define ALUOP_AND 3'b000
`define ALUOP_OR 3'b001
`define ALUOP_XOR 3'b100
`define ALUOP_NOR 3'b101
`define ALUOP_ADD 3'b010
`define ALUOP_SUB 3'b110
`define ALUOP_SLT 3'b111
`define ALUOP_SLTU 3'b011
`define SHIFTOP_LEFT 2'b00
`define SHIFTOP_ARITH_RIGHT 2'b11
`define SHIFTOP_LOGIC_RIGHT 2'b10

module simple_cpu(
	input             clk,
	input             rst,

	output [31:0]     PC,
	input  [31:0]     Instruction,

	output [31:0]     Address,
	output            MemWrite,
	output [31:0]     Write_data,
	output [ 3:0]     Write_strb,

	input  [31:0]     Read_data,
	output            MemRead
);

	// THESE THREE SIGNALS ARE USED IN OUR TESTBENCH
	// PLEASE DO NOT MODIFY SIGNAL NAMES
	// AND PLEASE USE THEM TO CONNECT PORTS
	// OF YOUR INSTANTIATION OF THE REGISTER FILE MODULE
	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;

	// Instanitation of Register File
	wire [4:0]	raddr1, raddr2;
	wire [31:0]	rdata1, rdata2;
	reg_file reg_file_i(
		.clk	(clk),
		.waddr	(RF_waddr),
		.raddr1	(raddr1),
		.raddr2 (raddr2),
		.wen	(RF_wen),
		.wdata	(RF_wdata),
		.rdata1 (rdata1),
		.rdata2	(rdata2)
	);

	// Instanitation of ALU
	wire [31:0]	src1, src2, ALU_Result;
	wire [2:0]	ALUop;
	wire Overflow, CarryOut, Zero;
	alu alu_i(
		.A		(src1),
		.B		(src2),
		.ALUop		(ALUop),
		.Overflow	(Overflow),
		.CarryOut	(CarryOut),
		.Zero		(Zero),
		.Result		(ALU_Result)
	);

	// Instanitation of Shifter
	wire [31:0]	Shift_src1;
	wire [4:0]	Shift_src2;
	wire [1:0]	Shiftop;
	wire [31:0]	Shifter_Result;
	shifter shifter_i(
		.A		(Shift_src1),
		.B		(Shift_src2),
		.Shiftop	(Shiftop),
		.Result		(Shifter_Result)
	);

	// Variants Definition
	reg  [31:0]	pc_reg;
	wire [31:0]	next_pc_reg;
	wire [31:0]	pc_plus_4, pc_JAL, pc_JALR, pc_BRAN;
	wire [6:0]	opcode;
	wire [4:0]	rd;
	wire [2:0]	funct3;
	wire [6:0]	funct7;
	wire [4:0]	shamt;
	wire [31:0]	U_imm, J_imm, I_imm, B_imm, S_imm;
	wire [2:0]	ALUop_BRANCH, ALUop_IMM, ALUop_CALC;
	wire Branch;
	wire is_shift_imm;
	wire op_LUI = (opcode == `OPCODE_LUI);
	wire op_AUIPC = (opcode == `OPCODE_AUIPC);
	wire op_JAL = (opcode == `OPCODE_JAL);
	wire op_JALR = (opcode == `OPCODE_JALR);
	wire op_BRANCH = (opcode == `OPCODE_BRANCH);
	wire op_LOAD = (opcode == `OPCODE_LOAD);
	wire op_STORE = (opcode == `OPCODE_STORE);
	wire op_IMM = (opcode == `OPCODE_IMM);
	wire op_CALC = (opcode == `OPCODE_CALC);
	wire [31:0] Load_data;
	wire [31:0] shifted_read_data = Read_data >> {ALU_Result[1:0], 3'b000};
	wire [31:0] short_data;

	// Instruction Fetch(PC)
	assign PC = pc_reg;
	assign pc_plus_4 = PC + 4;
	assign pc_JAL = PC + J_imm;
	assign pc_JALR = (rdata1 + I_imm) & ~32'h1;
	assign pc_BRAN = PC + B_imm;
	assign next_pc_reg = 
		({32{op_JAL}} & pc_JAL)  |
		({32{op_JALR}} & pc_JALR) |
		({32{Branch}} & pc_BRAN) |
		({32{!op_JAL & !op_JALR & !Branch}} & pc_plus_4);

	always @(posedge clk) begin
		if(rst) begin
			pc_reg <= 32'h0;
		end else begin
			pc_reg <= next_pc_reg;
		end
	end

	// Instruction Decode
	assign opcode = Instruction [6:0];
	assign rd = Instruction [11:7];
	assign funct3 = Instruction [14:12];
	assign funct7 = Instruction [31:25];
	assign raddr1 = Instruction [19:15];
	assign raddr2 = Instruction [24:20];
	assign shamt = Instruction [24:20];
	assign U_imm = {Instruction [31:12], 12'b0};
	assign J_imm = {{11{Instruction [31]}}, Instruction [31], Instruction [19:12], Instruction [20], Instruction [30:21], 1'b0};
	assign I_imm = {{20{Instruction [31]}}, Instruction [31:20]};
	assign B_imm = {{19{Instruction [31]}}, Instruction [31], Instruction [7], Instruction [30:25], Instruction [11:8], 1'b0};
	assign S_imm = {{20{Instruction [31]}}, Instruction [31:25], Instruction [11:7]};

	assign Branch = (op_BRANCH) && (
		(funct3 == 3'b000 & Zero)      | // BEQ
		(funct3 == 3'b001 & !Zero)     | // BNE
		(funct3 == 3'b100 & ALU_Result[0]) | // BLT
		(funct3 == 3'b101 & !ALU_Result[0])| // BGE
		(funct3 == 3'b110 & ALU_Result[0]) | // BLTU
		(funct3 == 3'b111 & !ALU_Result[0])  // BGEU
	);

	// Execute
	assign src1 = rdata1;
	assign src2 = 
		({32{op_LOAD | op_IMM}} & I_imm)  |
		({32{op_STORE}}         & S_imm)  |
		({32{!op_LOAD & !op_IMM & !op_STORE}} & rdata2);
	assign Shift_src1 = rdata1;
	assign Shift_src2 = op_CALC ? rdata2[4:0] : shamt;
	assign ALUop_BRANCH = 
		({3{funct3[2:1] == 2'b00}} & `ALUOP_SUB) | // BEQ, BNE
		({3{funct3[2:1] == 2'b10}} & `ALUOP_SLT) | // BLT, BGE
		({3{funct3[2:1] == 2'b11}} & `ALUOP_SLTU)| // BLTU, BGEU
		({3{funct3[2:1] == 2'b01}} & `ALUOP_ADD);
	assign ALUop_IMM = 
		({3{funct3 == 3'b000}} & `ALUOP_ADD)  |
		({3{funct3 == 3'b010}} & `ALUOP_SLT)  |
		({3{funct3 == 3'b011}} & `ALUOP_SLTU) |
		({3{funct3 == 3'b100}} & `ALUOP_XOR)  |
		({3{funct3 == 3'b110}} & `ALUOP_OR)   |
		({3{funct3 == 3'b111}} & `ALUOP_AND)  |
		({3{funct3 == 3'b001 | funct3 == 3'b101}} & `ALUOP_ADD);
	assign ALUop_CALC = 
		({3{funct3 == 3'b000 & funct7[5]}} & `ALUOP_SUB) |
	        ({3{!(funct3 == 3'b000 & funct7[5])}} & ALUop_IMM);
	assign ALUop = 
		({3{op_BRANCH}} & ALUop_BRANCH) |
		({3{op_IMM}}    & ALUop_IMM)    |
		({3{op_CALC}}   & ALUop_CALC) |
		({3{!op_BRANCH & !op_IMM & !op_CALC}} & `ALUOP_ADD);
	assign Shiftop = 
		({2{funct3 == 3'b001}} & `SHIFTOP_LEFT) |
		({2{funct3 == 3'b101 & !funct7[5]}} & `SHIFTOP_LOGIC_RIGHT) |
		({2{funct3 == 3'b101 &  funct7[5]}} & `SHIFTOP_ARITH_RIGHT);
	assign is_shift_imm = ((op_IMM | op_CALC) & (funct3[1:0] == 2'b01));

	// Memory-Access and Write-Back 
	assign Address = {ALU_Result[31:2], 2'b00};
	assign MemRead = op_LOAD;
	assign MemWrite = op_STORE;
	assign Load_data = 
		({32{funct3 == 3'b000}} & {{24{shifted_read_data[7]}},  shifted_read_data[7:0]})  | // LB
		({32{funct3 == 3'b001}} & {{16{shifted_read_data[15]}}, shifted_read_data[15:0]}) | // LH
		({32{funct3 == 3'b010}} & shifted_read_data)                                      | // LW
		({32{funct3 == 3'b100}} & {24'b0, shifted_read_data[7:0]})                        | // LBU
		({32{funct3 == 3'b101}} & {16'b0, shifted_read_data[15:0]});
	assign short_data = 
		({32{funct3 == 3'b000}} & {24'h0, rdata2[7:0]})  | // SB
		({32{funct3 == 3'b001}} & {16'h0, rdata2[15:0]}) | // SH
		({32{funct3 == 3'b010}} & rdata2); // SW
	assign Write_data = (op_STORE) ? (short_data << (ALU_Result[1:0] * 8)) : 32'b0;
	assign Write_strb = 
		({4{op_STORE & (funct3 == 3'b000)}} & (4'b0001 << ALU_Result[1:0])) |
		({4{op_STORE & (funct3 == 3'b001)}} & (4'b0011 << ALU_Result[1:0])) |
		({4{op_STORE & (funct3 == 3'b010)}} & 4'b1111);
	assign RF_waddr = rd;
	assign RF_wdata = 
		({32{op_LUI}} & U_imm) |
		({32{op_AUIPC}} & (U_imm + pc_reg)) |
		({32{op_JAL | op_JALR}} & (pc_reg + 4)) |
		({32{op_LOAD}} & Load_data) |
		({32{(op_IMM | op_CALC) & !is_shift_imm}} & ALU_Result) |
		({32{(op_IMM | op_CALC) &  is_shift_imm}} & Shifter_Result);
	assign RF_wen = op_LUI | op_AUIPC | op_JAL | op_JALR | op_LOAD | op_IMM | op_CALC;

endmodule