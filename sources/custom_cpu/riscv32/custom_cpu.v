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
`define WB_SEL_ALU      2'b00
`define WB_SEL_MEM      2'b01
`define WB_SEL_RET_ADDR 2'b10
`define WB_SEL_U_IMM    2'b11

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

	// Pipeline Control
	wire MEM_waiting = ((MemRead || Read_data_Ready) && !Read_data_Valid) || (MemWrite && !Mem_Req_Ready);
	wire load_in_EX  = ID_EX_MemRead  && EX_valid  && (ID_EX_rd  != 5'b0) && ((ID_EX_rd  == raddr1) || (ID_EX_rd  == raddr2));
	wire load_in_MEM = EX_MEM_MemRead && MEM_valid && (EX_MEM_rd != 5'b0) && ((EX_MEM_rd == raddr1) || (EX_MEM_rd == raddr2));
	wire load_use_stall = ID_valid && (load_in_EX || load_in_MEM);

	reg ID_valid;
	reg EX_valid;
	reg MEM_valid;
	reg WB_valid;

	wire IF_readygo  = Inst_Valid && !discard;
	wire ID_readygo  = !load_use_stall;
	wire EX_readygo  = 1'b1;
	wire MEM_readygo = !MEM_waiting;
	wire WB_readygo  = 1'b1;

	wire WB_allowin  = 1'b1;
	wire MEM_allowin = !MEM_valid || MEM_readygo && WB_allowin;
	wire EX_allowin  = !EX_valid  || EX_readygo  && MEM_allowin;
	wire ID_allowin  = !ID_valid  || ID_readygo  && EX_allowin;

	wire IF_ID_advance  = IF_readygo  && ID_allowin;
	wire ID_EX_advance  = ID_valid    && ID_readygo  && EX_allowin;
	wire EX_MEM_advance = EX_valid    && EX_readygo  && MEM_allowin;
	wire MEM_WB_advance = MEM_valid   && MEM_readygo && WB_allowin;

	wire jump_flush = EX_taken;

	// Handshake Signal
	assign Inst_Req_Valid  = !rst && !Inst_Ready;
	assign Inst_Ready      = IW || rst;
	assign Read_data_Ready = RDW || rst;

	reg IW;
	always @(posedge clk) begin
		if (rst || Inst_Valid) IW <= 1'b0;
		else if(Inst_Req_Ready) IW <= 1'b1;
	end

	reg RDW;
	always @(posedge clk) begin
		if (rst || Read_data_Valid) RDW <= 1'b0;
		else if(Mem_Req_Ready && MemRead) RDW <= 1'b1;
	end

	// PC
	reg  [31:0] pc_reg;
	assign PC = pc_reg;
	wire [31:0] next_pc =
		({32{ID_EX_is_jal}}             & (ID_EX_PC + ID_EX_imm))    |   // JAL:  PC + J_imm
		({32{ID_EX_is_jalr}}            & {ALU_Result[31:1], 1'b0})  |   // JALR: ALU result, LSB cleared
		({32{ID_EX_is_branch & Branch}} & (ID_EX_PC + ID_EX_imm))    |   // BRANCH taken: PC + B_imm
		({32{!((ID_EX_is_branch && Branch) || ID_EX_is_jal || ID_EX_is_jalr)}} & (pc_reg + 32'd4)); // default: sequential

	always @(posedge clk) begin
		if(rst) begin
			pc_reg <= 32'h0;
		end else begin
			if(IF_ID_advance || jump_flush) begin
				pc_reg <= next_pc;
			end
		end
	end

	// Instruction Fetch
	reg [31:0] IF_ID_PC;
	reg [31:0] IF_ID_IR;
	reg 	   discard;

	always @(posedge clk) begin
		if (rst) begin
			discard <= 1'b0;
		end else begin
			if (jump_flush && (Inst_Req_Valid || Inst_Ready) && !Inst_Valid) begin
				discard <= 1'b1;
			end else if (Inst_Valid && discard) begin
				discard <= 1'b0;
			end
		end
	end

	always @(posedge clk) begin
		if (rst || jump_flush || discard) begin
			IF_ID_PC    <= 32'h0;
			IF_ID_IR    <= 32'h00000013; // NOP
			ID_valid    <= 1'b0;
		end else if (ID_allowin) begin
			if (IF_ID_advance) begin
				IF_ID_IR <= Instruction;
				IF_ID_PC <= pc_reg;
				ID_valid <= 1'b1;
			end else begin
				IF_ID_IR <= 32'h00000013; // NOP
				IF_ID_PC <= 32'h0;
				ID_valid <= 1'b0;
			end
		end
	end

	// Instruction Decode
	wire [31:0] IR = IF_ID_IR;
	wire [6:0]  opcode  = IR [6:0];
	wire [4:0]  rd      = IR [11:7];
	wire [2:0]  funct3  = IR [14:12];
	wire [6:0]  funct7  = IR [31:25];
	wire [4:0]  shamt   = IR [24:20];
	assign raddr1 = IR [19:15];
	assign raddr2 = IR [24:20];

	wire [31:0] U_imm = {IR [31:12], 12'b0};
	wire [31:0] J_imm = {{11{IR [31]}}, IR [31], IR [19:12], IR [20], IR [30:21], 1'b0};
	wire [31:0] I_imm = {{20{IR [31]}}, IR [31:20]};
	wire [31:0] B_imm = {{19{IR [31]}}, IR [31], IR [7], IR [30:25], IR [11:8], 1'b0};
	wire [31:0] S_imm = {{20{IR [31]}}, IR [31:25], IR [11:7]};

	wire op_LUI    = (opcode == `OPCODE_LUI);
	wire op_AUIPC  = (opcode == `OPCODE_AUIPC);
	wire op_JAL    = (opcode == `OPCODE_JAL);
	wire op_JALR   = (opcode == `OPCODE_JALR);
	wire op_BRANCH = (opcode == `OPCODE_BRANCH);
	wire op_LOAD   = (opcode == `OPCODE_LOAD);
	wire op_STORE  = (opcode == `OPCODE_STORE);
	wire op_IMM    = (opcode == `OPCODE_IMM);
	wire op_CALC   = (opcode == `OPCODE_CALC);
	wire ID_is_mul = op_CALC && (funct3 == 3'b000) && (funct7 == 7'b0000001);

	wire [2:0] ALUop_BRANCH =
		({3{funct3[2:1] == 2'b00}} & `ALUOP_SUB) | // BEQ, BNE
		({3{funct3[2:1] == 2'b10}} & `ALUOP_SLT) | // BLT, BGE
		({3{funct3[2:1] == 2'b11}} & `ALUOP_SLTU)| // BLTU, BGEU
		({3{funct3[2:1] == 2'b01}} & `ALUOP_ADD);
	wire [2:0] ALUop_IMM =
		({3{funct3 == 3'b000}} & `ALUOP_ADD)  |
		({3{funct3 == 3'b010}} & `ALUOP_SLT)  |
		({3{funct3 == 3'b011}} & `ALUOP_SLTU) |
		({3{funct3 == 3'b100}} & `ALUOP_XOR)  |
		({3{funct3 == 3'b110}} & `ALUOP_OR)   |
		({3{funct3 == 3'b111}} & `ALUOP_AND)  |
		({3{funct3 == 3'b001 | funct3 == 3'b101}} & `ALUOP_ADD);
	wire [2:0] ALUop_CALC =
		({3{funct3 == 3'b000 & funct7[5]}} & `ALUOP_SUB) |
		({3{!(funct3 == 3'b000 & funct7[5])}} & ALUop_IMM);

	wire [31:0] ID_imm =
		({32{op_IMM | op_LOAD | op_JALR}} & I_imm) |
		({32{op_STORE}}                   & S_imm) |
		({32{op_LUI | op_AUIPC}}          & U_imm) |
		({32{op_BRANCH}}                  & B_imm) |
		({32{op_JAL}}                     & J_imm);
	wire [4:0] ID_shamt =
		({5{op_CALC}} & rdata2[4:0]) |
		({5{op_IMM}}  & shamt);
	wire [2:0] ID_aluop =
		({3{op_BRANCH}} & ALUop_BRANCH) |
		({3{op_IMM}}    & ALUop_IMM)    |
		({3{op_CALC}}   & ALUop_CALC)   |
		({3{!op_BRANCH & !op_IMM & !op_CALC}} & `ALUOP_ADD);
	wire [1:0] ID_shiftop =
		({2{funct3 == 3'b001}} & `SHIFTOP_LEFT) |
		({2{funct3 == 3'b101 & !funct7[5]}} & `SHIFTOP_LOGIC_RIGHT) |
		({2{funct3 == 3'b101 &  funct7[5]}} & `SHIFTOP_ARITH_RIGHT);

	wire ID_is_shift_imm     = ((op_IMM || op_CALC) && (funct3[1:0] == 2'b01));
	wire ID_alu_src1_sel_pc  = (op_AUIPC || op_JAL);
	wire ID_alu_src1_sel_reg = !(op_AUIPC || op_JAL);
	wire ID_alu_src2_sel_imm = (op_IMM || op_LOAD || op_JALR || op_STORE || op_LUI || op_AUIPC);
	wire ID_alu_src2_sel_reg = (op_CALC || op_BRANCH);
	wire ID_MemRead   = op_LOAD && ID_valid;
	wire ID_MemWrite  = op_STORE && ID_valid;
	wire ID_RegWrite  = !op_BRANCH && !op_STORE && ID_valid;
	wire ID_is_branch = op_BRANCH;
	wire ID_is_jal    = op_JAL;
	wire ID_is_jalr   = op_JALR;
	wire [1:0] ID_WB_sel =
		({2{op_LOAD}}              & `WB_SEL_MEM)      |
		({2{op_JAL | op_JALR}}     & `WB_SEL_RET_ADDR) |
		({2{op_LUI}}               & `WB_SEL_U_IMM)    |
		({2{op_AUIPC | op_IMM | op_CALC}} & `WB_SEL_ALU);
	wire [31:0] ID_ret_addr = IF_ID_PC + 32'd4;

	reg [31:0] ID_EX_rdata1;
	reg [31:0] ID_EX_rdata2;
	reg [31:0] ID_EX_PC;
	reg [31:0] ID_EX_imm;
	reg [4:0]  ID_EX_shamt;
	reg [4:0]  ID_EX_rd;
	reg [2:0]  ID_EX_funct3;
	reg [4:0]  ID_EX_raddr1;
	reg [4:0]  ID_EX_raddr2;
	reg        ID_EX_alu_src1_sel_pc;
	reg        ID_EX_alu_src1_sel_reg;
	reg        ID_EX_alu_src2_sel_imm;
	reg        ID_EX_alu_src2_sel_reg;
	reg [2:0]  ID_EX_aluop;
	reg [1:0]  ID_EX_shiftop;
	reg        ID_EX_is_shift_imm;
	reg        ID_EX_MemRead;
	reg        ID_EX_MemWrite;
	reg        ID_EX_RegWrite;
	reg [1:0]  ID_EX_WB_sel;
	reg [31:0] ID_EX_ret_addr;
	reg        ID_EX_is_branch;
	reg        ID_EX_is_jal;
	reg        ID_EX_is_jalr;
	reg        ID_EX_is_mul;

	always @(posedge clk) begin
		if (rst) begin
			ID_EX_rdata1           <= 32'h0;
			ID_EX_rdata2           <= 32'h0;
			ID_EX_PC               <= 32'h0;
			ID_EX_imm              <= 32'h0;
			ID_EX_shamt            <= 5'h0;
			ID_EX_rd               <= 5'h0;
			ID_EX_funct3           <= 3'b0;
			ID_EX_raddr1           <= 5'h0;
			ID_EX_raddr2           <= 5'h0;
			ID_EX_alu_src1_sel_pc  <= 1'b0;
			ID_EX_alu_src1_sel_reg <= 1'b0;
			ID_EX_alu_src2_sel_imm <= 1'b0;
			ID_EX_alu_src2_sel_reg <= 1'b0;
			ID_EX_aluop            <= 3'b0;
			ID_EX_shiftop          <= 2'b0;
			ID_EX_is_shift_imm     <= 1'b0;
			ID_EX_MemRead          <= 1'b0;
			ID_EX_MemWrite         <= 1'b0;
			ID_EX_RegWrite         <= 1'b0;
			ID_EX_WB_sel           <= 2'b0;
			ID_EX_ret_addr         <= 32'h0;
			ID_EX_is_branch        <= 1'b0;
			ID_EX_is_jal           <= 1'b0;
			ID_EX_is_jalr          <= 1'b0;
			ID_EX_is_mul           <= 1'b0;
		end else if (jump_flush && EX_allowin) begin
			ID_EX_MemRead         <= 1'b0;
			ID_EX_MemWrite        <= 1'b0;
			ID_EX_RegWrite        <= 1'b0;
			ID_EX_is_branch       <= 1'b0;
			ID_EX_is_jal          <= 1'b0;
			ID_EX_is_jalr         <= 1'b0;
			ID_EX_is_mul          <= 1'b0;
		end else if (ID_EX_advance) begin
			ID_EX_rdata1          <= rdata1;
			ID_EX_rdata2          <= rdata2;
			ID_EX_PC              <= IF_ID_PC;
			ID_EX_imm             <= ID_imm;
			ID_EX_shamt           <= ID_shamt;
			ID_EX_rd              <= rd;
			ID_EX_funct3          <= funct3;
			ID_EX_raddr1          <= raddr1;
			ID_EX_raddr2          <= raddr2;
			ID_EX_alu_src1_sel_pc  <= ID_alu_src1_sel_pc;
			ID_EX_alu_src1_sel_reg <= ID_alu_src1_sel_reg;
			ID_EX_alu_src2_sel_imm <= ID_alu_src2_sel_imm;
			ID_EX_alu_src2_sel_reg <= ID_alu_src2_sel_reg;
			ID_EX_aluop            <= ID_aluop;
			ID_EX_shiftop          <= ID_shiftop;
			ID_EX_is_shift_imm     <= ID_is_shift_imm;
			ID_EX_MemRead         <= ID_MemRead;
			ID_EX_MemWrite        <= ID_MemWrite;
			ID_EX_RegWrite        <= ID_RegWrite;
			ID_EX_WB_sel          <= ID_WB_sel;
			ID_EX_ret_addr        <= ID_ret_addr;
			ID_EX_is_branch       <= ID_is_branch;
			ID_EX_is_jal          <= ID_is_jal;
			ID_EX_is_jalr         <= ID_is_jalr;
			ID_EX_is_mul          <= ID_is_mul;
		end else if (!ID_EX_advance && EX_valid) begin
			if (forward_a_EXMEM)      ID_EX_rdata1 <= EX_MEM_ALU_result;
			else if (forward_a_MEMWB) ID_EX_rdata1 <= MEM_WB_fwd_data;
			if (forward_b_EXMEM)      ID_EX_rdata2 <= EX_MEM_ALU_result;
			else if (forward_b_MEMWB) ID_EX_rdata2 <= MEM_WB_fwd_data;
		end
	end

	// EX Valid
	always @(posedge clk) begin
		if (rst) begin
			EX_valid <= 1'b0;
		end else if (EX_allowin) begin
			EX_valid <= ID_valid && ID_readygo && !jump_flush;
		end
	end

	// Execute
	wire [31:0] MEM_WB_fwd_data =
		({32{MEM_WB_WB_sel == `WB_SEL_ALU}}      & MEM_WB_ALU_result) |
		({32{MEM_WB_WB_sel == `WB_SEL_MEM}}      & MEM_WB_Load_data)  |
		({32{MEM_WB_WB_sel == `WB_SEL_RET_ADDR}} & MEM_WB_ret_addr)   |
		({32{MEM_WB_WB_sel == `WB_SEL_U_IMM}}    & MEM_WB_imm); // forwarding

	// Forward detection
	wire forward_a_EXMEM = EX_MEM_RegWrite && MEM_valid && !EX_MEM_MemRead && (EX_MEM_rd != 5'b0) && (EX_MEM_rd == ID_EX_raddr1);
	wire forward_a_MEMWB = MEM_WB_RegWrite && WB_valid && (MEM_WB_rd != 5'b0) && (MEM_WB_rd == ID_EX_raddr1) && !forward_a_EXMEM;
	wire forward_b_EXMEM = EX_MEM_RegWrite && MEM_valid && !EX_MEM_MemRead && (EX_MEM_rd != 5'b0) && (EX_MEM_rd == ID_EX_raddr2);
	wire forward_b_MEMWB = MEM_WB_RegWrite && WB_valid && (MEM_WB_rd != 5'b0) && (MEM_WB_rd == ID_EX_raddr2) && !forward_b_EXMEM;

	wire [31:0] fwd_rdata1 =
		({32{forward_a_EXMEM}}        & EX_MEM_ALU_result) |
		({32{forward_a_MEMWB}}        & MEM_WB_fwd_data)   |
		({32{!(forward_a_EXMEM | forward_a_MEMWB)}} & ID_EX_rdata1);

	wire [31:0] fwd_rdata2 =
		({32{forward_b_EXMEM}}        & EX_MEM_ALU_result) |
		({32{forward_b_MEMWB}}        & MEM_WB_fwd_data)   |
		({32{!(forward_b_EXMEM | forward_b_MEMWB)}} & ID_EX_rdata2);

	assign src1 =
		({32{ID_EX_alu_src1_sel_pc}}  & ID_EX_PC) |
		({32{ID_EX_alu_src1_sel_reg}} & fwd_rdata1);

	assign src2 =
		({32{ID_EX_alu_src2_sel_imm}} & ID_EX_imm) |
		({32{ID_EX_alu_src2_sel_reg}} & fwd_rdata2);

	assign Shift_src1 = fwd_rdata1;
	assign Shift_src2 = ID_EX_shamt;
	assign ALUop      = ID_EX_aluop;
	assign Shiftop    = ID_EX_shiftop;
	wire [31:0] Mul_Result = src1 * src2;

	wire [31:0] EX_result =
		({32{ID_EX_is_mul}}                        & Mul_Result)     |
		({32{ID_EX_is_shift_imm}}                  & Shifter_Result) |
		({32{!ID_EX_is_shift_imm && !ID_EX_is_mul}} & ALU_Result);

	wire Branch = ID_EX_is_branch && (
		((ID_EX_funct3 == 3'b000) && Zero)          | // BEQ
		((ID_EX_funct3 == 3'b001) && !Zero)         | // BNE
		((ID_EX_funct3 == 3'b100) && ALU_Result[0]) | // BLT
		((ID_EX_funct3 == 3'b101) && !ALU_Result[0])| // BGE
		((ID_EX_funct3 == 3'b110) && ALU_Result[0]) | // BLTU
		((ID_EX_funct3 == 3'b111) && !ALU_Result[0])  // BGEU
	);

	wire EX_taken  = EX_valid && (Branch || ID_EX_is_jal || ID_EX_is_jalr);
	wire EX_is_jump = ID_EX_is_jal || ID_EX_is_jalr;

	reg [31:0] EX_MEM_ALU_result;
	reg [31:0] EX_MEM_rdata2;
	reg [31:0] EX_MEM_PC;
	reg [31:0] EX_MEM_imm;
	reg [31:0] EX_MEM_ret_addr;
	reg [4:0]  EX_MEM_rd;
	reg [2:0]  EX_MEM_funct3;
	reg        EX_MEM_MemRead;
	reg        EX_MEM_MemWrite;
	reg        EX_MEM_RegWrite;
	reg [1:0]  EX_MEM_WB_sel;

	always @(posedge clk) begin
		if (rst) begin
			EX_MEM_ALU_result <= 32'h0;
			EX_MEM_rdata2     <= 32'h0;
			EX_MEM_PC         <= 32'h0;
			EX_MEM_imm        <= 32'h0;
			EX_MEM_ret_addr   <= 32'h0;
			EX_MEM_rd         <= 5'h0;
			EX_MEM_funct3     <= 3'b0;
			EX_MEM_MemRead    <= 1'b0;
			EX_MEM_MemWrite   <= 1'b0;
			EX_MEM_RegWrite   <= 1'b0;
			EX_MEM_WB_sel     <= 2'b0;
		end else if (EX_MEM_advance) begin
			EX_MEM_ALU_result <= EX_result;
			EX_MEM_rdata2     <= fwd_rdata2;
			EX_MEM_PC         <= ID_EX_PC;
			EX_MEM_imm        <= ID_EX_imm;
			EX_MEM_ret_addr   <= ID_EX_ret_addr;
			EX_MEM_rd         <= ID_EX_rd;
			EX_MEM_funct3     <= ID_EX_funct3;
			EX_MEM_MemRead    <= ID_EX_MemRead;
			EX_MEM_MemWrite   <= ID_EX_MemWrite;
			EX_MEM_RegWrite   <= ID_EX_RegWrite;
			EX_MEM_WB_sel     <= ID_EX_WB_sel;
		end
	end

	// MEM Valid
	always @(posedge clk) begin
		if (rst) begin
			MEM_valid <= 1'b0;
		end else if (MEM_allowin) begin
			MEM_valid <= EX_valid && EX_readygo;
		end
	end

	// Memory
	reg MemWrite_reg;
	always @(posedge clk) begin
		if (rst) 
			MemWrite_reg <= 1'b0;
		else if (ID_EX_MemWrite && EX_MEM_advance) 
			MemWrite_reg <= 1'b1;
		else if (Mem_Req_Ready) 
			MemWrite_reg <= 1'b0;
	end

	reg MemRead_reg;
	always @(posedge clk) begin
		if (rst) 
			MemRead_reg <= 1'b0;
		else if (ID_EX_MemRead && EX_MEM_advance) 
			MemRead_reg <= 1'b1;
		else if (Mem_Req_Ready) 
			MemRead_reg <= 1'b0;
	end

	assign MemRead  = MemRead_reg;
	assign MemWrite = MemWrite_reg;
	assign Address  = {EX_MEM_ALU_result[31:2], 2'b00};

	wire [31:0] Store_data =
		({32{EX_MEM_funct3 == 3'b000}} & {24'h0,     EX_MEM_rdata2[7:0]})  | // SB
		({32{EX_MEM_funct3 == 3'b001}} & {16'h0,     EX_MEM_rdata2[15:0]}) | // SH
		({32{EX_MEM_funct3 == 3'b010}} & EX_MEM_rdata2);                     // SW
	assign Write_data = Store_data << {EX_MEM_ALU_result[1:0], 3'b000};
	assign Write_strb =
		({4{EX_MEM_funct3 == 3'b000}} & (4'b0001 << EX_MEM_ALU_result[1:0])) |
		({4{EX_MEM_funct3 == 3'b001}} & (4'b0011 << EX_MEM_ALU_result[1:0])) |
		({4{EX_MEM_funct3 == 3'b010}} & 4'b1111);

	wire [31:0] shifted_read_data = Read_data >> {EX_MEM_ALU_result[1:0], 3'b000};
	wire [31:0] Load_data =
		({32{EX_MEM_funct3 == 3'b000}} & {{24{shifted_read_data[7]}},  shifted_read_data[7:0]})  | // LB
		({32{EX_MEM_funct3 == 3'b001}} & {{16{shifted_read_data[15]}}, shifted_read_data[15:0]}) | // LH
		({32{EX_MEM_funct3 == 3'b010}} & shifted_read_data)                                      | // LW
		({32{EX_MEM_funct3 == 3'b100}} & {24'b0, shifted_read_data[7:0]})                        | // LBU
		({32{EX_MEM_funct3 == 3'b101}} & {16'b0, shifted_read_data[15:0]});                        // LHU

	reg [31:0] MEM_WB_ALU_result;
	reg [31:0] MEM_WB_Load_data;
	reg [31:0] MEM_WB_PC;
	reg [31:0] MEM_WB_imm;
	reg [31:0] MEM_WB_ret_addr;
	reg [4:0]  MEM_WB_rd;
	reg        MEM_WB_RegWrite;
	reg [1:0]  MEM_WB_WB_sel;

	always @(posedge clk) begin
		if (rst) begin
			MEM_WB_ALU_result <= 32'h0;
			MEM_WB_Load_data  <= 32'h0;
			MEM_WB_PC         <= 32'h0;
			MEM_WB_imm        <= 32'h0;
			MEM_WB_ret_addr   <= 32'h0;
			MEM_WB_rd         <= 5'h0;
			MEM_WB_RegWrite   <= 1'b0;
			MEM_WB_WB_sel     <= 2'b0;
		end else if (MEM_WB_advance) begin
			MEM_WB_ALU_result <= EX_MEM_ALU_result;
			MEM_WB_Load_data  <= Load_data;
			MEM_WB_PC         <= EX_MEM_PC;
			MEM_WB_imm        <= EX_MEM_imm;
			MEM_WB_ret_addr   <= EX_MEM_ret_addr;
			MEM_WB_rd         <= EX_MEM_rd;
			MEM_WB_RegWrite   <= EX_MEM_RegWrite;
			MEM_WB_WB_sel     <= EX_MEM_WB_sel;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			WB_valid <= 1'b0;
		end else if (MEM_WB_advance) begin
			WB_valid <= MEM_valid && MEM_readygo;
		end else if (WB_allowin) begin
			WB_valid <= MEM_valid && MEM_readygo;
		end
	end

	// Write Back
	assign RF_waddr = MEM_WB_rd;
	assign RF_wdata =
		({32{MEM_WB_WB_sel == `WB_SEL_ALU}}      & MEM_WB_ALU_result) |
		({32{MEM_WB_WB_sel == `WB_SEL_MEM}}      & MEM_WB_Load_data)  |
		({32{MEM_WB_WB_sel == `WB_SEL_RET_ADDR}} & MEM_WB_ret_addr)   |
		({32{MEM_WB_WB_sel == `WB_SEL_U_IMM}}    & MEM_WB_imm);
	assign RF_wen = MEM_WB_RegWrite && WB_valid;

	assign inst_retire = {RF_wen, RF_waddr, RF_wdata, MEM_WB_PC};

	// Performance Counter
	reg [31:0] cycle_cnt;
	assign cpu_perf_cnt_0  = cycle_cnt;
	assign cpu_perf_cnt_1  = 32'b0;
	assign cpu_perf_cnt_2  = 32'b0;
	assign cpu_perf_cnt_3  = 32'b0;
	assign cpu_perf_cnt_4  = 32'b0;
	assign cpu_perf_cnt_5  = 32'b0;
	assign cpu_perf_cnt_6  = 32'b0;
	assign cpu_perf_cnt_7  = 32'b0;
	assign cpu_perf_cnt_8  = 32'b0;
	assign cpu_perf_cnt_9  = 32'b0;
	assign cpu_perf_cnt_10 = 32'b0;
	assign cpu_perf_cnt_11 = 32'b0;
	assign cpu_perf_cnt_12 = 32'b0;
	assign cpu_perf_cnt_13 = 32'b0;
	assign cpu_perf_cnt_14 = 32'b0;
	assign cpu_perf_cnt_15 = 32'b0;

	always @ (posedge clk) begin
		if (rst)
			cycle_cnt <= 32'd0;
		else
			cycle_cnt <= cycle_cnt + 32'd1;
	end

endmodule