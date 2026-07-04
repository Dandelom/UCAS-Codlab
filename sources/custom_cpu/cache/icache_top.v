`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module icache_top (
	input	      clk,
	input	      rst,
	
	//CPU interface
	/** CPU instruction fetch request to Cache: valid signal */
	input         from_cpu_inst_req_valid,
	/** CPU instruction fetch request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_inst_req_addr,
	/** Acknowledgement from Cache: ready to receive CPU instruction fetch request */
	output        to_cpu_inst_req_ready,
	
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit Instruction value */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive Instruction */
	input	      from_cpu_cache_rsp_ready,

	//Memory interface (32 byte aligned address)
	/** Cache sending memory read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address (32 byte alignment) */
	output [31:0] to_mem_rd_req_addr,
	/** Acknowledgement from memory: ready to receive memory read request */
	input         from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input         from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input         from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready
);

	// Arrays Instanitation
	wire [3:0]   tag_wen;
	wire [3:0]   data_wen; // enable
	wire [23:0]  way_tag_dout [3:0];
	wire [255:0] way_data_dout [3:0]; // data out
	reg  [255:0] refill_line_wdata;
	wire [3:0]   hit_vector;
	wire         Read_Hit;
	wire [2:0]   raddr_sel;

	tag_array way0_tag_inst (
                .clk  (clk),
                .wen  (tag_wen[0]),
                .waddr(req_index),
                .wdata(req_tag),
                .raddr(raddr_sel),
                .rdata(way_tag_dout[0])
        );

	data_array way0_data_inst (
                .clk  (clk),
                .wen  (data_wen[0]),
                .waddr(req_index),
                .wdata(refill_line_wdata),
                .raddr(raddr_sel),
                .rdata(way_data_dout[0])
        );

	tag_array way1_tag_inst (
                .clk  (clk),
                .wen  (tag_wen[1]),
                .waddr(req_index),
                .wdata(req_tag),
                .raddr(raddr_sel),
                .rdata(way_tag_dout[1])
        );

	data_array way1_data_inst (
                .clk  (clk),
                .wen  (data_wen[1]),
                .waddr(req_index),
                .wdata(refill_line_wdata),
                .raddr(raddr_sel),
                .rdata(way_data_dout[1])
        );

	tag_array way2_tag_inst (
                .clk  (clk),
                .wen  (tag_wen[2]),
                .waddr(req_index),
                .wdata(req_tag),
                .raddr(raddr_sel),
                .rdata(way_tag_dout[2])
        );

	data_array way2_data_inst (
                .clk  (clk),
                .wen  (data_wen[2]),
                .waddr(req_index),
                .wdata(refill_line_wdata),
                .raddr(raddr_sel),
                .rdata(way_data_dout[2])
        );

	tag_array way3_tag_inst (
                .clk  (clk),
                .wen  (tag_wen[3]),
                .waddr(req_index),
                .wdata(req_tag),
                .raddr(raddr_sel),
                .rdata(way_tag_dout[3])
        );

	data_array way3_data_inst (
                .clk  (clk),
                .wen  (data_wen[3]),
                .waddr(req_index),
                .wdata(refill_line_wdata),
                .raddr(raddr_sel),
                .rdata(way_data_dout[3])
        );

	// Valid Arrays
	reg [7:0] way0_valid;
	reg [7:0] way1_valid;
	reg [7:0] way2_valid;
	reg [7:0] way3_valid;

	// States Definition
	localparam WAIT     = 8'b00000001;
	localparam TAG_RD   = 8'b00000010;
	localparam EVICT    = 8'b00000100;
	localparam MEM_RD   = 8'b00001000;
	localparam RECV     = 8'b00010000;
	localparam REFILL   = 8'b00100000;
	localparam RESP     = 8'b01000000;
	localparam CACHE_RD = 8'b10000000;

	// States Transference
	reg [7:0] current_state;
	reg [7:0] next_state;

	always @(*) 
	begin
		case(current_state)
			WAIT:
				if(to_cpu_inst_req_ready && from_cpu_inst_req_valid) next_state = TAG_RD;
				else next_state = WAIT;
			TAG_RD:
				if(Read_Hit) next_state = CACHE_RD;
				else next_state = EVICT;
			EVICT:
				next_state = MEM_RD;
			MEM_RD:
				if(to_mem_rd_req_valid && from_mem_rd_req_ready) next_state = RECV;
				else next_state = MEM_RD;
			RECV:
				if(from_mem_rd_rsp_valid && from_mem_rd_rsp_last) next_state = REFILL;
				else next_state = RECV;
			REFILL:
				next_state = RESP;
			RESP:
				if(to_cpu_cache_rsp_valid && from_cpu_cache_rsp_ready) next_state = WAIT;
				else next_state = RESP;
			CACHE_RD:
				next_state = RESP;
			default:
				next_state = WAIT;
		endcase
	end

	always @ (posedge clk) begin
		if(rst == 1'b1)
			current_state <= WAIT;
		else
			current_state <= next_state;
	end

	// Variants Definition
	wire is_wait     = (current_state == WAIT);
	wire is_tag_rd   = (current_state == TAG_RD);
	wire is_evict    = (current_state == EVICT);
	wire is_mem_rd   = (current_state == MEM_RD);
	wire is_recv     = (current_state == RECV);
	wire is_refill   = (current_state == REFILL);
	wire is_resp     = (current_state == RESP);
	wire is_cache_rd = (current_state == CACHE_RD);
	reg  [31:0] req_addr_r;
	reg  [31:0] resp_data_r;
	wire [4:0]  req_offset = req_addr_r[4:0];
	wire [2:0]  req_index  = req_addr_r[7:5];
	wire [23:0] req_tag    = req_addr_r[31:8];
	wire [4:0]  cpu_offset = from_cpu_inst_req_addr[4:0];
	wire [2:0]  cpu_index  = from_cpu_inst_req_addr[7:5];
	wire [23:0] cpu_tag    = from_cpu_inst_req_addr[31:8];

	wire sel_word0 = (req_offset[4:2] == 3'd0);
	wire sel_word1 = (req_offset[4:2] == 3'd1);
	wire sel_word2 = (req_offset[4:2] == 3'd2);
	wire sel_word3 = (req_offset[4:2] == 3'd3);
	wire sel_word4 = (req_offset[4:2] == 3'd4);
	wire sel_word5 = (req_offset[4:2] == 3'd5);
	wire sel_word6 = (req_offset[4:2] == 3'd6);
	wire sel_word7 = (req_offset[4:2] == 3'd7);

	// Wait
	assign to_cpu_inst_req_ready = is_wait | rst;
	assign raddr_sel = (cpu_index & {3{is_wait}}) | (req_index & {3{!is_wait}});
	always @(posedge clk) begin
		if (rst) begin
			req_addr_r <= 32'b0;
		end else if (is_wait && from_cpu_inst_req_valid) begin
			req_addr_r <= from_cpu_inst_req_addr;
		end
	end

	// Tag_Rd
	assign hit_vector[0] = way0_valid[req_index] & (way_tag_dout[0] == req_tag);
	assign hit_vector[1] = way1_valid[req_index] & (way_tag_dout[1] == req_tag);
	assign hit_vector[2] = way2_valid[req_index] & (way_tag_dout[2] == req_tag);
	assign hit_vector[3] = way3_valid[req_index] & (way_tag_dout[3] == req_tag);
	assign Read_Hit = |hit_vector;

	// Cache_Rd & Refill Data Selection
	wire [255:0] hit_line_data = (way_data_dout[0] & {256{hit_vector[0]}})
                           | (way_data_dout[1] & {256{hit_vector[1]}})
                           | (way_data_dout[2] & {256{hit_vector[2]}})
                           | (way_data_dout[3] & {256{hit_vector[3]}});

	wire [255:0] current_line_data = (refill_line_wdata & {256{is_refill}}) 
	                               | (hit_line_data   & {256{!is_refill}});

	wire [31:0] out_slice0 = current_line_data[31:0]    & {32{sel_word0}};
	wire [31:0] out_slice1 = current_line_data[63:32]   & {32{sel_word1}};
	wire [31:0] out_slice2 = current_line_data[95:64]   & {32{sel_word2}};
	wire [31:0] out_slice3 = current_line_data[127:96]  & {32{sel_word3}};
	wire [31:0] out_slice4 = current_line_data[159:128] & {32{sel_word4}};
	wire [31:0] out_slice5 = current_line_data[191:160] & {32{sel_word5}};
	wire [31:0] out_slice6 = current_line_data[223:192] & {32{sel_word6}};
	wire [31:0] out_slice7 = current_line_data[255:224] & {32{sel_word7}};

	wire [31:0] selected_rsp_data = out_slice0 | out_slice1 | out_slice2 | out_slice3 |
	                                out_slice4 | out_slice5 | out_slice6 | out_slice7;

	wire update_resp_data = is_refill | (is_cache_rd & Read_Hit);

	// Evict
	reg [1:0]  rr_counter [7:0];
	wire [1:0] victim_way = rr_counter[req_index];

	wire victim_way_is_0 = (victim_way == 2'd0);
	wire victim_way_is_1 = (victim_way == 2'd1);
	wire victim_way_is_2 = (victim_way == 2'd2);
	wire victim_way_is_3 = (victim_way == 2'd3);
	wire [7:0] index_mask = 8'b1 << req_index;
	
	always @(posedge clk) begin
		if (rst) begin
			way0_valid <= 8'b0;
			way1_valid <= 8'b0;
			way2_valid <= 8'b0;
			way3_valid <= 8'b0;
		end else begin
			way0_valid <= (way0_valid & ~(index_mask & {8{is_evict  & victim_way_is_0}})) 
						|  (index_mask & {8{is_refill & victim_way_is_0}});
			way1_valid <= (way1_valid & ~(index_mask & {8{is_evict  & victim_way_is_1}})) 
						|  (index_mask & {8{is_refill & victim_way_is_1}});
			way2_valid <= (way2_valid & ~(index_mask & {8{is_evict  & victim_way_is_2}})) 
						|  (index_mask & {8{is_refill & victim_way_is_2}});
			way3_valid <= (way3_valid & ~(index_mask & {8{is_evict  & victim_way_is_3}})) 
						|  (index_mask & {8{is_refill & victim_way_is_3}});
		end
	end

	integer idx;
	always @(posedge clk) begin
		if (rst) begin
			for (idx = 0; idx < 8; idx = idx + 1) begin
				rr_counter[idx] <= 2'b0;
			end
		end else if (is_refill) begin
			rr_counter[req_index] <= rr_counter[req_index] + 1'b1;
		end
	end

	// Mem_Rd
	assign to_mem_rd_req_valid = is_mem_rd;
	assign to_mem_rd_req_addr = (req_addr_r & 32'hFFFF_FFE0) & {32{is_mem_rd}};

	// Recv
	assign to_mem_rd_rsp_ready = is_recv | rst;
	wire mem_rd_rsp_handshake = from_mem_rd_rsp_valid && to_mem_rd_rsp_ready;
	reg [2:0] recv_cnt;

	always @(posedge clk) begin
		if (rst) begin
			recv_cnt <= 3'd0;
		end else begin
			recv_cnt <= (recv_cnt + mem_rd_rsp_handshake) & {3{is_recv}};
        	end
	end

	wire [7:0] beat_mask = 8'b1 << recv_cnt;
	wire en_word0 = is_recv & mem_rd_rsp_handshake & beat_mask[0];
	wire en_word1 = is_recv & mem_rd_rsp_handshake & beat_mask[1];
	wire en_word2 = is_recv & mem_rd_rsp_handshake & beat_mask[2];
	wire en_word3 = is_recv & mem_rd_rsp_handshake & beat_mask[3];
	wire en_word4 = is_recv & mem_rd_rsp_handshake & beat_mask[4];
	wire en_word5 = is_recv & mem_rd_rsp_handshake & beat_mask[5];
	wire en_word6 = is_recv & mem_rd_rsp_handshake & beat_mask[6];
	wire en_word7 = is_recv & mem_rd_rsp_handshake & beat_mask[7];
	always @(posedge clk) begin
		if (rst) begin
			refill_line_wdata <= 256'b0;
		end else begin
			refill_line_wdata[31:0]    <= (refill_line_wdata[31:0]    & ~{32{en_word0}}) | (from_mem_rd_rsp_data & {32{en_word0}});
			refill_line_wdata[63:32]   <= (refill_line_wdata[63:32]   & ~{32{en_word1}}) | (from_mem_rd_rsp_data & {32{en_word1}});
			refill_line_wdata[95:64]   <= (refill_line_wdata[95:64]   & ~{32{en_word2}}) | (from_mem_rd_rsp_data & {32{en_word2}});
			refill_line_wdata[127:96]  <= (refill_line_wdata[127:96]  & ~{32{en_word3}}) | (from_mem_rd_rsp_data & {32{en_word3}});
			refill_line_wdata[159:128] <= (refill_line_wdata[159:128] & ~{32{en_word4}}) | (from_mem_rd_rsp_data & {32{en_word4}});
			refill_line_wdata[191:160] <= (refill_line_wdata[191:160] & ~{32{en_word5}}) | (from_mem_rd_rsp_data & {32{en_word5}});
			refill_line_wdata[223:192] <= (refill_line_wdata[223:192] & ~{32{en_word6}}) | (from_mem_rd_rsp_data & {32{en_word6}});
			refill_line_wdata[255:224] <= (refill_line_wdata[255:224] & ~{32{en_word7}}) | (from_mem_rd_rsp_data & {32{en_word7}});
		end
	end

	// Refill
	assign data_wen[0] = is_refill & victim_way_is_0;
	assign data_wen[1] = is_refill & victim_way_is_1;
	assign data_wen[2] = is_refill & victim_way_is_2;
	assign data_wen[3] = is_refill & victim_way_is_3;
	assign tag_wen[0]  = is_refill & victim_way_is_0;
	assign tag_wen[1]  = is_refill & victim_way_is_1;
	assign tag_wen[2]  = is_refill & victim_way_is_2;
	assign tag_wen[3]  = is_refill & victim_way_is_3;
	// operation of Valid_Array is in evict

	always @(posedge clk) begin
		if (rst) begin
			resp_data_r <= 32'b0;
		end else begin
			resp_data_r <= (resp_data_r & ~{32{update_resp_data}})
				| (selected_rsp_data & {32{update_resp_data}});
		end
	end

	// Resp
	assign to_cpu_cache_rsp_valid = is_resp;
	assign to_cpu_cache_rsp_data  = resp_data_r & {32{is_resp}};

endmodule