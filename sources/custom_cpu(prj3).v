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

module custom_cpu(
	input         clk,
	input         rst,

	//Instruction request channel
	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

/* The following signal is leveraged for behavioral simulation, 
* which is delivered to testbench.
*
* STUDENTS MUST CONTROL LOGICAL BEHAVIORS of THIS SIGNAL.
*
* inst_retired (70-bit): detailed information of the retired instruction,
* mainly including (in order) 
* { 
*   reg_file write-back enable  (69:69,  1-bit),
*   reg_file write-back address (68:64,  5-bit), 
*   reg_file write-back data    (63:32, 32-bit),  
*   retired PC                  (31: 0, 32-bit)
* }
*
*/
	wire		RF_wen;
	wire [4:0]	RF_waddr;
	wire [31:0]	RF_wdata;

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

	// States Definition
	localparam INIT = 9'b000000001;
	localparam IF  	= 9'b000000010;
	localparam IW 	= 9'b000000100;
	localparam ID 	= 9'b000001000;
	localparam EX	= 9'b000010000;
	localparam ST 	= 9'b000100000;
	localparam LD	= 9'b001000000;
	localparam RDW	= 9'b010000000;
	localparam WB	= 9'b100000000;

	// Variants Definition
	reg  [31:0]	pc_reg;
	reg  [31:0]	ALU_reg;
	reg  [31:0]	IR;
	reg  [31:0] 	A_reg, B_reg;
	reg  [31:0] 	MDR;
	reg  [8:0] 	current_state;
	reg  [8:0] 	next_state;
	reg  [31:0] 	ret_addr_reg;
	reg  [31:0] 	cur_pc;
	wire [31:0]	pc_plus_4 = pc_reg + 32'd4;
	wire [6:0]	opcode;
	wire [4:0]	rd;
	wire [2:0]	funct3;
	wire [6:0]	funct7;
	wire [4:0]	shamt;
	wire [31:0]	U_imm, J_imm, I_imm, B_imm, S_imm;
	wire [2:0]	ALUop_BRANCH, ALUop_IMM, ALUop_CALC;
	wire Branch;
	wire is_shift_imm;
	wire is_INIT    = (current_state == INIT);
	wire is_IF      = (current_state == IF);
	wire is_IW      = (current_state == IW);
	wire is_ID      = (current_state == ID);
	wire is_EX      = (current_state == EX);
	wire is_ST      = (current_state == ST);
	wire is_LD      = (current_state == LD);
	wire is_RDW     = (current_state == RDW);
	wire is_WB      = (current_state == WB);
	wire is_MEM	= (is_ST | is_LD | is_RDW);
	wire op_LUI 	= (opcode == `OPCODE_LUI);
	wire op_AUIPC 	= (opcode == `OPCODE_AUIPC);
	wire op_JAL 	= (opcode == `OPCODE_JAL);
	wire op_JALR 	= (opcode == `OPCODE_JALR);
	wire op_BRANCH 	= (opcode == `OPCODE_BRANCH);
	wire op_LOAD	= (opcode == `OPCODE_LOAD);
	wire op_STORE 	= (opcode == `OPCODE_STORE);
	wire op_IMM 	= (opcode == `OPCODE_IMM);
	wire op_CALC 	= (opcode == `OPCODE_CALC);
	wire [31:0] Load_data;
	wire [31:0] shifted_read_data;
	wire [31:0] Store_data;

	always @ (posedge clk) 
	begin
		if(rst == 1'b1)
			current_state <= INIT;
		else
			current_state <= next_state;
	end

	// States Transference
	always @(*) 
	begin
		case(current_state)
			INIT:
				next_state=IF;
			IF: 
				if(Inst_Req_Ready)
					next_state=IW;
				else
					next_state=IF;
			IW:
				if(Inst_Valid)
					next_state=ID;
				else
					next_state=IW;
			ID:
				next_state=EX;
			EX:	
				case(opcode)
					`OPCODE_BRANCH: next_state=IF;
					`OPCODE_JAL, `OPCODE_JALR, `OPCODE_LUI, `OPCODE_AUIPC, `OPCODE_CALC, `OPCODE_IMM: next_state=WB;
					`OPCODE_LOAD: next_state=LD;
					`OPCODE_STORE: next_state=ST;
					default: next_state=INIT;
				endcase
			ST:
				if(Mem_Req_Ready)
					next_state=IF;
				else
					next_state=ST;
			LD:
				if(Mem_Req_Ready)
					next_state=RDW;
				else
					next_state=LD;
			RDW:
				if(Read_data_Valid)
					next_state=WB;
				else
					next_state=RDW;
			WB:
				next_state=IF;
			default:
				next_state=INIT;
		endcase
	end

	// Handshake Signal
	assign Inst_Req_Valid 	= is_IF | 1'b0;
	assign Inst_Ready	= is_INIT | is_IW | 1'b0;
	assign Read_data_Ready 	= is_RDW | is_INIT | 1'b0;
	assign MemRead 		= (is_LD) | 1'b0;
	assign MemWrite 	= (is_ST) | 1'b0;
	assign inst_retire 	= {RF_wen, RF_waddr, RF_wdata, cur_pc};

	// Instruction Fetch & Wait
	always @(posedge clk) begin
		if(rst) begin
			IR <= 32'h00000013; // NOP
		end
		else if(is_IW & Inst_Valid & Inst_Ready) begin
			IR <= Instruction;
		end
	end

	// PC
	assign PC = pc_reg;

	always @(posedge clk) begin
		if(rst) begin
			pc_reg <= 32'h0;
		end else begin
			case (current_state)
			EX: begin
				if (Branch)
					pc_reg <= ALU_reg;
				else if (!Branch & op_BRANCH)
					pc_reg <= pc_plus_4;
				else if (op_JALR)
					pc_reg <= {ALU_Result[31:1], 1'b0};
				else
					pc_reg <= pc_reg;
			end
			WB: begin
				if (op_JAL)
					pc_reg <= ALU_reg;
				if(!(op_JALR | op_JAL))
					pc_reg <= pc_plus_4;
			end
			ST: begin
				if(Mem_Req_Ready)
					pc_reg <= pc_plus_4;
			end
			default:
				pc_reg <= pc_reg;
			endcase
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			cur_pc <= 32'h0;
		end
		else if (is_IF & Inst_Req_Ready) begin
			cur_pc <= pc_reg; 
		end
	end

	// Instruction Decode
	assign opcode = IR [6:0];
	assign rd = IR [11:7];
	assign funct3 = IR [14:12];
	assign funct7 = IR [31:25];
	assign raddr1 = IR [19:15];
	assign raddr2 = IR [24:20];
	assign shamt = IR [24:20];
	assign U_imm = {IR [31:12], 12'b0};
	assign J_imm = {{11{IR [31]}}, IR [31], IR [19:12], IR [20], IR [30:21], 1'b0};
	assign I_imm = {{20{IR [31]}}, IR [31:20]};
	assign B_imm = {{19{IR [31]}}, IR [31], IR [7], IR [30:25], IR [11:8], 1'b0};
	assign S_imm = {{20{IR [31]}}, IR [31:25], IR [11:7]};

	always @(posedge clk) begin
		if (rst) begin
			A_reg <= 32'h0;
			B_reg <= 32'h0;
		end 
		else if (current_state == ID) begin
			A_reg <= rdata1; 
			B_reg <= rdata2;
		end
	end

	always @(posedge clk) begin
		if (rst) ret_addr_reg <= 32'b0;
		else if (is_ID) ret_addr_reg <= pc_plus_4;
	end

	// Execute
	assign src1 = 
		({32{is_ID}} & pc_reg) |
              	({32{is_EX & (op_AUIPC | op_JAL)}} & pc_reg) |
              	({32{is_EX & !(op_AUIPC | op_JAL)}} & A_reg) |
             	({32{is_MEM}} & A_reg);	
	assign src2 = 
              	({32{is_ID}} & (({32{op_BRANCH}} & B_imm) | ({32{op_JAL}} & J_imm))) |
             	({32{is_EX}} & (
                  ({32{op_IMM | op_LOAD | op_JALR}} & I_imm) |
                  ({32{op_STORE}} & S_imm)  |
                  ({32{op_LUI | op_AUIPC}} & U_imm) |
                  ({32{op_CALC | op_BRANCH}} & B_reg)
             	 ));
	assign Shift_src1 = A_reg;
	assign Shift_src2 = 
		({5{is_EX & op_CALC}} & B_reg[4:0]) | 
                ({5{is_EX & op_IMM}}  & shamt);
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
		({3{is_ID}} & `ALUOP_ADD) |
		({3{is_EX}} & (
			({3{op_BRANCH}} & ALUop_BRANCH) |
			({3{op_IMM}}    & ALUop_IMM)    |
			({3{op_CALC}}   & ALUop_CALC) |
			({3{!op_BRANCH & !op_IMM & !op_CALC}} & `ALUOP_ADD)
		));
	assign Shiftop = 
		({2{funct3 == 3'b001}} & `SHIFTOP_LEFT) |
		({2{funct3 == 3'b101 & !funct7[5]}} & `SHIFTOP_LOGIC_RIGHT) |
		({2{funct3 == 3'b101 &  funct7[5]}} & `SHIFTOP_ARITH_RIGHT);
	assign is_shift_imm = ((op_IMM | op_CALC) & (funct3[1:0] == 2'b01));
	assign Branch = (op_BRANCH) & (
		(funct3 == 3'b000 & Zero)      | // BEQ
		(funct3 == 3'b001 & !Zero)     | // BNE
		(funct3 == 3'b100 & ALU_Result[0]) | // BLT
		(funct3 == 3'b101 & !ALU_Result[0])| // BGE
		(funct3 == 3'b110 & ALU_Result[0]) | // BLTU
		(funct3 == 3'b111 & !ALU_Result[0])  // BGEU
	);

	always @(posedge clk) begin
		if (rst) begin
			ALU_reg <= 32'h0;
		end
		else if (is_ID) begin
			if (op_BRANCH | op_JAL | op_AUIPC) begin
			ALU_reg <= ALU_Result; 
			end
		end
		else if (is_EX) begin
			if (!op_BRANCH & !op_JAL) begin
			ALU_reg <= ({32{is_shift_imm}}  & Shifter_Result) | 
				   ({32{!is_shift_imm}} & ALU_Result);
			end
		end
	end

	// Store
	assign Address = {32{is_MEM}} & {ALU_reg[31:2], 2'b00};
	assign shifted_read_data = MDR >> {ALU_reg[1:0], 3'b000};
	assign Store_data = 
		({32{funct3 == 3'b000}} & {24'h0, B_reg[7:0]})  | // SB
		({32{funct3 == 3'b001}} & {16'h0, B_reg[15:0]}) | // SH
		({32{funct3 == 3'b010}} & B_reg); // SW
	assign Write_data = ({32{op_STORE}} & (Store_data << {ALU_reg[1:0], 3'b000}));
	assign Write_strb = 
		({4{op_STORE & (funct3 == 3'b000)}} & (4'b0001 << ALU_reg[1:0])) |
		({4{op_STORE & (funct3 == 3'b001)}} & (4'b0011 << ALU_reg[1:0])) |
		({4{op_STORE & (funct3 == 3'b010)}} & 4'b1111);
	
	// Load
	assign Load_data = 
		({32{funct3 == 3'b000}} & {{24{shifted_read_data[7]}},  shifted_read_data[7:0]})  | // LB
		({32{funct3 == 3'b001}} & {{16{shifted_read_data[15]}}, shifted_read_data[15:0]}) | // LH
		({32{funct3 == 3'b010}} & shifted_read_data)                                      | // LW
		({32{funct3 == 3'b100}} & {24'b0, shifted_read_data[7:0]})                        | // LBU
		({32{funct3 == 3'b101}} & {16'b0, shifted_read_data[15:0]}); // LHU
	
	always @(posedge clk) begin
		if (rst) begin
			MDR <= 32'b0;
		end 
		else if (is_RDW & Read_data_Valid) begin
			MDR <= Read_data;
		end
	end

	// Write-Back
	assign RF_waddr = rd;
	assign RF_wdata = 
		({32{op_LUI}}   & U_imm)     |
		({32{op_LOAD}}  & Load_data) |
		({32{op_JAL | op_JALR}} & ret_addr_reg) |
		({32{op_AUIPC | op_IMM | op_CALC}} & ALU_reg);
	assign RF_wen = is_WB;

	// Performance Counter
	reg [31:0] cycle_cnt;
	assign cpu_perf_cnt_0 = cycle_cnt;
	always @ (posedge clk)
	begin
		if (rst == 1'b1)
			cycle_cnt <= 32'd0;
		else
			cycle_cnt <= cycle_cnt + 32'd1;
	end

endmodule
