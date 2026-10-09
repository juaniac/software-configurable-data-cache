module data_cache (
  input  wire          i_clk,
  input  wire          i_rst_n,

  // ahb5 interface
  input  wire [31:0]   i_ahb5_addr,    
  input  wire          i_ahb5_we,
  input  wire [1:0]    i_ahb5_trans,    
  input  wire [2:0]    i_ahb5_size,
  input  wire [31:0]   i_ahb5_wdata,
  output reg  [31:0]   o_ahb5_rdata,
  output reg           o_ahb5_ready,
  output reg           o_ahb5_resp,

  // wishbone interface
  output reg           o_wb_cyc,
  output reg           o_wb_stb,
  output reg           o_wb_we,
  output reg  [1:0]    o_wb_bte,
  output reg  [2:0]    o_wb_cti,
  output reg  [3:0]    o_wb_sel,
  output reg  [31:0]   o_wb_addr,
  output reg  [31:0]   o_wb_wdata,
  input  wire [31:0]   i_wb_rdata,
  input  wire          i_wb_ack,
  input  wire          i_wb_err
);

localparam PARAM_NB_WAYS = 1; // 0 or 1 or 2 or 4
localparam PARAM_SIZE = 8192; // 8192 or 4096 or 2048 or 1024
localparam PARAM_WORD_PER_LINE = 4; // 4 or 8 or 16 or 32

localparam WB_BTE_LINEAR_BURST = 2'b00;

localparam WB_CTI_CLASSIC_CYCLE   = 3'b000;
localparam WB_CTI_INC_BURST_CYCLE = 3'b010;
localparam WB_CTI_END_BURST_CYCLE = 3'b111;

reg [2:0] state;
localparam STATE_ADDR           = 4'b0000;
localparam STATE_CACHE          = 4'b0001;
localparam STATE_LOOKUP         = 4'b0010;
localparam STATE_REPL_POLICY    = 4'b0011;
localparam STATE_MEM_WRITE_INIT = 4'b0100;
localparam STATE_MEM_WRITE      = 4'b0101;
localparam STATE_MEM_WAIT       = 4'b0110;
localparam STATE_MEM_READ       = 4'b0111;
localparam STATE_UPDATE_META    = 4'b1000;
localparam STATE_REDO_ADDR      = 4'b1001;
localparam STATE_MEM_ERR        = 4'b1010;

reg hit, miss_dirty, done_mem_write, done_mem_read; 
always @(posedge i_clk) begin
  if(~i_rst_n) begin
    state <= STATE_ADDR;
  end else begin
    case (state)
      STATE_ADDR: 
        state <= (i_ahb5_trans[1]) ? STATE_CACHE :
                                     STATE_ADDR;
      STATE_CACHE:
        state <= (hit & ~i_ahb5_trans[1]) ? STATE_ADDR :
                 (hit & i_ahb5_trans[1])  ? STATE_CACHE :
                                            STATE_LOOKUP;
      STATE_LOOKUP: 
        state <= (miss_dirty) ? STATE_MEM_WRITE_INIT :
                                STATE_MEM_READ; 
      STATE_MEM_WRITE_INIT:
        state <= STATE_MEM_WRITE;
      STATE_MEM_WRITE:
        state <= (i_wb_err)       ? STATE_MEM_ERR : 
                 (done_mem_write) ? STATE_MEM_WAIT :
                                    STATE_MEM_WRITE;
      STATE_MEM_ERR :
        state <= STATE_ADDR;
      STATE_MEM_WAIT:
        state <= STATE_MEM_READ;
      STATE_MEM_READ:
        state <= (i_wb_err)      ? STATE_MEM_ERR : 
                 (done_mem_read) ? STATE_UPDATE_META :
                                   STATE_MEM_READ;
      STATE_UPDATE_META:
        state <= STATE_REDO_ADDR;
      STATE_REDO_ADDR:
        state <= STATE_CACHE;
    endcase
  end
end

reg         meta_update_we   [3:0];
reg  [8:0]  meta_update_addr [3:0];
reg  [8:0]  meta_lookup_addr [3:0];
reg  [31:0] meta_update_in   [3:0];
wire [31:0] meta_update_out  [3:0];
wire [31:0] meta_lookup_out  [3:0];

reg         data_update_we   [3:0];
reg  [8:0]  data_update_addr [3:0];
reg  [8:0]  data_lookup_addr [3:0];
reg  [31:0] data_update_in   [3:0];
wire [31:0] data_update_out  [3:0];
wire [31:0] data_lookup_out  [3:0];

genvar i;
generate
  for (i = 0; i < 4; i=i+1) begin
    sdp_ram metadata_memory (
      .clkA(i_clk), 
      .clkB(i_clk), 
      .we(meta_update_we[i]),
      .addrA(meta_update_addr[i]), 
      .addrB(meta_lookup_addr[i]),
      .dataIn(meta_update_in[i]),
      .dataOutA(meta_update_out[i]), 
      .dataOutB(meta_lookup_out[i])
    );
    sdp_ram data_memory (
      .clkA(i_clk), 
      .clkB(i_clk), 
      .we(data_update_we[i]),
      .addrA(data_update_addr[i]), 
      .addrB(data_lookup_addr[i]),
      .dataIn(data_update_in[i]),
      .dataOutA(data_update_out[i]), 
      .dataOutB(data_lookup_out[i])
    );
  end
endgenerate

wire [31:0] tag_mask, line_mask, word_mask, dirty_mask, valid_mask;
assign tag_mask = {{19{1'b1}}, {9{1'b0}}, {4{1'b0}}};
assign line_mask = {{19{1'b0}}, {9{1'b1}}, {4{1'b0}}};
assign word_mask = {{19{1'b0}}, {9{1'b0}}, {2{1'b1}}, {2{1'b0}}};
assign dirty_mask = 32'b10;  
assign valid_mask = 32'b1;

reg [31:0] req_addr;
reg [2:0]  req_size;
reg        req_we;
always @(posedge i_clk)begin
  if(~i_rst_n)begin
    req_addr <= 32'b0;
    req_size <= 3'b0;
    req_we   <= 1'b0;
  end else if(
    state == STATE_ADDR |
    (state == STATE_CACHE & hit)
  ) begin
    req_addr <= i_ahb5_addr;
    req_size <= i_ahb5_size;
    req_we   <= i_ahb5_we;
  end 
end

reg [31:0] req_tag;
reg [31:0] req_line;
reg [31:0] req_word;
reg [31:0] req_line_offset;
reg [31:0] req_word_offset;
reg [31:0] req_data_mask;
always @(*)begin
  req_tag         = req_addr & tag_mask;
  req_line        = req_addr & line_mask;
  req_word        = req_addr & word_mask;
  req_line_offset = req_line >> 4;
  req_word_offset = req_word >> 2;
  case (req_size)
		3'b000:
			case(req_addr[1:0])
				2'b00: req_data_mask = 32'h000000FF;
				2'b01: req_data_mask = 32'h0000FF00;
				2'b10: req_data_mask = 32'h00FF0000;
				2'b11: req_data_mask = 32'hFF000000;
      endcase
		3'b001:
				case(req_addr[1])
					1'b0: req_data_mask = 32'h0000FFFF;
					1'b1: req_data_mask = 32'hFFFF0000;
        endcase
		default:
      req_data_mask = 32'hFFFFFFFF;
  endcase
end

wire [31:0] lookup_tag   [3:0];
wire        lookup_dirty [3:0];
wire        lookup_valid [3:0];
genvar j;
generate
  for (j = 0; j < 4; j=j+1) begin
	  assign lookup_tag[j]   = meta_lookup_out[j] & tag_mask;
	  assign lookup_dirty[j] = |(meta_lookup_out[j] & dirty_mask);
    assign lookup_valid[j] = |(meta_lookup_out[j] & valid_mask);
  end
endgenerate

reg [1:0] hit_way_id;
always @(*)begin
  hit = 1'b0;
  hit_way_id = 2'b00;
  if(state == STATE_CACHE)begin
    case (PARAM_NB_WAYS)
      1:begin
        hit = lookup_valid[req_line[8:7]] & (lookup_tag[req_line[8:7]] == req_tag);
        hit_way_id = lookup_valid[req_line[8:7]] & (lookup_tag[req_line[8:7]] == req_tag) ? req_line[8:7] : 2'b00;
      end
      2: begin
        hit = lookup_valid[req_line[7]] & (lookup_tag[req_line[7]] == req_tag) |
              lookup_valid[req_line[7]+2] & (lookup_tag[req_line[7]+2] == req_tag);
        hit_way_id = lookup_valid[req_line[7]] & (lookup_tag[req_line[7]] == req_tag) ? req_line[7] :
                     lookup_valid[req_line[7]+2] & (lookup_tag[req_line[7]+2] == req_tag) ? req_line[7]+2 : 2'b00;
      end
      default: begin
        hit = lookup_valid[0] & (lookup_tag[0] == req_tag) |
              lookup_valid[1] & (lookup_tag[1] == req_tag) |
              lookup_valid[2] & (lookup_tag[2] == req_tag) |
              lookup_valid[3] & (lookup_tag[3] == req_tag);
        hit_way_id = lookup_valid[0] & (lookup_tag[0] == req_tag) ? 2'b00 :
                     lookup_valid[1] & (lookup_tag[1] == req_tag) ? 2'b01 :
                     lookup_valid[2] & (lookup_tag[2] == req_tag) ? 2'b10 :
                     lookup_valid[3] & (lookup_tag[3] == req_tag) ? 2'b11 : 2'b00;
      end
    endcase
  end
end

reg [1:0] miss_way_id;
always @(posedge i_clk) begin
  if(state == STATE_LOOKUP)begin
    case (PARAM_NB_WAYS)
      1:       miss_way_id <= req_line[8:7];
      2:       miss_way_id <= req_addr[7] + rp_way_id;
      default: miss_way_id <= rp_way_id;
    endcase
  end
end

always @(*) begin
  miss_dirty = 1'b00;
  if(state == STATE_LOOKUP & PARAM_NB_WAYS == 1 |
     state == STATE_REPL_POLICY) begin
    miss_dirty = lookup_dirty[] & |(metadata_memory & valid_mask);
  end
end

endmodule