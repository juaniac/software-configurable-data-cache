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
  input  wire          i_wb_err,

  // configurations
  input wire           i_cleanup
);

localparam WB_BTE_LINEAR_BURST = 2'b00;

localparam WB_CTI_CLASSIC_CYCLE   = 3'b000;
localparam WB_CTI_INC_BURST_CYCLE = 3'b010;
localparam WB_CTI_END_BURST_CYCLE = 3'b111;

reg [3:0] cstate;
localparam CSTATE_ADDR                = 4'b0000;
localparam CSTATE_CACHE               = 4'b0001;
localparam CSTATE_LOOKUP              = 4'b0010;
localparam CSTATE_MEM_EVICT           = 4'b0011;
localparam CSTATE_MEM_WAIT            = 4'b0100;
localparam CSTATE_MEM_READ            = 4'b0101;
localparam CSTATE_UPDATE_META         = 4'b0110;
localparam CSTATE_REDO_ADDR           = 4'b0111;
localparam CSTATE_MEM_ERR             = 4'b1000;
localparam CSTATE_CLEANUP_INIT        = 4'b1001;
localparam CSTATE_CLEANUP_LOOKUP      = 4'b1010;
localparam CSTATE_CLEANUP_WRITEBACK   = 4'b1011;
localparam CSTATE_CLEANUP_UPDATE_META = 4'b1100;

reg hit, miss_dirty, wb_transfer_done, cleanup_pending, cleanup_dirty, cleanup_done; 
always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n) begin
    cstate <= CSTATE_ADDR;
  end else begin
    case (cstate)
      CSTATE_ADDR: 
        cstate <= (cleanup_pending) ? CSTATE_CLEANUP_INIT :
                  (i_ahb5_trans[1]) ? CSTATE_CACHE :
                                      CSTATE_ADDR;
      CSTATE_CACHE:
        cstate <= (hit & cleanup_pending)  ? CSTATE_CLEANUP_INIT :
                  (hit & ~i_ahb5_trans[1]) ? CSTATE_ADDR :
                  (hit & i_ahb5_trans[1])  ? CSTATE_CACHE :
                                             CSTATE_LOOKUP;
      CSTATE_LOOKUP: 
        cstate <= (miss_dirty) ? CSTATE_MEM_EVICT :
                                 CSTATE_MEM_READ; 
      CSTATE_MEM_EVICT:
        cstate <= (i_wb_err)         ? CSTATE_MEM_ERR : 
                  (wb_transfer_done) ? CSTATE_MEM_WAIT :
                                       CSTATE_MEM_EVICT;
      CSTATE_MEM_ERR :
        cstate <= CSTATE_ADDR;
      CSTATE_MEM_WAIT:
        cstate <= CSTATE_MEM_READ;
      CSTATE_MEM_READ:
        cstate <= (i_wb_err)         ? CSTATE_MEM_ERR : 
                  (wb_transfer_done) ? CSTATE_UPDATE_META :
                                       CSTATE_MEM_READ;
      CSTATE_UPDATE_META:
        cstate <= CSTATE_REDO_ADDR;
      CSTATE_REDO_ADDR:
        cstate <= CSTATE_CACHE;
      CSTATE_CLEANUP_INIT:
        cstate <= CSTATE_CLEANUP_LOOKUP;
      CSTATE_CLEANUP_LOOKUP:
        cstate <= (cleanup_dirty) ? CSTATE_CLEANUP_WRITEBACK :
                  (cleanup_done)  ? CSTATE_ADDR :
                                    CSTATE_CLEANUP_LOOKUP;
      CSTATE_CLEANUP_WRITEBACK:
        cstate <= (i_wb_err)         ? CSTATE_CLEANUP_INIT : 
                  (wb_transfer_done) ? CSTATE_CLEANUP_UPDATE_META :
                                       CSTATE_CLEANUP_WRITEBACK;
      CSTATE_CLEANUP_UPDATE_META:
        cstate <= CSTATE_CLEANUP_INIT;
      default:
        cstate <= CSTATE_ADDR;
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
    assign meta_lookup_out[i] = (meta_fwd_valid[i]) ? meta_fwd_data[i] : meta_lookup_out_[i];

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
    assign data_lookup_out[i] = (data_fwd_valid[i]) ? data_fwd_data[i] : data_lookup_out_[i];
    
  end
endgenerate

wire [31:0] tag_mask, line_mask, word_mask, dirty_mask, valid_mask;
assign tag_mask   = {{19{1'b1}}, {9{1'b0}}, {4{1'b0}}};
assign line_mask  = {{19{1'b0}}, {9{1'b1}}, {4{1'b0}}};
assign word_mask  = {{19{1'b0}}, {9{1'b0}}, {2{1'b1}}, {2{1'b0}}};
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
    cstate == CSTATE_ADDR |
    (cstate == CSTATE_CACHE & hit)
  ) begin
    req_addr <= i_ahb5_addr;
    req_size <= i_ahb5_size;
    req_we   <= i_ahb5_we;
  end 
end

reg [31:0] req_tag;
reg [31:0] req_line;
reg [31:0] req_word;
reg [31:0] req_data_mask;
always @(*)begin
  req_tag  = req_addr & tag_mask;
  req_line = req_addr & line_mask;
  req_word = req_addr & word_mask;
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

reg [31:0] lookup_tag   [3:0];
reg        lookup_dirty [3:0];
reg        lookup_valid [3:0];
reg        lookup_hit   [3:0];
generate
  for (genvar i = 0; i < 4; i=i+1) begin
    always @(*) begin
      lookup_tag[i]   = meta_lookup_out[i] & tag_mask;
      lookup_valid[i] = |(meta_lookup_out[i] & valid_mask);
      lookup_hit[i]   = lookup_valid[i] & (lookup_tag[i] == req_tag);
      lookup_dirty[i] = lookup_valid[i] & ((meta_lookup_out[i] & dirty_mask) >> 1);
    end
  end
endgenerate

reg [1:0] hit_way_id;
always @(*)begin
  hit = 1'b0;
  hit_way_id = 2'b00;
  if(cstate == CSTATE_CACHE)begin
    hit = lookup_hit[req_addr[12:11]];
    hit_way_id = (lookup_hit[req_line[12:11]]) ? req_line[12:11] : 2'b00;
  end
end

reg [1:0] miss_way_id;
always @(*) begin
  miss_way_id = 2'b00;
  if(cstate == CSTATE_LOOKUP | 
     cstate == CSTATE_MEM_EVICT |
     cstate == CSTATE_MEM_READ |
     cstate == CSTATE_UPDATE_META)begin
    miss_way_id = req_line[12:11];
  end
end

always @(*) begin
  miss_dirty = 1'b0;
  if(cstate == CSTATE_LOOKUP) begin
    miss_dirty = lookup_dirty[miss_way_id];
  end
end

reg [1:0] req_way_id;
reg [8:0] cleanup_line;
reg [1:0] cleanup_dirty_way_id;
always @(*) begin
  req_way_id = 2'b00;
  if(cstate == CSTATE_CACHE)
    req_way_id = hit_way_id;
  else if(cstate == CSTATE_LOOKUP | 
          cstate == CSTATE_MEM_EVICT |
          cstate == CSTATE_MEM_READ |
          cstate == CSTATE_UPDATE_META)
    req_way_id = miss_way_id;
  else if(cstate == CSTATE_CLEANUP_WRITEBACK)
    req_way_id = cleanup_dirty_way_id;
end

generate
  for (genvar i = 0; i < 4; i=i+1) begin
    always @(*) begin
      if(cstate == CSTATE_ADDR | 
         cstate == CSTATE_CACHE & hit)begin
        meta_lookup_addr[i] = i_ahb5_addr[10:4]; 
        data_lookup_addr[i] = i_ahb5_addr[10:2];
      end else if(cstate == CSTATE_CLEANUP_INIT |
                  cstate == CSTATE_CLEANUP_LOOKUP |
                  cstate == CSTATE_CLEANUP_WRITEBACK |
                  cstate == CSTATE_CLEANUP_UPDATE_META)begin
        meta_lookup_addr[i] = cleanup_line + ((cstate == CSTATE_CLEANUP_LOOKUP) ? 1'b1 : 1'b0); 
        data_lookup_addr[i] = {(cleanup_line + ((cstate == CSTATE_CLEANUP_LOOKUP) ? 1'b1 : 1'b0)), 2'b00};
      end else begin
        meta_lookup_addr[i] = req_addr[10:4]; 
        data_lookup_addr[i] = req_addr[10:2];
      end
   end
  end 
endgenerate

reg [1:0] wbstate;
localparam WBSTATE_IDLE       = 2'b00;
localparam WBSTATE_WDATA_WAIT = 2'b01;
localparam WBSTATE_TRANSFER   = 2'b10;

reg        wb_transfer_we;
reg  [5:0] wb_transfer_size;
reg [31:0] wb_transfer_base_addr;
reg  [4:0] wb_word_offset;
always @(posedge i_clk or negedge i_rst_n)begin
  if(~i_rst_n)begin
    wbstate               <= WBSTATE_IDLE;
    wb_transfer_we        <= 1'b0;
    wb_transfer_size      <= 6'b0;
    wb_transfer_base_addr <= 32'b0;
    wb_word_offset        <= 4'b0;
  end
  else begin
    if(cstate == CSTATE_LOOKUP & miss_dirty)begin
      wbstate               <= WBSTATE_WDATA_WAIT;
      wb_transfer_we        <= 1'b1;
      wb_transfer_size      <= 4;
      wb_transfer_base_addr <= lookup_tag[req_way_id] | req_line;
      wb_word_offset        <= 4'b0;
    end 
    else if((cstate == CSTATE_LOOKUP & ~miss_dirty) |
             cstate == CSTATE_MEM_WAIT)begin
      wbstate               <= WBSTATE_TRANSFER;
      wb_transfer_we        <= 1'b0;
      wb_transfer_size      <= 4;
      wb_transfer_base_addr <= req_tag | req_line;
      wb_word_offset        <= 4'b0;
    end 
    else if(cstate == CSTATE_CLEANUP_LOOKUP & cleanup_dirty)begin
      wbstate               <= WBSTATE_WDATA_WAIT;
      wb_transfer_we        <= 1'b1;
      wb_transfer_size      <= 4;
      wb_transfer_base_addr <= lookup_tag[cleanup_dirty_way_id] | {cleanup_line, 4'b0000};
      wb_word_offset        <= 4'b0;
    end

    if(wbstate == WBSTATE_WDATA_WAIT)
      wbstate <= WBSTATE_TRANSFER;
    if((wbstate == WBSTATE_TRANSFER & wb_transfer_done) | i_wb_err)
      wbstate <= WBSTATE_IDLE;

    if(i_wb_ack)
      wb_word_offset <= wb_word_offset + 1;
  end
end

always @(*)begin
  wb_transfer_done = (wbstate == WBSTATE_TRANSFER) & (wb_word_offset == wb_transfer_size-1) & i_wb_ack;
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
  if(cstate == CSTATE_CACHE & req_we & hit)begin
    data_update_addr[req_way_id] = req_addr[10:2];
    data_update_we[req_way_id]   = 1'b1;
    data_update_in[req_way_id]   = 
      (i_ahb5_wdata & req_data_mask) | 
      (data_lookup_out[req_way_id] & ~req_data_mask);
  end 
  else if(cstate == CSTATE_MEM_EVICT)begin
    data_update_addr[req_way_id] = {req_addr[10:4], 2'b00} + wb_word_offset;
    if(i_wb_ack)begin
      data_update_addr[req_way_id] = {req_addr[10:4], 2'b00} + wb_word_offset + 1;
    end
  end 
  else if(cstate == CSTATE_MEM_READ & i_wb_ack)begin
    data_update_addr[req_way_id] = {req_addr[10:4], 2'b00} + wb_word_offset;
    data_update_we[req_way_id]   = 1'b1;
    data_update_in[req_way_id]   = i_wb_rdata;
  end
  else if(cstate == CSTATE_CLEANUP_WRITEBACK)begin
    data_update_addr[req_way_id] = {cleanup_line, 2'b00} + wb_word_offset;
    if(i_wb_ack)begin
      data_update_addr[req_way_id] = {cleanup_line, 2'b00} + wb_word_offset + 1;
    end
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
  if(cstate == CSTATE_CACHE & hit & req_we & ~lookup_dirty[req_way_id])begin
    meta_update_addr[req_way_id] = req_addr[10:4];
    meta_update_we[req_way_id]   = 1'b1;
    meta_update_in[req_way_id]   = meta_lookup_out[req_way_id] | dirty_mask;
  end 
  else if(cstate == CSTATE_MEM_EVICT)begin
    meta_update_addr[req_way_id] = req_addr[10:4];
  end
  else if(cstate == CSTATE_UPDATE_META)begin
    meta_update_addr[req_way_id] = req_addr[10:4]; 
    meta_update_we[req_way_id]   = 1'b1;
    meta_update_in[req_way_id]   = req_tag | valid_mask;
  end else if(cstate == CSTATE_CLEANUP_LOOKUP & ~cleanup_dirty)begin
    meta_update_addr[0] = cleanup_line;
    meta_update_addr[1] = cleanup_line;
    meta_update_addr[2] = cleanup_line;
    meta_update_addr[3] = cleanup_line;
    meta_update_we[0]   = 1'b1;
    meta_update_we[1]   = 1'b1;
    meta_update_we[2]   = 1'b1;
    meta_update_we[3]   = 1'b1;
    meta_update_in[0]   = 32'b0;
    meta_update_in[1]   = 32'b0;
    meta_update_in[2]   = 32'b0;
    meta_update_in[3]   = 32'b0;
  end else if(cstate == CSTATE_CLEANUP_UPDATE_META)begin
    meta_update_addr[cleanup_dirty_way_id] = cleanup_line; 
    meta_update_we[cleanup_dirty_way_id]   = 1'b1;
    meta_update_in[cleanup_dirty_way_id]   = 32'b0;
  end
end

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n)begin
    cleanup_pending <= 1'b0;
    cleanup_line    <= 9'b0;
  end else begin 
    if(cstate == CSTATE_CLEANUP_LOOKUP & ~cleanup_dirty)
      cleanup_line <= cleanup_line + 1;

    if(i_cleanup)
      cleanup_pending <= 1'b1;
    
    if(cleanup_done)begin
      cleanup_pending <= 1'b0;
      cleanup_line    <= 9'b0;
    end
  end
end

always @(*) begin
  cleanup_dirty = lookup_dirty[0] |
                  lookup_dirty[1] |
                  lookup_dirty[2] |
                  lookup_dirty[3];
  cleanup_dirty_way_id = (lookup_dirty[0] == 1'b1) ? 2'b00 :
                         (lookup_dirty[1] == 1'b1) ? 2'b01 :
                         (lookup_dirty[2] == 1'b1) ? 2'b10 :
                         (lookup_dirty[3] == 1'b1) ? 2'b11 : 2'b00;

  cleanup_done = (cstate == CSTATE_CLEANUP_LOOKUP) & (cleanup_line == (128-1)) & ~cleanup_dirty;
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
  if(wbstate == WBSTATE_TRANSFER)begin
    o_wb_cyc   = 1'b1;
    o_wb_stb   = 1'b1;
    o_wb_we    = wb_transfer_we;
    o_wb_bte   = WB_BTE_LINEAR_BURST;
    
    if(wb_transfer_size > 1)begin
      o_wb_cti   = (wb_word_offset < 4-1) ? WB_CTI_INC_BURST_CYCLE : WB_CTI_END_BURST_CYCLE;
      o_wb_sel   = 4'b1111;
      o_wb_addr  = wb_transfer_base_addr | {wb_word_offset, 2'b00};
      if(wb_transfer_we)
        o_wb_wdata = data_update_out[req_way_id];
    end else begin
      o_wb_cti   = WB_CTI_CLASSIC_CYCLE;
      o_wb_sel   = {req_data_mask[24], req_data_mask[16], req_data_mask[8], req_data_mask[0]};
      o_wb_addr  = wb_transfer_base_addr;
      if(wb_transfer_we)  
        o_wb_wdata = i_ahb5_wdata;
    end
  end
end

always @(*) begin
  o_ahb5_rdata = 32'b0;
  o_ahb5_ready = 1'b0;
  if(cstate == CSTATE_ADDR |
    (cstate == CSTATE_CACHE & hit))begin
    o_ahb5_ready = 1'b1;
  end
  if(cstate == CSTATE_CACHE & hit & ~req_we)begin
    o_ahb5_rdata = data_lookup_out[hit_way_id] & req_data_mask;
  end
end

always @(posedge i_clk) begin
  o_ahb5_resp <= 1'b0;
  if(i_wb_err | cstate == CSTATE_MEM_ERR)
    o_ahb5_resp <= 1'b1;
end

endmodule