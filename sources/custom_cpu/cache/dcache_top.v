`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module dcache_top (
	input	      clk,
	input	      rst,

	//CPU interface
	/** CPU memory/IO access request to Cache: valid signal */
	input         from_cpu_mem_req_valid,
	/** CPU memory/IO access request to Cache: 0 for read; 1 for write (when req_valid is high) */
	input         from_cpu_mem_req,
	/** CPU memory/IO access request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_mem_req_addr,
	/** CPU memory/IO access request to Cache: 32-bit write data */
	input  [31:0] from_cpu_mem_req_wdata,
	/** CPU memory/IO access request to Cache: 4-bit write strobe */
	input  [ 3:0] from_cpu_mem_req_wstrb,
	/** Acknowledgement from Cache: ready to receive CPU memory access request */
	output        to_cpu_mem_req_ready,

	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit read data */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive read data */
	input         from_cpu_cache_rsp_ready,

	//Memory/IO read interface
	/** Cache sending memory/IO read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address
	  * 4 byte alignment for I/O read
	  * 32 byte alignment for cache read miss */
	output [31:0] to_mem_rd_req_addr,
        /** Cache sending memory read request: burst length
	  * 0 for I/O read (read only one data beat)
	  * 7 for cache read miss (read eight data beats) */
	output [ 7:0] to_mem_rd_req_len,
        /** Acknowledgement from memory: ready to receive memory read request */
	input	      from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input	      from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input	      from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready,

	//Memory/IO write interface
	/** Cache sending memory/IO write request: valid signal */
	output        to_mem_wr_req_valid,
	/** Cache sending memory write request: address
	  * 4 byte alignment for I/O write
	  * 4 byte alignment for cache write miss
          * 32 byte alignment for cache write-back */
	output [31:0] to_mem_wr_req_addr,
        /** Cache sending memory write request: burst length
          * 0 for I/O write (write only one data beat)
          * 0 for cache write miss (write only one data beat)
          * 7 for cache write-back (write eight data beats) */
	output [ 7:0] to_mem_wr_req_len,
        /** Acknowledgement from memory: ready to receive memory write request */
	input         from_mem_wr_req_ready,

	/** Cache sending memory/IO write data: valid signal for current data beat */
	output        to_mem_wr_data_valid,
	/** Cache sending memory/IO write data: current data beat */
	output [31:0] to_mem_wr_data,
	/** Cache sending memory/IO write data: write strobe
	  * 4'b1111 for cache write-back
	  * other values for I/O write and cache write miss according to the original CPU request*/
	output [ 3:0] to_mem_wr_data_strb,
	/** Cache sending memory/IO write data: if current data beat is the last in this burst data transmission */
	output        to_mem_wr_data_last,
	/** Acknowledgement from memory/IO: ready to receive current data beat */
	input	      from_mem_wr_data_ready
);

	// Arrays Instanitation
	wire [3:0]   tag_wen;
	wire [3:0]   data_wen;
	wire [23:0]  way_tag_dout [3:0];
	wire [255:0] way_data_dout [3:0];
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
	                .wdata(cache_wdata),
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
	                .wdata(cache_wdata),
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
	                .wdata(cache_wdata),
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
	                .wdata(cache_wdata),
	                .raddr(raddr_sel),
	                .rdata(way_data_dout[3])
	        );

	// Valid Arrays
	reg [7:0] way0_valid;
	reg [7:0] way1_valid;
	reg [7:0] way2_valid;
	reg [7:0] way3_valid;

	// Dirty Arrays
	reg [7:0] way0_dirty;
	reg [7:0] way1_dirty;
	reg [7:0] way2_dirty;
	reg [7:0] way3_dirty;

	// States Definition
	localparam WAIT          = 14'b00000000000001;
	localparam TAG_RD        = 14'b00000000000010;
	localparam CACHE_RD      = 14'b00000000000100;
	localparam WRITE_HIT     = 14'b00000000001000;
	localparam EVICT_WB_REQ  = 14'b00000000010000;
	localparam EVICT_WB_DATA = 14'b00000000100000;
	localparam MEM_RD        = 14'b00000001000000;
	localparam RECV          = 14'b00000010000000;
	localparam REFILL        = 14'b00000100000000;
	localparam RESP          = 14'b00001000000000;
	localparam BYP_RD_REQ    = 14'b00010000000000;
	localparam BYP_RD_RECV   = 14'b00100000000000;
	localparam BYP_WR_REQ    = 14'b01000000000000;
	localparam BYP_WR_DATA   = 14'b10000000000000;

	// States Transference
	reg [13:0] current_state;
	reg [13:0] next_state;

	always @(*) begin
		case (current_state)
			WAIT: begin
				if (to_cpu_mem_req_ready && from_cpu_mem_req_valid) begin
					if (bypass_comb) begin
						if (from_cpu_mem_req) begin
							next_state = BYP_WR_REQ;
						end else begin
							next_state = BYP_RD_REQ;
						end
					end else begin
						next_state = TAG_RD;
					end
				end else begin
					next_state = WAIT;
				end
			end
			TAG_RD: begin
				if (Read_Hit && !req_is_write_r) begin
					next_state = CACHE_RD;
				end else if (Read_Hit && req_is_write_r) begin
					next_state = WRITE_HIT;
				end else if (!Read_Hit && victim_dirty) begin
					next_state = EVICT_WB_REQ;
				end else begin
					next_state = MEM_RD;
				end
			end
			CACHE_RD: begin
				next_state = RESP;
			end
			WRITE_HIT: begin
				next_state = WAIT;
			end
			EVICT_WB_REQ: begin
				if (to_mem_wr_req_valid && from_mem_wr_req_ready) begin
					next_state = EVICT_WB_DATA;
				end else begin
					next_state = EVICT_WB_REQ;
				end
			end
			EVICT_WB_DATA: begin
				if (to_mem_wr_data_valid && from_mem_wr_data_ready && to_mem_wr_data_last) begin
					next_state = MEM_RD;
				end else begin
					next_state = EVICT_WB_DATA;
				end
			end
			MEM_RD: begin
				if (to_mem_rd_req_valid && from_mem_rd_req_ready) begin
					next_state = RECV;
				end else begin
					next_state = MEM_RD;
				end
			end
			RECV: begin
				if (from_mem_rd_rsp_valid && to_mem_rd_rsp_ready && from_mem_rd_rsp_last) begin
					next_state = REFILL;
				end else begin
					next_state = RECV;
				end
			end
			REFILL: begin
				if (req_is_write_r) begin
					next_state = WAIT;
				end else begin
					next_state = RESP;
				end
			end
			RESP: begin
				if (to_cpu_cache_rsp_valid && from_cpu_cache_rsp_ready) begin
					next_state = WAIT;
				end else begin
					next_state = RESP;
				end
			end
			BYP_RD_REQ: begin
				if (to_mem_rd_req_valid && from_mem_rd_req_ready) begin
					next_state = BYP_RD_RECV;
				end else begin
					next_state = BYP_RD_REQ;
				end
			end
			BYP_RD_RECV: begin
				if (from_mem_rd_rsp_valid && to_mem_rd_rsp_ready) begin
					next_state = RESP;
				end else begin
					next_state = BYP_RD_RECV;
				end
			end
			BYP_WR_REQ: begin
				if (to_mem_wr_req_valid && from_mem_wr_req_ready) begin
					next_state = BYP_WR_DATA;
				end else begin
					next_state = BYP_WR_REQ;
				end
			end
			BYP_WR_DATA: begin
				if (to_mem_wr_data_valid && from_mem_wr_data_ready && to_mem_wr_data_last) begin
					next_state = WAIT;
				end else begin
					next_state = BYP_WR_DATA;
				end
			end
			default: begin
				next_state = WAIT;
			end
		endcase
	end

	always @(posedge clk) begin
		if (rst == 1'b1)
			current_state <= WAIT;
		else
			current_state <= next_state;
	end

	// Variants Definition
	wire is_wait          = (current_state == WAIT);
	wire is_tag_rd        = (current_state == TAG_RD);
	wire is_cache_rd      = (current_state == CACHE_RD);
	wire is_write_hit     = (current_state == WRITE_HIT);
	wire is_evict_wb_req  = (current_state == EVICT_WB_REQ);
	wire is_evict_wb_data = (current_state == EVICT_WB_DATA);
	wire is_mem_rd        = (current_state == MEM_RD);
	wire is_recv          = (current_state == RECV);
	wire is_refill        = (current_state == REFILL);
	wire is_resp          = (current_state == RESP);
	wire is_byp_rd_req    = (current_state == BYP_RD_REQ);
	wire is_byp_rd_recv   = (current_state == BYP_RD_RECV);
	wire is_byp_wr_req    = (current_state == BYP_WR_REQ);
	wire is_byp_wr_data   = (current_state == BYP_WR_DATA);

	reg  [31:0] req_addr_r;
	reg         req_is_write_r;
	reg  [31:0] req_wdata_r;
	reg  [ 3:0] req_wstrb_r;
	reg  [31:0] resp_data_r;
	wire [4:0]  req_offset = req_addr_r[4:0];
	wire [2:0]  req_index  = req_addr_r[7:5];
	wire [23:0] req_tag    = req_addr_r[31:8];
	wire [4:0]  cpu_offset = from_cpu_mem_req_addr[4:0];
	wire [2:0]  cpu_index  = from_cpu_mem_req_addr[7:5];
	wire [23:0] cpu_tag    = from_cpu_mem_req_addr[31:8];

	wire bypass_comb = (from_cpu_mem_req_addr < 32'h20)
	                 | (from_cpu_mem_req_addr >= 32'h40000000);

	wire sel_word0 = (req_offset[4:2] == 3'd0);
	wire sel_word1 = (req_offset[4:2] == 3'd1);
	wire sel_word2 = (req_offset[4:2] == 3'd2);
	wire sel_word3 = (req_offset[4:2] == 3'd3);
	wire sel_word4 = (req_offset[4:2] == 3'd4);
	wire sel_word5 = (req_offset[4:2] == 3'd5);
	wire sel_word6 = (req_offset[4:2] == 3'd6);
	wire sel_word7 = (req_offset[4:2] == 3'd7);

	// Hit way register
	reg [1:0] hit_way_r;

	// Victim way register
	reg [1:0] victim_way_r;

	// Victim tag register (for writeback address)
	reg [23:0] victim_tag_r;

	// Wait
	assign to_cpu_mem_req_ready = is_wait;
	assign raddr_sel = (cpu_index & {3{is_wait}}) | (req_index & {3{!is_wait}});

	always @(posedge clk) begin
		if (rst) begin
			req_addr_r     <= 32'b0;
			req_is_write_r <= 1'b0;
			req_wdata_r    <= 32'b0;
			req_wstrb_r    <= 4'b0;
		end else if (is_wait && from_cpu_mem_req_valid) begin
			req_addr_r     <= from_cpu_mem_req_addr;
			req_is_write_r <= from_cpu_mem_req;
			req_wdata_r    <= from_cpu_mem_req_wdata;
			req_wstrb_r    <= from_cpu_mem_req_wstrb;
		end
	end

	// Tag_Rd
	assign hit_vector[0] = way0_valid[req_index] & (way_tag_dout[0] == req_tag);
	assign hit_vector[1] = way1_valid[req_index] & (way_tag_dout[1] == req_tag);
	assign hit_vector[2] = way2_valid[req_index] & (way_tag_dout[2] == req_tag);
	assign hit_vector[3] = way3_valid[req_index] & (way_tag_dout[3] == req_tag);
	assign Read_Hit = |hit_vector;

	// Hit way encoding (priority: way0 > way1 > way2 > way3)
	wire hit_way_is_0 = hit_vector[0];
	wire hit_way_is_1 = hit_vector[1] & !hit_vector[0];
	wire hit_way_is_2 = hit_vector[2] & !(|hit_vector[1:0]);
	wire hit_way_is_3 = hit_vector[3] & !(|hit_vector[2:0]);
	wire [1:0] hit_way_comb = ({2{hit_way_is_1}} & 2'd1)
	                        | ({2{hit_way_is_2}} & 2'd2)
	                        | ({2{hit_way_is_3}} & 2'd3);

	always @(posedge clk) begin
		if (rst) begin
			hit_way_r <= 2'd0;
		end else if (is_tag_rd) begin
			hit_way_r <= hit_way_comb;
		end
	end

	// Cache_Rd & Refill Data Selection
	wire [255:0] hit_line_data = (way_data_dout[0] & {256{hit_vector[0]}})
	                           | (way_data_dout[1] & {256{hit_vector[1]}})
	                           | (way_data_dout[2] & {256{hit_vector[2]}})
	                           | (way_data_dout[3] & {256{hit_vector[3]}});

	wire [255:0] current_line_data = (refill_line_wdata & {256{is_refill || is_recv}})
	                               | (hit_line_data     & {256{!(is_refill || is_recv)}});

	wire [31:0] out_slice0 = current_line_data[31:0]    & {32{sel_word0}};
	wire [31:0] out_slice1 = current_line_data[63:32]   & {32{sel_word1}};
	wire [31:0] out_slice2 = current_line_data[95:64]   & {32{sel_word2}};
	wire [31:0] out_slice3 = current_line_data[127:96]  & {32{sel_word3}};
	wire [31:0] out_slice4 = current_line_data[159:128] & {32{sel_word4}};
	wire [31:0] out_slice5 = current_line_data[191:160] & {32{sel_word5}};
	wire [31:0] out_slice6 = current_line_data[223:192] & {32{sel_word6}};
	wire [31:0] out_slice7 = current_line_data[255:224] & {32{sel_word7}};

	wire [31:0] selected_rsp_data = out_slice0 | out_slice1 | out_slice2 | out_slice3
	                              | out_slice4 | out_slice5 | out_slice6 | out_slice7;

	wire update_resp_data = is_refill | (is_cache_rd & Read_Hit);

	// Evict
	reg [1:0] rr_counter [7:0];
	wire [1:0] victim_way = rr_counter[req_index];

	wire victim_way_is_0 = (victim_way == 2'd0);
	wire victim_way_is_1 = (victim_way == 2'd1);
	wire victim_way_is_2 = (victim_way == 2'd2);
	wire victim_way_is_3 = (victim_way == 2'd3);
	wire [7:0] index_mask = 8'b1 << req_index;

	// Victim dirty detection
	wire victim_dirty_0 = way0_dirty[req_index];
	wire victim_dirty_1 = way1_dirty[req_index];
	wire victim_dirty_2 = way2_dirty[req_index];
	wire victim_dirty_3 = way3_dirty[req_index];
	wire victim_dirty = (victim_dirty_0 & victim_way_is_0)
	                  | (victim_dirty_1 & victim_way_is_1)
	                  | (victim_dirty_2 & victim_way_is_2)
	                  | (victim_dirty_3 & victim_way_is_3);

	wire do_evict = is_tag_rd && !Read_Hit;

	always @(posedge clk) begin
		if (rst) begin
			victim_way_r   <= 2'd0;
			victim_tag_r   <= 24'b0;
		end else if (do_evict) begin
			victim_way_r   <= victim_way;
			victim_tag_r   <= ({24{victim_way_is_0}} & way_tag_dout[0])
			                | ({24{victim_way_is_1}} & way_tag_dout[1])
			                | ({24{victim_way_is_2}} & way_tag_dout[2])
			                | ({24{victim_way_is_3}} & way_tag_dout[3]);
		end
	end

	// Valid & Dirty update
	always @(posedge clk) begin
		if (rst) begin
			way0_valid <= 8'b0;
			way1_valid <= 8'b0;
			way2_valid <= 8'b0;
			way3_valid <= 8'b0;
			way0_dirty <= 8'b0;
			way1_dirty <= 8'b0;
			way2_dirty <= 8'b0;
			way3_dirty <= 8'b0;
		end else begin
			way0_valid <= (way0_valid & ~(index_mask & {8{do_evict  & victim_way_is_0}}))
			            |  (index_mask & {8{is_refill & (victim_way_r == 2'd0)}});
			way1_valid <= (way1_valid & ~(index_mask & {8{do_evict  & victim_way_is_1}}))
			            |  (index_mask & {8{is_refill & (victim_way_r == 2'd1)}});
			way2_valid <= (way2_valid & ~(index_mask & {8{do_evict  & victim_way_is_2}}))
			            |  (index_mask & {8{is_refill & (victim_way_r == 2'd2)}});
			way3_valid <= (way3_valid & ~(index_mask & {8{do_evict  & victim_way_is_3}}))
			            |  (index_mask & {8{is_refill & (victim_way_r == 2'd3)}});

			way0_dirty <= (way0_dirty | (index_mask & {8{is_write_hit && (hit_way_r == 2'd0)}}))
			            & ~(index_mask & {8{is_refill && (victim_way_r == 2'd0) && !req_is_write_r}})
			            |  (index_mask & {8{is_refill && (victim_way_r == 2'd0) && req_is_write_r}});
			way1_dirty <= (way1_dirty | (index_mask & {8{is_write_hit && (hit_way_r == 2'd1)}}))
			            & ~(index_mask & {8{is_refill && (victim_way_r == 2'd1) && !req_is_write_r}})
			            |  (index_mask & {8{is_refill && (victim_way_r == 2'd1) && req_is_write_r}});
			way2_dirty <= (way2_dirty | (index_mask & {8{is_write_hit && (hit_way_r == 2'd2)}}))
			            & ~(index_mask & {8{is_refill && (victim_way_r == 2'd2) && !req_is_write_r}})
			            |  (index_mask & {8{is_refill && (victim_way_r == 2'd2) && req_is_write_r}});
			way3_dirty <= (way3_dirty | (index_mask & {8{is_write_hit && (hit_way_r == 2'd3)}}))
			            & ~(index_mask & {8{is_refill && (victim_way_r == 2'd3) && !req_is_write_r}})
			            |  (index_mask & {8{is_refill && (victim_way_r == 2'd3) && req_is_write_r}});
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

	// Write_Hit: read-modify-write — mask target word in hit_line_data with CPU wdata per wstrb
	wire wh_word0  = (req_offset[4:2] == 3'd0);
	wire wh_word1  = (req_offset[4:2] == 3'd1);
	wire wh_word2  = (req_offset[4:2] == 3'd2);
	wire wh_word3  = (req_offset[4:2] == 3'd3);
	wire wh_word4  = (req_offset[4:2] == 3'd4);
	wire wh_word5  = (req_offset[4:2] == 3'd5);
	wire wh_word6  = (req_offset[4:2] == 3'd6);
	wire wh_word7  = (req_offset[4:2] == 3'd7);

	wire [7:0] wh_byte0 = {8{req_wstrb_r[0]}};
	wire [7:0] wh_byte1 = {8{req_wstrb_r[1]}};
	wire [7:0] wh_byte2 = {8{req_wstrb_r[2]}};
	wire [7:0] wh_byte3 = {8{req_wstrb_r[3]}};
	wire [31:0] wh_mask_32 = {wh_byte3, wh_byte2, wh_byte1, wh_byte0};
	wire [31:0] wh_wdata = req_wdata_r & wh_mask_32;
	wire [31:0] wh_mask = ~wh_mask_32;

	wire [255:0] write_hit_data = {
		((wh_wdata | (hit_line_data[255:224] & wh_mask)) & {32{wh_word7}}) | (hit_line_data[255:224] & {32{!wh_word7}}),
		((wh_wdata | (hit_line_data[223:192] & wh_mask)) & {32{wh_word6}}) | (hit_line_data[223:192] & {32{!wh_word6}}),
		((wh_wdata | (hit_line_data[191:160] & wh_mask)) & {32{wh_word5}}) | (hit_line_data[191:160] & {32{!wh_word5}}),
		((wh_wdata | (hit_line_data[159:128] & wh_mask)) & {32{wh_word4}}) | (hit_line_data[159:128] & {32{!wh_word4}}),
		((wh_wdata | (hit_line_data[127:96]  & wh_mask)) & {32{wh_word3}}) | (hit_line_data[127:96]  & {32{!wh_word3}}),
		((wh_wdata | (hit_line_data[95:64]   & wh_mask)) & {32{wh_word2}}) | (hit_line_data[95:64]   & {32{!wh_word2}}),
		((wh_wdata | (hit_line_data[63:32]   & wh_mask)) & {32{wh_word1}}) | (hit_line_data[63:32]   & {32{!wh_word1}}),
		((wh_wdata | (hit_line_data[31:0]    & wh_mask)) & {32{wh_word0}}) | (hit_line_data[31:0]    & {32{!wh_word0}})
	};

	// Refill merge: for write-miss, merge CPU wdata into refill line same way
	wire [255:0] refill_merged = {
		((wh_wdata | (refill_line_wdata[255:224] & wh_mask)) & {32{wh_word7}}) | (refill_line_wdata[255:224] & {32{!wh_word7}}),
		((wh_wdata | (refill_line_wdata[223:192] & wh_mask)) & {32{wh_word6}}) | (refill_line_wdata[223:192] & {32{!wh_word6}}),
		((wh_wdata | (refill_line_wdata[191:160] & wh_mask)) & {32{wh_word5}}) | (refill_line_wdata[191:160] & {32{!wh_word5}}),
		((wh_wdata | (refill_line_wdata[159:128] & wh_mask)) & {32{wh_word4}}) | (refill_line_wdata[159:128] & {32{!wh_word4}}),
		((wh_wdata | (refill_line_wdata[127:96]  & wh_mask)) & {32{wh_word3}}) | (refill_line_wdata[127:96]  & {32{!wh_word3}}),
		((wh_wdata | (refill_line_wdata[95:64]   & wh_mask)) & {32{wh_word2}}) | (refill_line_wdata[95:64]   & {32{!wh_word2}}),
		((wh_wdata | (refill_line_wdata[63:32]   & wh_mask)) & {32{wh_word1}}) | (refill_line_wdata[63:32]   & {32{!wh_word1}}),
		((wh_wdata | (refill_line_wdata[31:0]    & wh_mask)) & {32{wh_word0}}) | (refill_line_wdata[31:0]    & {32{!wh_word0}})
	};

	// Cache write data mux
	wire [255:0] cache_wdata = (write_hit_data                      & {256{is_write_hit}})
	                         | (refill_merged                       & {256{is_refill && req_is_write_r}})
	                         | (refill_line_wdata                   & {256{is_refill && !req_is_write_r}});

	// Mem_Rd
	assign to_mem_rd_req_valid = is_mem_rd | is_byp_rd_req;
	assign to_mem_rd_req_addr = ({req_addr_r[31:5], 5'b0} & {32{is_mem_rd}})
	                          | ({req_addr_r[31:2], 2'b0} & {32{is_byp_rd_req}});
	assign to_mem_rd_req_len = (8'd7 & {8{is_mem_rd}})
	                         | (8'd0 & {8{is_byp_rd_req}});

	// Recv
	assign to_mem_rd_rsp_ready = is_recv | is_byp_rd_recv;
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
	assign data_wen[0] = (is_refill && (victim_way_r == 2'd0)) | (is_write_hit && (hit_way_r == 2'd0));
	assign data_wen[1] = (is_refill && (victim_way_r == 2'd1)) | (is_write_hit && (hit_way_r == 2'd1));
	assign data_wen[2] = (is_refill && (victim_way_r == 2'd2)) | (is_write_hit && (hit_way_r == 2'd2));
	assign data_wen[3] = (is_refill && (victim_way_r == 2'd3)) | (is_write_hit && (hit_way_r == 2'd3));
	assign tag_wen[0]  = is_refill & (victim_way_r == 2'd0);
	assign tag_wen[1]  = is_refill & (victim_way_r == 2'd1);
	assign tag_wen[2]  = is_refill & (victim_way_r == 2'd2);
	assign tag_wen[3]  = is_refill & (victim_way_r == 2'd3);

	always @(posedge clk) begin
		if (rst) begin
			resp_data_r <= 32'b0;
		end else if (update_resp_data) begin
			resp_data_r <= selected_rsp_data;
		end else if (is_byp_rd_recv && from_mem_rd_rsp_valid && to_mem_rd_rsp_ready) begin
			resp_data_r <= from_mem_rd_rsp_data;
		end
	end

	// Mem Write Request
	assign to_mem_wr_req_valid = is_evict_wb_req | is_byp_wr_req;
	assign to_mem_wr_req_addr = ({victim_tag_r, req_index, 5'b0} & {32{is_evict_wb_req}})
	                          | ({req_addr_r[31:2], 2'b0}         & {32{is_byp_wr_req}});
	assign to_mem_wr_req_len = (8'd7 & {8{is_evict_wb_req}})
	                         | (8'd0 & {8{is_byp_wr_req}});

	// Mem Write Data
	assign to_mem_wr_data_valid = is_evict_wb_data | is_byp_wr_data;

	wire [255:0] victim_data_line = (way_data_dout[0] & {256{victim_way_r == 2'd0}})
	                              | (way_data_dout[1] & {256{victim_way_r == 2'd1}})
	                              | (way_data_dout[2] & {256{victim_way_r == 2'd2}})
	                              | (way_data_dout[3] & {256{victim_way_r == 2'd3}});

	reg [2:0] wb_beat_cnt;
	wire wb_beat_handshake = is_evict_wb_data && to_mem_wr_data_valid && from_mem_wr_data_ready;

	always @(posedge clk) begin
		if (rst) begin
			wb_beat_cnt <= 3'd0;
		end else begin
			wb_beat_cnt <= (wb_beat_cnt + wb_beat_handshake) & {3{is_evict_wb_data}};
		end
	end

	// Writeback beat data selection
	reg [31:0] wb_beat_data;
	always @(*) begin
		case (wb_beat_cnt)
			3'd0: wb_beat_data = victim_data_line[31:0];
			3'd1: wb_beat_data = victim_data_line[63:32];
			3'd2: wb_beat_data = victim_data_line[95:64];
			3'd3: wb_beat_data = victim_data_line[127:96];
			3'd4: wb_beat_data = victim_data_line[159:128];
			3'd5: wb_beat_data = victim_data_line[191:160];
			3'd6: wb_beat_data = victim_data_line[223:192];
			3'd7: wb_beat_data = victim_data_line[255:224];
			default: wb_beat_data = 32'b0;
		endcase
	end

	assign to_mem_wr_data = (wb_beat_data & {32{is_evict_wb_data}})
	                      | (req_wdata_r  & {32{is_byp_wr_data}});

	assign to_mem_wr_data_strb = (4'b1111       & {4{is_evict_wb_data}})
	                           | (req_wstrb_r    & {4{is_byp_wr_data}});

	assign to_mem_wr_data_last = (is_evict_wb_data && (wb_beat_cnt == 3'd7))
	                           | is_byp_wr_data;

	// Resp
	assign to_cpu_cache_rsp_valid = is_resp;
	assign to_cpu_cache_rsp_data  = resp_data_r & {32{is_resp}};

endmodule