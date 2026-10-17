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
localparam PARAM_REPLACEMENT_POLICY = 0; 
localparam RP_ROUND_ROBIN = 0;
localparam RP_PLRU = 1;
localparam RP_LRU  = 2;

localparam WB_BTE_LINEAR_BURST = 2'b00;

localparam WB_CTI_CLASSIC_CYCLE   = 3'b000;
localparam WB_CTI_INC_BURST_CYCLE = 3'b010;
localparam WB_CTI_END_BURST_CYCLE = 3'b111;

reg [2:0] state;
localparam STATE_ADDR           = 4'b0000;
localparam STATE_CACHE          = 4'b0001;
localparam STATE_LOOKUP         = 4'b0010;
localparam STATE_MEM_WRITE_INIT = 4'b0100;
localparam STATE_MEM_WRITE      = 4'b0101;
localparam STATE_MEM_WAIT       = 4'b0110;
localparam STATE_MEM_READ       = 4'b0111;
localparam STATE_UPDATE_META    = 4'b1000;
localparam STATE_REDO_ADDR      = 4'b1001;
localparam STATE_MEM_ERR        = 4'b1010;
localparam STATE_CLEANUP        = 4'b1010;

reg hit, miss_dirty, done_mem_write, done_mem_read; 
always @(posedge i_clk or negedge i_rst_n) begin
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

reg         meta_fwd_valid   [3:0];
reg  [31:0] meta_fwd_data    [3:0];
wire [31:0] meta_lookup_out_ [3:0];

reg         data_update_we   [3:0];
reg  [8:0]  data_update_addr [3:0];
reg  [8:0]  data_lookup_addr [3:0];
reg  [31:0] data_update_in   [3:0];
wire [31:0] data_update_out  [3:0];
wire [31:0] data_lookup_out  [3:0];

reg         data_fwd_valid   [3:0];
reg  [31:0] data_fwd_data    [3:0];
wire [31:0] data_lookup_out_ [3:0];

generate
  for (genvar i = 0; i < 4; i=i+1) begin
    sdp_ram metadata_memory (
      .clkA(i_clk), 
      .clkB(i_clk), 
      .we(meta_update_we[i]),
      .addrA(meta_update_addr[i]), 
      .addrB(meta_lookup_addr[i]),
      .dataIn(meta_update_in[i]),
      .dataOutA(meta_update_out[i]), 
      .dataOutB(meta_lookup_out_[i])
    );

    always @(posedge i_clk)begin
      meta_fwd_data[i] <= meta_update_in[i];
      meta_fwd_valid[i] <= (meta_update_addr[i] == meta_lookup_addr[i]) & meta_update_we[i];
    end
    assign meta_lookup_out[i] = meta_fwd_valid[i] ? meta_fwd_data[i] : meta_lookup_out_[i];

    sdp_ram data_memory (
      .clkA(i_clk), 
      .clkB(i_clk), 
      .we(data_update_we[i]),
      .addrA(data_update_addr[i]), 
      .addrB(data_lookup_addr[i]),
      .dataIn(data_update_in[i]),
      .dataOutA(data_update_out[i]), 
      .dataOutB(data_lookup_out_[i])
    );

    always @(posedge i_clk)begin
      data_fwd_data[i] <= data_update_in[i];
      data_fwd_valid[i] <= (data_update_addr[i] == data_lookup_addr[i]) & data_update_we[i];
    end
    assign data_lookup_out[i] = data_fwd_valid[i] ? data_fwd_data[i] : data_lookup_out_[i];
    
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
always @(posedge i_clk or negedge i_rst_n)begin
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
wire        lookup_hit   [3:0];
generate
  for (genvar i = 0; i < 4; i=i+1) begin
	  assign lookup_tag[i]   = meta_lookup_out[i] & tag_mask;
    assign lookup_valid[i] = |(meta_lookup_out[i] & valid_mask);
    assign lookup_hit[i]   = lookup_valid[i] & (lookup_tag[i] == req_tag);
    assign lookup_dirty[i] = lookup_valid[i] & ((meta_lookup_out[i] & dirty_mask) >> 1);
  end
endgenerate

reg [1:0] hit_way_id;
always @(*)begin
  hit = 1'b0;
  hit_way_id = 2'b00;
  if(state == STATE_CACHE)begin
    case (PARAM_NB_WAYS)
      1:begin
        hit = lookup_hit[req_line[8:7]];
        hit_way_id = lookup_hit[req_line[8:7]] ? req_line[8:7] : 2'b00;
      end
      2: begin
        hit = lookup_hit[{1'b0, req_line[7]}] |
              lookup_hit[{1'b1, req_line[7]}];
        hit_way_id = lookup_hit[{1'b0, req_line[7]}] ? {1'b0, req_line[7]} :
                     lookup_hit[{1'b1, req_line[7]}] ? {1'b1, req_line[7]} : 2'b00;
      end
      default: begin
        hit = lookup_hit[0] |
              lookup_hit[1] |
              lookup_hit[2] |
              lookup_hit[3];
        hit_way_id = lookup_hit[0] ? 2'b00 :
                     lookup_hit[1] ? 2'b01 :
                     lookup_hit[2] ? 2'b10 :
                     lookup_hit[3] ? 2'b11 : 2'b00;
      end
    endcase
  end
end

reg [1:0] rp_way_id;
always @(*) begin
  rp_way_id = 2'b00;
  if(state == STATE_LOOKUP)begin
    case (PARAM_REPLACEMENT_POLICY)
      RP_ROUND_ROBIN: rp_way_id = meta_lookup_out[0][3:2];  
      // TODO REST OF REPLACEMENT POLICIES
    endcase
  end
end

reg [1:0] miss_way_id;
always @(*) begin
  miss_way_id = 2'b00;
  if(state == STATE_LOOKUP)begin
    case (PARAM_NB_WAYS)
      1:       miss_way_id = req_line[8:7];
      2:       miss_way_id = {rp_way_id[0], req_addr[7]};
      default: miss_way_id = rp_way_id;
    endcase
  end
end

always @(*) begin
  miss_dirty = 1'b0;
  if(state == STATE_LOOKUP) begin
    miss_dirty = lookup_dirty[miss_way_id];
  end
end

reg [1:0] req_way_id;
always @(*) begin
  req_way_id = 2'b00;
  if(state == STATE_CACHE)
    req_way_id = hit_way_id;
  else if(state == STATE_LOOKUP | 
          state == STATE_MEM_WRITE_INIT |
          state == STATE_MEM_WRITE |
          state == STATE_MEM_READ |
          state == STATE_UPDATE_META
          ) begin
    req_way_id = miss_way_id;
  end
end

generate
  for (genvar i = 0; i < 4; i=i+1) begin
    always @(*) begin
      meta_lookup_addr[i] = 9'b0;
      data_lookup_addr[i] = 9'b0;
      if(state == STATE_ADDR | 
         state == STATE_CACHE)begin
        meta_lookup_addr[i] = i_ahb5_addr[10:4]; 
        data_lookup_addr[i] = i_ahb5_addr[10:2];
      end else if(state == STATE_REDO_ADDR)begin
        meta_lookup_addr[i] = req_addr[10:4]; 
        data_lookup_addr[i] = req_addr[10:2];
      end
   end
  end 
endgenerate

reg [4:0] wb_word;
always @(posedge i_clk) begin
  wb_word <= 5'b0;
  if(state == STATE_MEM_WRITE |
     state == STATE_MEM_READ)begin
    if(done_mem_read |
       done_mem_write)
      wb_word <= 5'b0;
    else if(i_wb_ack)
      wb_word <= wb_word + 1;
    else
     wb_word <= wb_word;
  end
end

always @(*)begin
  done_mem_read  = 1'b0;
  done_mem_write = 1'b0;
  if(state == STATE_MEM_WRITE)
    done_mem_write = (wb_word == PARAM_WORD_PER_LINE-1) & i_wb_ack;
  else if(state == STATE_MEM_READ)
    done_mem_read  = (wb_word == PARAM_WORD_PER_LINE-1) & i_wb_ack;
end

always @(*)begin
  data_update_addr[0] = 9'b0;
  data_update_addr[1] = 9'b0;
  data_update_addr[2] = 9'b0;
  data_update_addr[3] = 9'b0;
  data_update_we[0]   = 1'b0;
  data_update_we[1]   = 1'b0;
  data_update_we[2]   = 1'b0;
  data_update_we[3]   = 1'b0;
  data_update_in[0]   = 32'b0;
  data_update_in[1]   = 32'b0;
  data_update_in[2]   = 32'b0;
  data_update_in[3]   = 32'b0;
  if(state == STATE_CACHE & req_we & hit)begin
    data_update_addr[req_way_id] = req_addr[10:2];
    data_update_we[req_way_id]   = 1'b1;
    data_update_in[req_way_id]   = 
      (i_ahb5_wdata & req_data_mask) | 
      (data_lookup_out[req_way_id] & ~req_data_mask);
  end 
  else if(state == STATE_MEM_WRITE_INIT)begin
    data_update_addr[req_way_id] = (req_addr[10:4])<<2;
  end 
  else if(state == STATE_MEM_WRITE)begin
    data_update_addr[req_way_id] = (req_addr[10:4])<<2 + wb_word;
    if(i_wb_ack)begin
      data_update_addr[req_way_id] = (req_addr[10:4])<<2 + wb_word + 1;
    end
  end 
  else if(state == STATE_MEM_READ & i_wb_ack)begin
    data_update_addr[req_way_id] = (req_addr[10:4])<<2 + wb_word;
    data_update_we[req_way_id]   = 1'b1;
    data_update_in[req_way_id]   = i_wb_rdata;
  end
end

always @(*) begin
  meta_update_addr[0] = 9'b0;
  meta_update_addr[1] = 9'b0;
  meta_update_addr[2] = 9'b0;
  meta_update_addr[3] = 9'b0;
  meta_update_we[0]   = 1'b0;
  meta_update_we[1]   = 1'b0;
  meta_update_we[2]   = 1'b0;
  meta_update_we[3]   = 1'b0;
  meta_update_in[0]   = 32'b0;
  meta_update_in[1]   = 32'b0;
  meta_update_in[2]   = 32'b0;
  meta_update_in[3]   = 32'b0;
  if(state == STATE_CACHE & hit & req_we & ~lookup_dirty[req_way_id])begin
    meta_update_addr[req_way_id] = req_addr[10:4];
    meta_update_we[req_way_id]   = 1'b1;
    meta_update_in[req_way_id]   = meta_lookup_out[req_way_id] | dirty_mask;
  end 
  else if(state == STATE_MEM_WRITE_INIT |
          state == STATE_MEM_WRITE)begin
    meta_update_addr[req_way_id] = req_addr[10:4];
  end
  else if(state == STATE_UPDATE_META)begin
    meta_update_addr[req_way_id] = req_addr[10:4]; 
    meta_update_we[req_way_id]   = 1'b1;
    meta_update_in[req_way_id]   = req_tag | valid_mask;
  end
end

always @(*) begin
  o_wb_cyc   = 1'b0;
  o_wb_stb   = 1'b0;
  o_wb_we    = 1'b0;
  o_wb_bte   = 2'b0;
  o_wb_cti   = 3'b0;
  o_wb_sel   = 4'b0;
  o_wb_addr  = 32'b0;
  o_wb_wdata = 32'b0;
  if(state == STATE_MEM_WRITE)begin
    o_wb_cyc   = 1'b1;
    o_wb_stb   = 1'b1;
    o_wb_we    = 1'b1;
    o_wb_bte   = WB_BTE_LINEAR_BURST;
    o_wb_cti   = (wb_word < PARAM_WORD_PER_LINE-1) ? WB_CTI_INC_BURST_CYCLE : WB_CTI_END_BURST_CYCLE;
    o_wb_sel   = 4'b1111;
    o_wb_addr  = (meta_update_out[req_way_id] & tag_mask) | req_line | (wb_word << 2);
    o_wb_wdata = data_update_out[req_way_id];
  end
  else if(state == STATE_MEM_READ)begin
    o_wb_cyc   = 1'b1;
    o_wb_stb   = 1'b1;
    o_wb_we    = 1'b0;
    o_wb_bte   = WB_BTE_LINEAR_BURST;
    o_wb_cti   = (wb_word < PARAM_WORD_PER_LINE-1) ? WB_CTI_INC_BURST_CYCLE : WB_CTI_END_BURST_CYCLE;
    o_wb_sel   = 4'b1111;
    o_wb_addr  = req_tag | req_line | (wb_word << 2);
  end
end

always @(*) begin
  o_ahb5_rdata = 32'b0;
  o_ahb5_ready = 1'b0;
  if(state == STATE_ADDR |
    (state == STATE_CACHE & hit))begin
    o_ahb5_ready = 1'b1;
  end
  if(state == STATE_CACHE & hit & ~req_we)begin
    o_ahb5_rdata = data_lookup_out[hit_way_id] & req_data_mask;
  end
end

endmodule