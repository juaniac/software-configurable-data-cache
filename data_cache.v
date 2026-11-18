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
  input wire           i_flush,
  input wire  [1:0]    i_cache_size,
  input wire  [1:0]    i_associativity,
  input wire  [1:0]    i_cache_line_size,
  input wire           i_write_policy
);
reg [1:0]  conf_cache_size;
localparam CONF_1KB = 2'b00;
localparam CONF_2KB = 2'b01;
localparam CONF_4KB = 2'b10;
localparam CONF_8KB = 2'b11;

reg [1:0]  conf_associativity;
localparam CONF_OFF        = 2'b00;
localparam CONF_DIRECT_MAP = 2'b01;
localparam CONF_2_WAY_SET  = 2'b10;
localparam CONF_4_WAY_SET  = 2'b11;

reg [1:0]  conf_cache_line_size;
localparam CONF_16B  = 2'b00;
localparam CONF_32B  = 2'b01;
localparam CONF_64B  = 2'b10;
localparam CONF_128B = 2'b11;

reg        conf_write_policy;
localparam CONF_WRITE_BACK    = 1'b0;
localparam CONF_WRITE_THROUGH = 1'b1;

reg [5:0] conf_nb_tag_bits;
reg [5:0] conf_nb_mem_id_bits;
reg [5:0] conf_nb_line_bits;
reg [5:0] conf_nb_word_bits;
reg [5:0] conf_nb_byte_bits;

reg       conf_cache_on;

wire [6:0] conf_new;
reg  [6:0] conf_active;

reg [31:0] ahb5_addr_tag;
reg [31:0] ahb5_addr_mem_id;
reg [31:0] ahb5_addr_line;
reg [31:0] ahb5_addr_word;
reg [31:0] ahb5_addr_byte;
reg  [3:0] ahb5_byte_sel;

`define WORD_ADDR(addr) ((addr) >> (conf_nb_byte_bits))
`define LINE_ADDR(addr) ((addr) >> (conf_nb_word_bits + conf_nb_byte_bits))
`define MEM_ID_ADDR(addr) ((addr) >> (conf_nb_line_bits + conf_nb_word_bits + conf_nb_byte_bits))

reg  [31:0] addr_tag_mask;
reg  [31:0] addr_mem_id_mask;
reg  [31:0] addr_line_mask;
reg  [31:0] addr_word_mask;
reg  [31:0] addr_byte_mask;

wire  [31:0] meta_repl_mask; 
wire  [31:0] meta_dirty_mask; 
wire  [31:0] meta_valid_mask;

reg [3:0]  req_state;
localparam REQ_STATE_ADDR            = 4'b0000;
localparam REQ_STATE_CACHE           = 4'b0001;
localparam REQ_STATE_LOOKUP          = 4'b0010;
localparam REQ_STATE_EVICT           = 4'b0011;
localparam REQ_STATE_BUS_WAIT        = 4'b0100;
localparam REQ_STATE_REFILL          = 4'b0101;
localparam REQ_STATE_UPDATE_META     = 4'b0110;
localparam REQ_STATE_REDO_ADDR       = 4'b0111;
localparam REQ_STATE_BUS_ERR         = 4'b1000;
localparam REQ_STATE_STALL           = 4'b1001;
localparam REQ_STATE_BYPASS_TRANSFER = 4'b1010;
localparam REQ_STATE_BYPASS_RESPONSE = 4'b1011;

reg req_pending_transfer;
reg req_cacheable_addr;
reg req_cache_start;
reg req_bypass_start;
reg req_stall_start;
reg req_write_through;

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

reg [31:0] lookup_tag   [3:0];
reg        lookup_dirty [3:0];
reg        lookup_valid [3:0];
reg        lookup_hit   [3:0];
reg [5:0]  lookup_repl  [3:0];

reg [31:0] req_addr;
reg [31:0] req_addr_tag;
reg [31:0] req_addr_mem_id;
reg [31:0] req_addr_line;
reg [31:0] req_addr_word;
reg [2:0]  req_size;
reg        req_we;
reg [31:0] req_rdata;
reg [31:0] req_data_mask;
reg [1:0]  req_mem_id;
reg        req_hit;
reg [1:0]  req_hit_mem_id;
reg [1:0]  req_miss_mem_id;
reg        req_miss_dirty;

reg [2:0]  flush_state;
localparam FLUSH_STATE_IDLE        = 3'b000;
localparam FLUSH_STATE_ADDR        = 3'b100;
localparam FLUSH_STATE_LOOKUP      = 3'b101;
localparam FLUSH_STATE_WRITEBACK   = 3'b110;
localparam FLUSH_STATE_UPDATE_META = 3'b111;

reg [8:0] flush_line;
reg [1:0] flush_line_dirty_mem_id;
reg       flush_pending; 
reg       flush_line_dirty;
reg       flush_writeback;
reg       flush_start;
reg       flush_done;

reg [1:0] mem_id;

reg [1:0]  wb_state;
localparam WB_STATE_IDLE       = 2'b00;
localparam WB_STATE_WDATA_WAIT = 2'b01;
localparam WB_STATE_TRANSFER   = 2'b10;

reg        wb_transfer_we;
reg  [5:0] wb_transfer_size;
reg  [3:0] wb_transfer_byte_sel;
reg [31:0] wb_transfer_base_addr;
reg  [4:0] wb_word_offset;
reg        wb_transfer_done;
reg        wb_bus_err;

localparam WB_BTE_LINEAR_BURST = 2'b00;

localparam WB_CTI_CLASSIC_CYCLE   = 3'b000;
localparam WB_CTI_INC_BURST_CYCLE = 3'b010;
localparam WB_CTI_END_BURST_CYCLE = 3'b111;

assign conf_new = {i_cache_size, i_associativity, i_cache_line_size, i_write_policy};

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n)
    conf_active <= {CONF_8KB, CONF_DIRECT_MAP, CONF_16B, CONF_WRITE_THROUGH};
  else if(flush_done)
    conf_active <= conf_new;
end

always @(*) begin
  conf_cache_size      = conf_active[6:5];
  conf_associativity   = conf_active[4:3];
  conf_cache_line_size = conf_active[2:1];
  conf_write_policy    = conf_active[0];

  conf_nb_byte_bits = 6'd2;  
  conf_nb_word_bits = (conf_cache_line_size == CONF_16B)  ? 6'd2 :
                      (conf_cache_line_size == CONF_32B)  ? 6'd3 :
                      (conf_cache_line_size == CONF_64B)  ? 6'd4 :
                      (conf_cache_line_size == CONF_128B) ? 6'd5 :
                                                            6'd0;
  conf_nb_mem_id_bits = (conf_associativity == CONF_DIRECT_MAP) ? 6'd2 :
                        (conf_associativity == CONF_2_WAY_SET)  ? 6'd1 :
                        (conf_associativity == CONF_4_WAY_SET)  ? 6'd0 :
                                                                  6'd0;
  conf_nb_line_bits = ((conf_cache_size == CONF_1KB) ? 6'd10 :
                      (conf_cache_size == CONF_2KB)  ? 6'd11 :
                      (conf_cache_size == CONF_4KB)  ? 6'd12 :
                      (conf_cache_size == CONF_8KB)  ? 6'd13 :
                                                       6'd0)
                      - (conf_nb_mem_id_bits + conf_nb_word_bits + conf_nb_byte_bits);
  conf_nb_tag_bits    = 6'd32 - (conf_nb_mem_id_bits + conf_nb_line_bits + conf_nb_word_bits + conf_nb_byte_bits);

  conf_cache_on = (conf_associativity == CONF_DIRECT_MAP) |
                  (conf_associativity == CONF_2_WAY_SET) |
                  (conf_associativity == CONF_4_WAY_SET);
end

assign meta_repl_mask  = 32'b11111100;
assign meta_dirty_mask = 32'b10;
assign meta_valid_mask = 32'b1;

always @(*) begin
  addr_tag_mask    = (((33'b1 << (conf_nb_tag_bits)) - 1) << (conf_nb_mem_id_bits + conf_nb_line_bits + conf_nb_word_bits + conf_nb_byte_bits));
  addr_mem_id_mask = (((33'b1 << (conf_nb_mem_id_bits)) - 1) << (conf_nb_line_bits + conf_nb_word_bits + conf_nb_byte_bits));
  addr_line_mask   = (((33'b1 << (conf_nb_line_bits)) - 1) << (conf_nb_word_bits + conf_nb_byte_bits));
  addr_word_mask   = (((33'b1 << (conf_nb_word_bits)) - 1) << (conf_nb_byte_bits));
  addr_byte_mask   = ((33'b1 << (conf_nb_byte_bits)) - 1);

  ahb5_addr_tag    = i_ahb5_addr & addr_tag_mask;
  ahb5_addr_mem_id = i_ahb5_addr & addr_mem_id_mask;
  ahb5_addr_line   = i_ahb5_addr & addr_line_mask;
  ahb5_addr_word   = i_ahb5_addr & addr_word_mask;
  ahb5_addr_byte   = i_ahb5_addr & addr_byte_mask;
  case (i_ahb5_size)
		3'b000:
			case(ahb5_addr_byte)
				2'b00: ahb5_byte_sel = 4'b0001;
				2'b01: ahb5_byte_sel = 4'b0010;
				2'b10: ahb5_byte_sel = 4'b0100;
				2'b11: ahb5_byte_sel = 4'b1000;
      endcase
		3'b001:
			case(ahb5_addr_byte)
				2'b00, 2'b01: ahb5_byte_sel = 4'b0011;
				2'b10, 2'b11: ahb5_byte_sel = 4'b1100;
      endcase
		default:
      ahb5_byte_sel = 4'b1111;
  endcase
end

always @(*) begin
  req_cacheable_addr   = (req_state == REQ_STATE_STALL) ? ~req_addr[31] : ~i_ahb5_addr[31];
  req_pending_transfer = ((req_state == REQ_STATE_STALL) ? 1'b1 : i_ahb5_trans[1]);
  req_cache_start      = req_pending_transfer & conf_cache_on & req_cacheable_addr & ~flush_pending;
  req_bypass_start     = req_pending_transfer &
                         (~req_cacheable_addr | (~flush_pending & ~conf_cache_on)) &  
                         ((flush_state == FLUSH_STATE_IDLE) |
                          (flush_state == FLUSH_STATE_ADDR) |
                          ((flush_state == FLUSH_STATE_LOOKUP) & ~flush_line_dirty) |
                          (flush_state == FLUSH_STATE_UPDATE_META)) &
                         (wb_state == WB_STATE_IDLE);
  req_stall_start      = req_pending_transfer & 
                         ((req_cacheable_addr & flush_pending) |
                          ((flush_state == FLUSH_STATE_LOOKUP) & flush_writeback) | 
                          (flush_state == FLUSH_STATE_WRITEBACK) |
                          (wb_state == WB_STATE_WDATA_WAIT) |
                          (wb_state == WB_STATE_TRANSFER));
  req_write_through    = req_we & (conf_write_policy == CONF_WRITE_THROUGH);
end

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n) begin
    req_state <= REQ_STATE_ADDR;
  end else begin
    case (req_state)
      REQ_STATE_ADDR: 
        req_state <= (req_cache_start)  ? REQ_STATE_CACHE :
                     (req_bypass_start) ? REQ_STATE_BYPASS_TRANSFER :
                     (req_stall_start)  ? REQ_STATE_STALL :
                                          REQ_STATE_ADDR;
      REQ_STATE_CACHE:
        req_state <= (req_write_through) ? REQ_STATE_BYPASS_TRANSFER :
                     (~req_hit)          ? REQ_STATE_LOOKUP :
                     (req_cache_start)   ? REQ_STATE_CACHE :
                     (req_bypass_start)  ? REQ_STATE_BYPASS_TRANSFER :
                     (req_stall_start)   ? REQ_STATE_STALL :
                                           REQ_STATE_ADDR;
      REQ_STATE_LOOKUP: 
        req_state <= (req_miss_dirty) ? REQ_STATE_EVICT :
                                        REQ_STATE_REFILL;     
      REQ_STATE_EVICT:
        req_state <= (wb_bus_err)       ? REQ_STATE_BUS_ERR : 
                     (wb_transfer_done) ? REQ_STATE_BUS_WAIT :
                                          REQ_STATE_EVICT;
      REQ_STATE_BUS_ERR :
        req_state <= REQ_STATE_ADDR;
      REQ_STATE_BUS_WAIT:
        req_state <= REQ_STATE_REFILL;
      REQ_STATE_REFILL:
        req_state <= (wb_bus_err)       ? REQ_STATE_BUS_ERR : 
                     (wb_transfer_done) ? REQ_STATE_UPDATE_META :
                                          REQ_STATE_REFILL;
      REQ_STATE_UPDATE_META:
        req_state <= REQ_STATE_REDO_ADDR;
      REQ_STATE_REDO_ADDR:
        req_state <= REQ_STATE_CACHE;
      REQ_STATE_STALL:  
        req_state <= (req_cache_start)  ? REQ_STATE_REDO_ADDR :
                     (req_bypass_start) ? REQ_STATE_BYPASS_TRANSFER :
                                          REQ_STATE_STALL;
      REQ_STATE_BYPASS_TRANSFER:
        req_state <= (wb_bus_err)       ? REQ_STATE_BUS_ERR :
                     (wb_transfer_done) ? REQ_STATE_BYPASS_RESPONSE :
                                          REQ_STATE_BYPASS_TRANSFER;
      REQ_STATE_BYPASS_RESPONSE:
        req_state <= (req_cache_start)  ? REQ_STATE_CACHE :
                     (req_bypass_start) ? REQ_STATE_BYPASS_TRANSFER :
                     (req_stall_start)  ? REQ_STATE_STALL :
                                          REQ_STATE_ADDR;
      default:
        req_state <= REQ_STATE_ADDR;
    endcase
  end
end

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
      meta_fwd_data[i]  <= meta_update_in[i];
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
      data_fwd_data[i]  <= data_update_in[i];
      data_fwd_valid[i] <= (data_update_addr[i] == data_lookup_addr[i]) & data_update_we[i];
    end
    assign data_lookup_out[i] = (data_fwd_valid[i]) ? data_fwd_data[i] : data_lookup_out_[i];
    
  end
endgenerate

generate
  for (genvar i = 0; i < 4; i=i+1) begin
    always @(*) begin
      lookup_tag[i]   = meta_lookup_out[i] & addr_tag_mask;
      lookup_valid[i] = |(meta_lookup_out[i] & meta_valid_mask);
      lookup_hit[i]   = lookup_valid[i] & (lookup_tag[i] == req_addr_tag);
      lookup_dirty[i] = lookup_valid[i] & ((meta_lookup_out[i] & meta_dirty_mask) >> 1);
      lookup_repl[i]  = {6{lookup_valid[i]}} & ((meta_lookup_out[i] & meta_repl_mask) >> 2);
    end
  end
endgenerate

always @(posedge i_clk or negedge i_rst_n)begin
  if(~i_rst_n)begin
    req_addr <= 32'b0;
    req_size <= 3'b0;
    req_we   <= 1'b0;
    
    req_addr_tag    <= 32'b0;
    req_addr_mem_id <= 32'b0;
    req_addr_line   <= 32'b0;
    req_addr_word   <= 32'b0;
  end else if(
    ((req_state == REQ_STATE_ADDR) & req_pending_transfer) |
    ((req_state == REQ_STATE_CACHE) & ~req_write_through & req_hit & req_pending_transfer) |
    ((req_state == REQ_STATE_BYPASS_RESPONSE) & req_pending_transfer)
  )begin
    req_addr <= i_ahb5_addr; 
    req_size <= i_ahb5_size;
    req_we   <= i_ahb5_we;

    req_addr_tag    <= ahb5_addr_tag;
    req_addr_mem_id <= ahb5_addr_mem_id;
    req_addr_line   <= ahb5_addr_line;
    req_addr_word   <= ahb5_addr_word;
    req_data_mask   <= {{8{ahb5_byte_sel[3]}},
                        {8{ahb5_byte_sel[2]}},
                        {8{ahb5_byte_sel[1]}},
                        {8{ahb5_byte_sel[0]}}};
  end 
end

always @(*)begin
  req_hit = 1'b0;
  req_hit_mem_id = 2'b00;
  req_mem_id = `MEM_ID_ADDR(req_addr_mem_id);
  if(req_state == REQ_STATE_CACHE)begin
    if(conf_associativity == CONF_DIRECT_MAP)begin
      req_hit = lookup_hit[req_mem_id];
      req_hit_mem_id = (lookup_hit[req_mem_id]) ? req_mem_id : 2'b00;
    end 
    else if(conf_associativity == CONF_2_WAY_SET) begin
      req_hit = lookup_hit[{1'b0, req_mem_id[0]}] |
                lookup_hit[{1'b1, req_mem_id[0]}];
      req_hit_mem_id = (lookup_hit[{1'b0, req_mem_id[0]}]) ? {1'b0, req_mem_id[0]} :
                       (lookup_hit[{1'b1, req_mem_id[0]}]) ? {1'b1, req_mem_id[0]} : 2'b00;
    end
    else if(conf_associativity == CONF_4_WAY_SET) begin
      req_hit = lookup_hit[2'b00] |
                lookup_hit[2'b01] |
                lookup_hit[2'b10] |
                lookup_hit[2'b11];
      req_hit_mem_id = (lookup_hit[2'b00]) ? 2'b00 :
                       (lookup_hit[2'b01]) ? 2'b01 :
                       (lookup_hit[2'b10]) ? 2'b10 :
                       (lookup_hit[2'b11]) ? 2'b11 : 2'b00;
    end
  end
end

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n)begin
    req_miss_mem_id <= 2'b00;
  end
  else if(req_state == REQ_STATE_CACHE & ~req_hit)begin
    if(conf_associativity == CONF_DIRECT_MAP)
      req_miss_mem_id <= req_mem_id;
    else if(conf_associativity == CONF_2_WAY_SET)
      req_miss_mem_id <= {lookup_repl[2'b00][0], req_mem_id[0]};
    else if(conf_associativity == CONF_4_WAY_SET)
      req_miss_mem_id <= lookup_repl[2'b00][1:0];
  end
end

always @(*) begin
  req_miss_dirty = 1'b0;
  if(req_state == REQ_STATE_LOOKUP) begin
    req_miss_dirty = lookup_dirty[req_miss_mem_id];
  end
end

always @(*) begin
  mem_id = 2'b00;
  if(req_state == REQ_STATE_CACHE)
    mem_id = req_hit_mem_id;
  else if((req_state == REQ_STATE_LOOKUP) | 
          (req_state == REQ_STATE_EVICT) |
          (req_state == REQ_STATE_REFILL)     |
          (req_state == REQ_STATE_UPDATE_META))
    mem_id = req_miss_mem_id;
  else if((flush_state == FLUSH_STATE_LOOKUP) |
          (flush_state == FLUSH_STATE_WRITEBACK) |
          (flush_state == FLUSH_STATE_UPDATE_META))
    mem_id = flush_line_dirty_mem_id;
end

generate
  for (genvar i = 0; i < 4; i=i+1) begin
    always @(*) begin
       if(
        (flush_state == FLUSH_STATE_ADDR) |
        ((flush_state == FLUSH_STATE_LOOKUP) & flush_line_dirty) |
        (flush_state == FLUSH_STATE_WRITEBACK) |
        (flush_state == FLUSH_STATE_UPDATE_META)
      )begin
        meta_lookup_addr[i] = flush_line; 
        data_lookup_addr[i] = {flush_line, 2'b00};
      end else if(
        (flush_state == FLUSH_STATE_LOOKUP) & ~flush_line_dirty
      )begin
        meta_lookup_addr[i] = flush_line + 1'b1; 
        data_lookup_addr[i] = {flush_line + 1'b1, 2'b00};
      end else if(
        (req_state == REQ_STATE_ADDR) | 
        ((req_state == REQ_STATE_CACHE) & req_hit) |
        (req_state == REQ_STATE_BYPASS_RESPONSE)
      )begin
        meta_lookup_addr[i] = `LINE_ADDR(ahb5_addr_line); 
        data_lookup_addr[i] = `WORD_ADDR(ahb5_addr_line | ahb5_addr_word);
      end else begin
        meta_lookup_addr[i] = `LINE_ADDR(req_addr_line);
        data_lookup_addr[i] = `WORD_ADDR(req_addr_line | req_addr_word);
      end
   end
  end 
endgenerate

always @(posedge i_clk or negedge i_rst_n)begin
  if(~i_rst_n)begin
    wb_state              <= WB_STATE_IDLE;
    wb_transfer_we        <= 1'b0;
    wb_transfer_size      <= 6'b0;
    wb_transfer_byte_sel  <= 4'b0;
    wb_transfer_base_addr <= 32'b0;
    wb_word_offset        <= 4'b0;
  end
  else begin
    if(wb_state == WB_STATE_IDLE)begin
      if((req_state == REQ_STATE_LOOKUP) & req_miss_dirty)begin
        wb_state              <= WB_STATE_WDATA_WAIT;
        wb_transfer_we        <= 1'b1;
        wb_transfer_size      <= ((32'b1) << conf_nb_word_bits);
        wb_transfer_byte_sel  <= 4'b1111;
        wb_transfer_base_addr <= (lookup_tag[mem_id] | req_addr_mem_id | req_addr_line);
        wb_word_offset        <= 4'b0;
      end 
      else if(((req_state == REQ_STATE_LOOKUP) & ~req_miss_dirty) |
               (req_state == REQ_STATE_BUS_WAIT))begin
        wb_state              <= WB_STATE_TRANSFER;
        wb_transfer_we        <= 1'b0;
        wb_transfer_size      <= ((32'b1) << conf_nb_word_bits);
        wb_transfer_byte_sel  <= 4'b1111;
        wb_transfer_base_addr <= (req_addr_tag | req_addr_mem_id | req_addr_line);
        wb_word_offset        <= 4'b0;
      end 
      else if(((req_state == REQ_STATE_ADDR) & req_bypass_start) | 
              ((req_state == REQ_STATE_CACHE) & req_hit & req_bypass_start) |
              ((req_state == REQ_STATE_BYPASS_RESPONSE) & req_bypass_start))begin
        wb_state              <= WB_STATE_TRANSFER;
        wb_transfer_we        <= i_ahb5_we;
        wb_transfer_size      <= 1;
        wb_transfer_byte_sel  <= ahb5_byte_sel;
        wb_transfer_base_addr <= (ahb5_addr_tag | ahb5_addr_mem_id | ahb5_addr_line | ahb5_addr_word);
        wb_word_offset        <= 4'b0;
      end
      else if(((req_state == REQ_STATE_STALL) & req_bypass_start) |
              ((req_state == REQ_STATE_CACHE) & req_write_through))begin
        wb_state              <= WB_STATE_TRANSFER;
        wb_transfer_we        <= req_we;
        wb_transfer_size      <= 1;
        wb_transfer_byte_sel  <= {req_data_mask[24], req_data_mask[16], req_data_mask[8], req_data_mask[0]};
        wb_transfer_base_addr <= (req_addr_tag | req_addr_mem_id | req_addr_line | req_addr_word);
        wb_word_offset        <= 4'b0;
      end
      else if((flush_state == FLUSH_STATE_LOOKUP) & flush_writeback)begin
        wb_state              <= WB_STATE_WDATA_WAIT;
        wb_transfer_we        <= 1'b1;
        wb_transfer_size      <= ((32'b1) << conf_nb_word_bits);
        wb_transfer_byte_sel  <= 4'b1111;
        wb_transfer_base_addr <= lookup_tag[mem_id] | {mem_id, flush_line[6:0], 4'b0000};
        wb_word_offset        <= 4'b0;
      end
    end else if(wb_state == WB_STATE_WDATA_WAIT)begin
      wb_state <= WB_STATE_TRANSFER;
    end else if((wb_state == WB_STATE_TRANSFER) & (wb_transfer_done | wb_bus_err))begin
      wb_state <= WB_STATE_IDLE;
    end

    if((wb_state == WB_STATE_TRANSFER) & wb_transfer_done)
      wb_word_offset <= 4'b0;
    else if((wb_state == WB_STATE_TRANSFER) & i_wb_ack)
      wb_word_offset <= wb_word_offset + 1;
  end
end

always @(*)begin
  wb_transfer_done = (wb_state == WB_STATE_TRANSFER) & (wb_word_offset == wb_transfer_size-1) & i_wb_ack;
  wb_bus_err       = (i_wb_err | (req_state == REQ_STATE_BUS_ERR));
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
  if((req_state == REQ_STATE_CACHE) & req_we & req_hit)begin
    data_update_addr[mem_id] = `WORD_ADDR(req_addr_line | req_addr_word);
    data_update_we[mem_id]   = 1'b1;
    data_update_in[mem_id]   = 
      (i_ahb5_wdata & req_data_mask) | 
      (data_lookup_out[mem_id] & ~req_data_mask);
  end 
  else if(req_state == REQ_STATE_EVICT)begin
    data_update_addr[mem_id] = `WORD_ADDR(req_addr_line) + wb_word_offset;
    if(i_wb_ack)begin
      data_update_addr[mem_id] = `WORD_ADDR(req_addr_line) + wb_word_offset + 1;
    end
  end 
  else if((req_state == REQ_STATE_REFILL)     & i_wb_ack)begin
    data_update_addr[mem_id] = `WORD_ADDR(req_addr_line) + wb_word_offset;
    data_update_we[mem_id]   = 1'b1;
    data_update_in[mem_id]   = i_wb_rdata;
  end
  else if(flush_state == FLUSH_STATE_WRITEBACK)begin
    data_update_addr[mem_id] = {flush_line, 2'b00} + wb_word_offset;
    if(i_wb_ack)begin
      data_update_addr[mem_id] = {flush_line, 2'b00} + wb_word_offset + 1;
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
  if((req_state == REQ_STATE_CACHE) & req_hit & req_we & ~lookup_dirty[mem_id] & ~req_write_through)begin
    meta_update_addr[mem_id] = `LINE_ADDR(req_addr_line);
    meta_update_we[mem_id]   = 1'b1;
    meta_update_in[mem_id]   = meta_lookup_out[mem_id] | meta_dirty_mask;
  end 
  else if((req_state == REQ_STATE_LOOKUP) &
          ((conf_associativity == CONF_2_WAY_SET) |
           (conf_associativity == CONF_4_WAY_SET)))begin
    meta_update_addr[2'b00] = `LINE_ADDR(req_addr_line);
    meta_update_we[2'b00]   = 1'b1;
    meta_update_in[2'b00]   = 
      (meta_lookup_out[2'b00] & ~meta_repl_mask) |
      ({(lookup_repl[2'b00] + 6'b1), 2'b00} & meta_repl_mask);
  end 
  else if(req_state == REQ_STATE_UPDATE_META)begin
    meta_update_addr[mem_id] = `LINE_ADDR(req_addr_line); 
    meta_update_we[mem_id]   = 1'b1;
    meta_update_in[mem_id]   = req_addr_tag | meta_valid_mask;
  end 
  else if((flush_state == FLUSH_STATE_LOOKUP) & ~flush_line_dirty)begin
    meta_update_addr[0] = flush_line;
    meta_update_we[0]   = 1'b1;
    meta_update_in[0]   = 32'b0;
    meta_update_addr[1] = flush_line;
    meta_update_we[1]   = 1'b1;
    meta_update_in[1]   = 32'b0;
    meta_update_addr[2] = flush_line;
    meta_update_we[2]   = 1'b1;
    meta_update_in[2]   = 32'b0;
    meta_update_addr[3] = flush_line;
    meta_update_we[3]   = 1'b1;
    meta_update_in[3]   = 32'b0;
  end 
  else if(flush_state == FLUSH_STATE_UPDATE_META)begin
    meta_update_addr[mem_id] = flush_line; 
    meta_update_we[mem_id]   = 1'b1;
    meta_update_in[mem_id]   = 32'b0;
  end
end

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n) begin
    flush_state   <= FLUSH_STATE_IDLE;
    flush_pending <= 1'b1;
    flush_line    <= 9'b0;
  end else begin
    case (flush_state)
      FLUSH_STATE_IDLE:
        flush_state <= (flush_start) ? FLUSH_STATE_ADDR :
                                       FLUSH_STATE_IDLE;
      FLUSH_STATE_ADDR:
        flush_state <= FLUSH_STATE_LOOKUP;
      FLUSH_STATE_LOOKUP:
        flush_state <= (flush_writeback) ? FLUSH_STATE_WRITEBACK :
                       (flush_done)      ? FLUSH_STATE_IDLE :
                                           FLUSH_STATE_LOOKUP;
      FLUSH_STATE_WRITEBACK:
        flush_state <= (wb_bus_err)       ? FLUSH_STATE_ADDR : 
                       (wb_transfer_done) ? FLUSH_STATE_UPDATE_META :
                                            FLUSH_STATE_WRITEBACK;
      FLUSH_STATE_UPDATE_META:
        flush_state <= FLUSH_STATE_ADDR;
      default:
        flush_state <= FLUSH_STATE_IDLE;
    endcase

    if((flush_state == FLUSH_STATE_LOOKUP) & ~flush_line_dirty)
      flush_line <= flush_line + 1;

    if(i_flush | (|(conf_active ^ conf_new) & conf_cache_on))
      flush_pending <= 1'b1;
    
    if(flush_done)begin
      flush_pending <= 1'b0;
      flush_line    <= 9'b0;
    end
  end
end

always @(*) begin
  flush_start             = 1'b0;
  flush_line_dirty        = 1'b0;
  flush_line_dirty_mem_id = 2'b00;
  flush_done              = 1'b0;
  flush_writeback         = 1'b0;
  if(flush_state == FLUSH_STATE_IDLE)begin
    flush_start = flush_pending &
                  ((req_state == REQ_STATE_ADDR) |
                   (req_state == REQ_STATE_STALL) |
                   (req_state == REQ_STATE_BYPASS_TRANSFER));
  end else begin
    flush_line_dirty = lookup_dirty[0] |
                       lookup_dirty[1] |
                       lookup_dirty[2] |
                       lookup_dirty[3];
    flush_line_dirty_mem_id = (lookup_dirty[0] == 1'b1) ? 2'b00 :
                              (lookup_dirty[1] == 1'b1) ? 2'b01 :
                              (lookup_dirty[2] == 1'b1) ? 2'b10 :
                              (lookup_dirty[3] == 1'b1) ? 2'b11 : 
                              2'b00;
    flush_writeback = flush_line_dirty & 
                      (conf_write_policy == CONF_WRITE_BACK) &
                      ((req_state == REQ_STATE_ADDR) | 
                       (req_state == REQ_STATE_STALL));
    flush_done      = (flush_state == FLUSH_STATE_LOOKUP) & (flush_line == (128-1)) & ~flush_line_dirty;
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
  if(wb_state == WB_STATE_TRANSFER)begin
    o_wb_cyc   = 1'b1;
    o_wb_stb   = 1'b1;
    o_wb_we    = wb_transfer_we;
    o_wb_bte   = WB_BTE_LINEAR_BURST;
    o_wb_sel   = wb_transfer_byte_sel;
    
    if(wb_transfer_size > 1)begin
      o_wb_cti   = (wb_word_offset < (wb_transfer_size-1)) ? WB_CTI_INC_BURST_CYCLE : WB_CTI_END_BURST_CYCLE;
      o_wb_addr  = wb_transfer_base_addr | {wb_word_offset, 2'b00};
      if(wb_transfer_we)
        o_wb_wdata = data_update_out[mem_id];
    end else begin
      o_wb_cti   = WB_CTI_CLASSIC_CYCLE;
      o_wb_addr  = wb_transfer_base_addr;
      if(wb_transfer_we)  
        o_wb_wdata = i_ahb5_wdata;
    end
  end
end

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n)
    req_rdata <= 32'b0;
  else if((req_state == REQ_STATE_BYPASS_TRANSFER) & i_wb_ack)
    req_rdata <= i_wb_rdata;
end

always @(*) begin
  o_ahb5_ready = 
    (req_state == REQ_STATE_ADDR) |
    ((req_state == REQ_STATE_CACHE) & req_hit & ~req_write_through) |
    (req_state == REQ_STATE_BYPASS_RESPONSE);

  o_ahb5_rdata = 32'b0;
  if((req_state == REQ_STATE_CACHE) & req_hit & ~req_we)begin
    o_ahb5_rdata = data_lookup_out[mem_id] & req_data_mask;
  end
  else if((req_state == REQ_STATE_BYPASS_RESPONSE) & ~req_we)begin
    o_ahb5_rdata = req_rdata & req_data_mask;
  end
end

always @(posedge i_clk or negedge i_rst_n) begin
  if(~i_rst_n)
    o_ahb5_resp <= 1'b0;
  else
    o_ahb5_resp <= wb_bus_err & (flush_state != FLUSH_STATE_WRITEBACK);
end

endmodule