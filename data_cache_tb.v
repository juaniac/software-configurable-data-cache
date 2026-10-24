`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Testbench for data_cache.v
//
// Assumptions inferred from the DUT supplied with this request:
//   * AHB-like requests use i_ahb5_trans[1] == 1 for a valid transfer.
//   * A cache line contains four 32-bit words (16 bytes).
//   * The apparent address layout is {tag[18:0], bank[1:0], line[6:0], byte[3:0]}.
//   * The DUT's internal FSM registers are named cstate and wbstate, with the
//     encodings copied below. Update the coverage hooks if those names change.
//   * sdp_ram is a synchronous RAM. Prefer your real sdp_ram model/IP when
//     possible; sdp_ram_model.v is provided as an optional simulation model.
//
// This is a directed, coverage-oriented testbench rather than a formal proof.
// It deliberately checks bank isolation, high line-index addressing, writeback,
// cleanup, and response/error behaviour; those tests may expose existing DUT
// bugs and therefore are not guaranteed to pass against the original RTL.
// -----------------------------------------------------------------------------
module tb_data_cache;

  localparam integer CLK_PERIOD_NS       = 5;
  localparam integer MEM_WORDS           = 65536;
  localparam integer MAX_WAIT_CYCLES     = 6000;
  localparam integer MAX_CLEANUP_CYCLES  = 6000;

  // Main FSM encodings from the supplied data_cache RTL.
  localparam [3:0] ST_ADDR                 = 4'h0;
  localparam [3:0] ST_CACHE                = 4'h1;
  localparam [3:0] ST_LOOKUP               = 4'h2;
  localparam [3:0] ST_MEM_EVICT            = 4'h3;
  localparam [3:0] ST_MEM_WAIT             = 4'h4;
  localparam [3:0] ST_MEM_READ             = 4'h5;
  localparam [3:0] ST_UPDATE_META          = 4'h6;
  localparam [3:0] ST_REDO_ADDR            = 4'h7;
  localparam [3:0] ST_MEM_ERR              = 4'h8;
  localparam [3:0] ST_CLEANUP_INIT         = 4'h9;
  localparam [3:0] ST_CLEANUP_LOOKUP       = 4'hA;
  localparam [3:0] ST_CLEANUP_WRITEBACK    = 4'hB;
  localparam [3:0] ST_CLEANUP_UPDATE_META  = 4'hC;

  localparam [1:0] WB_ST_IDLE       = 2'h0;
  localparam [1:0] WB_ST_WDATA_WAIT = 2'h1;
  localparam [1:0] WB_ST_TRANSFER   = 2'h2;

  reg clk;
  reg rst_n;

  reg [31:0] ahb_addr;
  reg        ahb_we;
  reg [1:0]  ahb_trans;
  reg [2:0]  ahb_size;
  reg [31:0] ahb_wdata;
  wire [31:0]  ahb_rdata;
  wire         ahb_ready;
  wire         ahb_resp;

  wire         wb_cyc;
  wire         wb_stb;
  wire         wb_we;
  wire [1:0]   wb_bte;
  wire [2:0]   wb_cti;
  wire [3:0]   wb_sel;
  wire [31:0]  wb_addr;
  wire [31:0]  wb_wdata;
  reg [31:0] wb_rdata;
  reg        wb_ack;
  reg        wb_err;

  reg cleanup;

  data_cache dut (
    .i_clk       (clk),
    .i_rst_n     (rst_n),
    .i_ahb5_addr (ahb_addr),
    .i_ahb5_we   (ahb_we),
    .i_ahb5_trans(ahb_trans),
    .i_ahb5_size (ahb_size),
    .i_ahb5_wdata(ahb_wdata),
    .o_ahb5_rdata(ahb_rdata),
    .o_ahb5_ready(ahb_ready),
    .o_ahb5_resp (ahb_resp),
    .o_wb_cyc    (wb_cyc),
    .o_wb_stb    (wb_stb),
    .o_wb_we     (wb_we),
    .o_wb_bte    (wb_bte),
    .o_wb_cti    (wb_cti),
    .o_wb_sel    (wb_sel),
    .o_wb_addr   (wb_addr),
    .o_wb_wdata  (wb_wdata),
    .i_wb_rdata  (wb_rdata),
    .i_wb_ack    (wb_ack),
    .i_wb_err    (wb_err),
    .i_cleanup   (cleanup)
  );

  initial begin
    $dumpfile("data_cache.vcd");
    $dumpvars(0, dut);

    // Cache lookup results
    $dumpvars(0, dut.lookup_tag[0]);
    $dumpvars(0, dut.lookup_tag[1]);
    $dumpvars(0, dut.lookup_tag[2]);
    $dumpvars(0, dut.lookup_tag[3]);

    $dumpvars(0, dut.lookup_dirty[0]);
    $dumpvars(0, dut.lookup_dirty[1]);
    $dumpvars(0, dut.lookup_dirty[2]);
    $dumpvars(0, dut.lookup_dirty[3]);

    $dumpvars(0, dut.lookup_valid[0]);
    $dumpvars(0, dut.lookup_valid[1]);
    $dumpvars(0, dut.lookup_valid[2]);
    $dumpvars(0, dut.lookup_valid[3]);

    $dumpvars(0, dut.lookup_hit[0]);
    $dumpvars(0, dut.lookup_hit[1]);
    $dumpvars(0, dut.lookup_hit[2]);
    $dumpvars(0, dut.lookup_hit[3]);

    // Metadata RAM control and data
    $dumpvars(0, dut.meta_update_we[0]);
    $dumpvars(0, dut.meta_update_we[1]);
    $dumpvars(0, dut.meta_update_we[2]);
    $dumpvars(0, dut.meta_update_we[3]);

    $dumpvars(0, dut.meta_update_addr[0]);
    $dumpvars(0, dut.meta_update_addr[1]);
    $dumpvars(0, dut.meta_update_addr[2]);
    $dumpvars(0, dut.meta_update_addr[3]);

    $dumpvars(0, dut.meta_update_in[0]);
    $dumpvars(0, dut.meta_update_in[1]);
    $dumpvars(0, dut.meta_update_in[2]);
    $dumpvars(0, dut.meta_update_in[3]);

    $dumpvars(0, dut.meta_update_out[0]);
    $dumpvars(0, dut.meta_update_out[1]);
    $dumpvars(0, dut.meta_update_out[2]);
    $dumpvars(0, dut.meta_update_out[3]);

    $dumpvars(0, dut.meta_lookup_addr[0]);
    $dumpvars(0, dut.meta_lookup_addr[1]);
    $dumpvars(0, dut.meta_lookup_addr[2]);
    $dumpvars(0, dut.meta_lookup_addr[3]);

    $dumpvars(0, dut.meta_lookup_out[0]);
    $dumpvars(0, dut.meta_lookup_out[1]);
    $dumpvars(0, dut.meta_lookup_out[2]);
    $dumpvars(0, dut.meta_lookup_out[3]);

    $dumpvars(0, dut.meta_lookup_out_[0]);
    $dumpvars(0, dut.meta_lookup_out_[1]);
    $dumpvars(0, dut.meta_lookup_out_[2]);
    $dumpvars(0, dut.meta_lookup_out_[3]);

    $dumpvars(0, dut.meta_fwd_valid[0]);
    $dumpvars(0, dut.meta_fwd_valid[1]);
    $dumpvars(0, dut.meta_fwd_valid[2]);
    $dumpvars(0, dut.meta_fwd_valid[3]);

    $dumpvars(0, dut.meta_fwd_data[0]);
    $dumpvars(0, dut.meta_fwd_data[1]);
    $dumpvars(0, dut.meta_fwd_data[2]);
    $dumpvars(0, dut.meta_fwd_data[3]);

    // Data RAM control and data
    $dumpvars(0, dut.data_update_we[0]);
    $dumpvars(0, dut.data_update_we[1]);
    $dumpvars(0, dut.data_update_we[2]);
    $dumpvars(0, dut.data_update_we[3]);

    $dumpvars(0, dut.data_update_addr[0]);
    $dumpvars(0, dut.data_update_addr[1]);
    $dumpvars(0, dut.data_update_addr[2]);
    $dumpvars(0, dut.data_update_addr[3]);

    $dumpvars(0, dut.data_update_in[0]);
    $dumpvars(0, dut.data_update_in[1]);
    $dumpvars(0, dut.data_update_in[2]);
    $dumpvars(0, dut.data_update_in[3]);

    $dumpvars(0, dut.data_update_out[0]);
    $dumpvars(0, dut.data_update_out[1]);
    $dumpvars(0, dut.data_update_out[2]);
    $dumpvars(0, dut.data_update_out[3]);

    $dumpvars(0, dut.data_lookup_addr[0]);
    $dumpvars(0, dut.data_lookup_addr[1]);
    $dumpvars(0, dut.data_lookup_addr[2]);
    $dumpvars(0, dut.data_lookup_addr[3]);

    $dumpvars(0, dut.data_lookup_out[0]);
    $dumpvars(0, dut.data_lookup_out[1]);
    $dumpvars(0, dut.data_lookup_out[2]);
    $dumpvars(0, dut.data_lookup_out[3]);

    $dumpvars(0, dut.data_lookup_out_[0]);
    $dumpvars(0, dut.data_lookup_out_[1]);
    $dumpvars(0, dut.data_lookup_out_[2]);
    $dumpvars(0, dut.data_lookup_out_[3]);

    $dumpvars(0, dut.data_fwd_valid[0]);
    $dumpvars(0, dut.data_fwd_valid[1]);
    $dumpvars(0, dut.data_fwd_valid[2]);
    $dumpvars(0, dut.data_fwd_valid[3]);

    $dumpvars(0, dut.data_fwd_data[0]);
    $dumpvars(0, dut.data_fwd_data[1]);
    $dumpvars(0, dut.data_fwd_data[2]);
    $dumpvars(0, dut.data_fwd_data[3]);
end

  // Clock generation.
  initial clk = 1'b0;
  always #(CLK_PERIOD_NS/2) clk = ~clk;

  // ---------------------------------------------------------------------------
  // Backing memory / Wishbone slave model
  // ---------------------------------------------------------------------------
  // The cache uses 32-bit word transfers. The model maps byte addresses through
  // address bits [17:2], giving 64K words for directed tests. Keep test addresses
  // in this region so that addresses don't alias in the model.
  reg [31:0] backing_mem [0:MEM_WORDS-1];

  integer wb_read_beats;
  integer wb_write_beats;
  integer wb_error_count;
  integer wb_fixed_latency;
  reg   wb_random_latency;
  reg   wb_inject_error_next;

  reg        wb_pending;
  reg [31:0] wb_pending_addr;
  reg [31:0] wb_pending_wdata;
  reg [3:0]  wb_pending_sel;
  reg        wb_pending_we;
  reg        wb_pending_error;
  integer      wb_pending_delay;

  function integer memory_index;
    input [31:0] byte_addr;
    begin
      memory_index = byte_addr[17:2];
    end
  endfunction

  function [31:0] read_backing_word;
    input [31:0] byte_addr;
    begin
      read_backing_word = backing_mem[memory_index(byte_addr)];
    end
  endfunction

  function [31:0] apply_byte_select;
    input [31:0] old_word;
    input [31:0] new_word;
    input [3:0] byte_sel;
    reg [31:0] merged;
    integer lane;
    begin
      merged = old_word;
      for (lane = 0; lane < 4; lane = lane + 1) begin
        if (byte_sel[lane])
          merged[lane*8 +: 8] = new_word[lane*8 +: 8];
      end
      apply_byte_select = merged;
    end
  endfunction

  function [31:0] make_addr;
    input [18:0] tag;
    input [1:0] bank;
    input [6:0] line_index;
    input [3:0] byte_offset;
    begin
      make_addr = {tag, bank, line_index, byte_offset};
    end
  endfunction

  // Model accepts a beat, optionally waits, then returns a one-cycle ACK or ERR.
  // Outputs are driven on the falling edge so they are stable at the DUT's next
  // rising edge. Address/data are captured at the start of each beat as required
  // by a conventional Wishbone slave.
  integer wb_memory_idx;

  always @(negedge clk) begin : wishbone_slave_model
    if (!rst_n) begin
      wb_rdata           = 32'b0;
      wb_ack             = 1'b0;
      wb_err             = 1'b0;
      wb_pending         = 1'b0;
      wb_pending_delay   = 0;
      wb_pending_error   = 1'b0;
      wb_pending_addr    = 32'b0;
      wb_pending_wdata   = 32'b0;
      wb_pending_sel     = 4'b0;
      wb_pending_we      = 1'b0;
    end else begin
      wb_ack = 1'b0;
      wb_err = 1'b0;

      if (wb_pending) begin
        if (wb_pending_delay > 0) begin
          wb_pending_delay = wb_pending_delay - 1;
        end else begin
          wb_memory_idx = memory_index(wb_pending_addr);
          if (wb_pending_error) begin
            wb_err = 1'b1;
            wb_error_count = wb_error_count + 1;
          end else begin
            wb_ack = 1'b1;
            if (wb_pending_we) begin
              backing_mem[wb_memory_idx] = apply_byte_select(
                backing_mem[wb_memory_idx], wb_pending_wdata, wb_pending_sel
              );
              wb_write_beats = wb_write_beats + 1;
            end else begin
              wb_rdata = backing_mem[wb_memory_idx];
              wb_read_beats = wb_read_beats + 1;
            end
          end
          wb_pending = 1'b0;
        end
      end else if (wb_cyc && wb_stb) begin
        wb_pending_addr  = wb_addr;
        wb_pending_wdata = wb_wdata;
        wb_pending_sel   = wb_sel;
        wb_pending_we    = wb_we;
        wb_pending_error = wb_inject_error_next;
        wb_inject_error_next = 1'b0;
        if (wb_random_latency)
          wb_pending_delay = ($random & 32'h7fffffff) % 4;
        else
          wb_pending_delay = wb_fixed_latency;
        wb_pending = 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Lightweight FSM coverage hooks. These intentionally use hierarchical
  // references because the request is specifically to cover the states in this
  // implementation. If the RTL is renamed/refactored, update this section.
  // ---------------------------------------------------------------------------
  reg [15:0] main_state_seen;
  reg [3:0]  wb_state_seen;
  integer checks_failed;
  integer checks_passed;

  always @(posedge clk) begin
    if (rst_n) begin
      if ((^dut.cstate) !== 1'bx)
        main_state_seen[dut.cstate] = 1'b1;
      if ((^dut.wbstate) !== 1'bx)
        wb_state_seen[dut.wbstate] = 1'b1;
    end
  end

  task check;
    input condition;
    input [8*256-1:0] message;

    begin : check_body
      if (condition !== 1'b1) begin
        checks_failed = checks_failed + 1;
        $display("\033[31m[FAIL %0t] %0s\033[0m", $time, message);
      end else begin
        checks_passed = checks_passed + 1;
        $display("\033[32m[PASS %0t] %0s\033[0m", $time, message);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Reusable AHB-like request tasks
  // ---------------------------------------------------------------------------
  task wait_for_addr_state;
    output reg success;

    integer cycles;
    begin : wait_for_addr_state_body
      success = 1'b0;
      cycles = 0;
      while ((dut.cstate !== ST_ADDR) && (cycles < MAX_WAIT_CYCLES)) begin
        @(negedge clk);
        cycles = cycles + 1;
      end
      if (dut.cstate === ST_ADDR)
        success = 1'b1;
      else
        check(1'b0, "Timed out waiting for CSTATE_ADDR before AHB request");
    end
  endtask

  task ahb_start_request;
    input [31:0] address;
    input is_write;
    input [2:0] size;
    input [31:0] write_data;
    output reg success;

    reg addr_ready;
    begin : ahb_start_request_body
      wait_for_addr_state(addr_ready);
      if (!addr_ready) begin
        success = 1'b0;
        disable ahb_start_request_body;
      end

      // Leave a full falling-edge setup interval before the accepting rising edge.
      @(negedge clk);
      ahb_addr  = address;
      ahb_we    = is_write;
      ahb_size  = size;
      ahb_wdata = write_data;
      ahb_trans = 2'b10; // NONSEQ / valid transfer for this DUT

      @(posedge clk); // request accepted in CSTATE_ADDR
      @(negedge clk);
      ahb_trans = 2'b00; // no pipelined next request; keep other fields stable
      success = 1'b1;
    end
  endtask

  task ahb_wait_for_hit;
    output reg [31:0] read_data;
    output reg success;

    integer cycles;
    begin : ahb_wait_for_hit_body
      read_data = 32'b0;
      success = 1'b0;
      for (cycles = 0; cycles < MAX_WAIT_CYCLES; cycles = cycles + 1) begin
        // Check before waiting: a cache hit may be ready on the first negedge
        // after ahb_start_request returns.
        if ((dut.cstate === ST_CACHE) && (dut.hit === 1'b1) && (ahb_ready === 1'b1)) begin
          read_data = ahb_rdata;
          @(posedge clk); // let the hit/write complete
          @(negedge clk);
          success = 1'b1;
          disable ahb_wait_for_hit_body;
        end
        @(negedge clk);
      end
      check(1'b0, "Timed out waiting for a cache hit/completed AHB request");
    end
  endtask

  task ahb_transfer;
    input [31:0] address;
    input is_write;
    input [2:0] size;
    input [31:0] write_data;
    output reg [31:0] read_data;
    output reg success;

    reg start_ok;
    begin : ahb_transfer_body
      ahb_start_request(address, is_write, size, write_data, start_ok);
      if (!start_ok) begin
        read_data = 32'b0;
        success = 1'b0;
        disable ahb_transfer_body;
      end
      ahb_wait_for_hit(read_data, success);
    end
  endtask

  task cpu_read_word;
    input [31:0] address;
    output reg [31:0] value;
    output reg success;
    input [8*256-1:0] label;

    begin : cpu_read_word_body
      ahb_transfer(address, 1'b0, 3'b010, 32'b0, value, success);
      check(success, label);
    end
  endtask

  task cpu_write_word;
    input [31:0] address;
    input [31:0] value;
    output reg success;
    input [8*256-1:0] label;

    reg [31:0] unused_data;
    begin : cpu_write_word_body
      ahb_transfer(address, 1'b1, 3'b010, value, unused_data, success);
      check(success, label);
    end
  endtask

  task cpu_write_byte;
    input [31:0] address;
    input [7:0] value;
    output reg success;

    reg [31:0] shifted_data;
    reg [31:0] unused_data;
    begin : cpu_write_byte_body
      // This matches the lane-aligned write-data convention used by the DUT's
      // (wdata & byte_mask) merge. Adjust if your AHB bridge uses another format.
      shifted_data = {24'b0, value} << (8 * address[1:0]);
      ahb_transfer(address, 1'b1, 3'b000, shifted_data, unused_data, success);
      check(success, "byte store completed");
    end
  endtask

  task cpu_read_byte;
    input [31:0] address;
    output reg [7:0] value;
    output reg success;

    reg [31:0] raw_data;
    reg [31:0] shifted_data;
    begin : cpu_read_byte_body
      ahb_transfer(address, 1'b0, 3'b000, 32'b0, raw_data, success);
      shifted_data = raw_data >> (8 * address[1:0]);
      value = shifted_data[7:0];
      check(success, "byte load completed");
    end
  endtask

  task cpu_write_halfword;
    input [31:0] address;
    input [15:0] value;
    output reg success;

    reg [31:0] shifted_data;
    reg [31:0] unused_data;
    begin : cpu_write_halfword_body
      shifted_data = {16'b0, value} << (address[1] ? 16 : 0);
      ahb_transfer(address, 1'b1, 3'b001, shifted_data, unused_data, success);
      check(success, "halfword store completed");
    end
  endtask

  task cpu_read_halfword;
    input [31:0] address;
    output reg [15:0] value;
    output reg success;

    reg [31:0] raw_data;
    reg [31:0] shifted_data;
    begin : cpu_read_halfword_body
      ahb_transfer(address, 1'b0, 3'b001, 32'b0, raw_data, success);
      shifted_data = raw_data >> (address[1] ? 16 : 0);
      value = shifted_data[15:0];
      check(success, "halfword load completed");
    end
  endtask

  task expect_wishbone_error;
    input [31:0] address;
    output reg success;

    reg start_ok;
    integer cycles;
    begin : expect_wishbone_error_body
      success = 1'b0;
      ahb_start_request(address, 1'b0, 3'b010, 32'b0, start_ok);
      if (!start_ok)
        disable expect_wishbone_error_body;

      for (cycles = 0; cycles < MAX_WAIT_CYCLES; cycles = cycles + 1) begin
        if (dut.cstate === ST_MEM_ERR) begin
          check(ahb_resp === 1'b1, "AHB response indicates the Wishbone error for 1 cycle");
          @(posedge clk);
          @(negedge clk);
          check(ahb_resp === 1'b1, "AHB response indicates the Wishbone error for 2 cycles");
          success = 1'b1;
          disable expect_wishbone_error_body;
        end
        @(negedge clk);
      end
      check(1'b0, "Timed out waiting for CSTATE_MEM_ERR after injected Wishbone error");
    end
  endtask

  task request_cleanup;
    output reg success;

    integer cycles;
    begin : request_cleanup_body
      success = 1'b0;
      @(negedge clk);
      cleanup = 1'b1;
      @(negedge clk);
      cleanup = 1'b0;

      for (cycles = 0; cycles < MAX_CLEANUP_CYCLES; cycles = cycles + 1) begin
        // Avoid mistaking the initial, not-yet-latched cleanup request for done.
        if ((cycles > 20) && (dut.cstate === ST_ADDR) &&
            (dut.cleanup_pending === 1'b0)) begin
          success = 1'b1;
          disable request_cleanup_body;
        end
        @(negedge clk);
      end
      check(1'b0, "Timed out waiting for cache cleanup to finish");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Directed tests
  // ---------------------------------------------------------------------------
  reg [31:0] base_addr;
  reg [31:0] expected_base_word;
  reg [31:0] bank_addr [0:3];

  task test_reset_and_idle;
    begin
      check(dut.cstate === ST_ADDR, "reset leaves main FSM in CSTATE_ADDR");
      check(wb_cyc === 1'b0 && wb_stb === 1'b0, "Wishbone is idle after reset");
      check(ahb_ready === 1'b1, "AHB ready is asserted in address state");
    end
  endtask

  task test_clean_miss_hit_and_refill_words;
    reg [31:0] got;
    reg [31:0] address;
    reg ok;
    integer before_reads;
    integer word_no;
    begin
      $display("\n=== TEST: clean miss, burst refill, hits, word ordering ===");
      base_addr = make_addr(19'h00001, 2'b00, 7'd0, 4'd0);
      expected_base_word = read_backing_word(base_addr);
      before_reads = wb_read_beats;

      cpu_read_word(base_addr, got, ok, "initial clean miss");
      check(got === expected_base_word,
            "miss returns backing-memory word");
      check((wb_read_beats - before_reads) == 4,
            "a line miss performs four acknowledged Wishbone read beats");

      before_reads = wb_read_beats;
      for (word_no = 0; word_no < 4; word_no = word_no + 1) begin
        address = base_addr + (word_no * 4);
        cpu_read_word(address, got, ok, "refilled word");
        check(got === read_backing_word(address),
              "refilled word has correct data");
      end
      check(wb_read_beats == before_reads,
            "reads of all words in the resident line do not access Wishbone");
    end
  endtask

  task test_byte_and_halfword_stores;
    reg [31:0] got_word;
    reg [7:0]  got_byte;
    reg [15:0] got_half;
    reg [7:0]  byte_value;
    reg ok;
    integer lane;
    begin
      $display("\n=== TEST: byte/halfword write masks and dirty tracking ===");
      expected_base_word = read_backing_word(base_addr);

      for (lane = 0; lane < 4; lane = lane + 1) begin
        byte_value = 8'hA1 + lane;
        cpu_write_byte(base_addr + lane, byte_value, ok);
        case (lane)
          0: expected_base_word[7:0]   = byte_value;
          1: expected_base_word[15:8]  = byte_value;
          2: expected_base_word[23:16] = byte_value;
          3: expected_base_word[31:24] = byte_value;
        endcase
        cpu_read_word(base_addr, got_word, ok, "verify byte lane");
        check(got_word === expected_base_word,
              "byte lane merge");
        cpu_read_byte(base_addr + lane, got_byte, ok);
        check(got_byte === byte_value,
              "byte lane readback");
      end

      cpu_write_halfword(base_addr + 2, 16'hBEEF, ok);
      expected_base_word[31:16] = 16'hBEEF;
      cpu_read_word(base_addr, got_word, ok, "verify upper-halfword store");
      check(got_word === expected_base_word,
            "halfword merge");
      cpu_read_halfword(base_addr + 2, got_half, ok);
      check(got_half === 16'hBEEF,
            "halfword readback");
    end
  endtask

  task test_dirty_eviction;
    reg [31:0] new_addr;
    reg [31:0] got;
    reg [31:0] expected_old_word;
    reg ok;
    integer before_writes;
    integer before_reads;
    begin
      $display("\n=== TEST: dirty eviction writes a victim line back ===");
      expected_old_word = expected_base_word;
      // A conflicting tag with the same bank and line index should evict base_addr.
      new_addr = make_addr(19'h00002, 2'b00, 7'd0, 4'd0);
      before_writes = wb_write_beats;
      before_reads  = wb_read_beats;

      cpu_write_word(base_addr, 32'hCAFE_1234, ok, "make victim dirty");
      expected_old_word = 32'hCAFE_1234;
      cpu_read_word(new_addr, got, ok, "read conflicting tag after dirty eviction");
      check(got === read_backing_word(new_addr),
            "replacement line data matches backing memory");
      check((wb_write_beats - before_writes) >= 4,
            "dirty eviction generates four Wishbone write beats");
      check(read_backing_word(base_addr) === expected_old_word,
            "victim word reaches backing memory");
      check((wb_read_beats - before_reads) >= 4,
            "replacement line is fetched from backing memory");
    end
  endtask

  task test_four_bank_isolation;
    reg [31:0] got;
    reg ok;
    integer bank;
    integer before_reads;
    begin
      $display("\n=== TEST: four-bank isolation ===");
      // Same tag/index but different bank bits should represent four independent
      // resident lines under the apparent address layout.
      for (bank = 0; bank < 4; bank = bank + 1)
        bank_addr[bank] = make_addr(19'h0000A, bank[1:0], 7'd0, 4'd0);

      before_reads = wb_read_beats;
      for (bank = 0; bank < 4; bank = bank + 1) begin
        cpu_read_word(bank_addr[bank], got, ok, "first read bank");
        check(got === read_backing_word(bank_addr[bank]),
              "bank returns its own data");
      end
      check((wb_read_beats - before_reads) == 16,
            "one cold line in each bank causes four bursts (16 read beats)");

      before_reads = wb_read_beats;
      for (bank = 0; bank < 4; bank = bank + 1) begin
        cpu_read_word(bank_addr[bank], got, ok, "second read bank");
        check(got === read_backing_word(bank_addr[bank]),
              "bank remains isolated");
      end
      check(wb_read_beats == before_reads,
            "second reads of all four resident banks cause no extra refills");
    end
  endtask

  task test_high_line_index_addressing;
    reg [31:0] address;
    reg [31:0] got;
    reg ok;
    begin
      $display("\n=== TEST: nonzero/high line-index address arithmetic ===");
      address = make_addr(19'h00011, 2'b00, 7'd40, 4'd0);
      cpu_read_word(address, got, ok, "read line index 40");
      check(got === read_backing_word(address),
            "line-index 40 data/addressing");
    end
  endtask

  task test_variable_wishbone_latency;
    reg [31:0] address;
    reg [31:0] got;
    reg ok;
    integer before_reads;
    begin
      $display("\n=== TEST: Wishbone acknowledgement stalls ===");
      address = make_addr(19'h00015, 2'b00, 7'd3, 4'd0);
      before_reads = wb_read_beats;
      wb_random_latency = 1'b1;
      cpu_read_word(address, got, ok, "read with randomized Wishbone latency");
      wb_random_latency = 1'b0;
      check(got === read_backing_word(address),
            "delayed refill data");
      check((wb_read_beats - before_reads) == 4,
            "Wishbone wait states neither drop nor duplicate refill beats");
    end
  endtask

  task test_wishbone_error_path;
    reg [31:0] address;
    reg ok;
    integer before_errors;
    begin
      $display("\n=== TEST: Wishbone error and controller recovery ===");
      address = make_addr(19'h00123, 2'b00, 7'd48, 4'd0);
      before_errors = wb_error_count;
      wb_inject_error_next = 1'b1;
      expect_wishbone_error(address, ok);
      check(ok, "injected Wishbone error reaches CSTATE_MEM_ERR");
      check(wb_error_count == before_errors + 1,
            "Wishbone slave model injected exactly one error");
      check(dut.cstate === ST_ADDR,
            "controller returns to CSTATE_ADDR after memory error");
    end
  endtask

  task test_cleanup_writeback;
    reg [31:0] address;
    reg [31:0] got;
    reg [31:0] expected_after_store;
    reg ok;
    integer before_writes;
    begin
      $display("\n=== TEST: cleanup scans lines and writes back dirty data ===");
      address = make_addr(19'h00055, 2'b00, 7'd8, 4'd0);
      cpu_read_word(address, got, ok, "load line to be cleaned");
      check(got === read_backing_word(address), "cleanup test line initially matches backing memory");

      expected_after_store = 32'hD00D_F00D;
      cpu_write_word(address, expected_after_store, ok, "dirty line before cleanup");
      before_writes = wb_write_beats;
      request_cleanup(ok);
      check(ok, "cleanup request completes");
      check((wb_write_beats - before_writes) >= 4,
            "cleanup writes back at least one four-word dirty line");
      check(read_backing_word(address) === expected_after_store,
            "cleanup persisted dirty word");
      check(dut.cleanup_pending === 1'b0,
            "cleanup_pending is cleared when cleanup completes");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Coverage summary
  // ---------------------------------------------------------------------------
  task report_main_state;
    input integer state_id;
    input [8*256-1:0] state_name;

    begin : report_main_state_body
      check(main_state_seen[state_id] === 1'b1,
            state_name);
    end
  endtask

  task report_wb_state;
    input integer state_id;
    input [8*256-1:0] state_name;

    begin : report_wb_state_body
      check(wb_state_seen[state_id] === 1'b1,
            state_name);
    end
  endtask

  task report_state_coverage;
    begin
      $display("\n=== MAIN FSM STATE COVERAGE ===");
      report_main_state(ST_ADDR,                "CSTATE_ADDR");
      report_main_state(ST_CACHE,               "CSTATE_CACHE");
      report_main_state(ST_LOOKUP,              "CSTATE_LOOKUP");
      report_main_state(ST_MEM_EVICT,            "CSTATE_MEM_EVICT");
      report_main_state(ST_MEM_WAIT,             "CSTATE_MEM_WAIT");
      report_main_state(ST_MEM_READ,             "CSTATE_MEM_READ");
      report_main_state(ST_UPDATE_META,          "CSTATE_UPDATE_META");
      report_main_state(ST_REDO_ADDR,            "CSTATE_REDO_ADDR");
      report_main_state(ST_MEM_ERR,              "CSTATE_MEM_ERR");
      report_main_state(ST_CLEANUP_INIT,         "CSTATE_CLEANUP_INIT");
      report_main_state(ST_CLEANUP_LOOKUP,       "CSTATE_CLEANUP_LOOKUP");
      report_main_state(ST_CLEANUP_WRITEBACK,    "CSTATE_CLEANUP_WRITEBACK");
      report_main_state(ST_CLEANUP_UPDATE_META,  "CSTATE_CLEANUP_UPDATE_META");

      $display("\n=== WISHBONE FSM STATE COVERAGE ===");
      report_wb_state(WB_ST_IDLE,       "WBSTATE_IDLE");
      report_wb_state(WB_ST_WDATA_WAIT, "WBSTATE_WDATA_WAIT");
      report_wb_state(WB_ST_TRANSFER,   "WBSTATE_TRANSFER");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  integer init_i;
  initial begin
    rst_n = 1'b0;
    ahb_addr = 32'b0;
    ahb_we = 1'b0;
    ahb_trans = 2'b00;
    ahb_size = 3'b010;
    ahb_wdata = 32'b0;
    cleanup = 1'b0;

    wb_rdata = 32'b0;
    wb_ack = 1'b0;
    wb_err = 1'b0;
    wb_read_beats = 0;
    wb_write_beats = 0;
    wb_error_count = 0;
    wb_fixed_latency = 1;
    wb_random_latency = 1'b0;
    wb_inject_error_next = 1'b0;
    wb_pending = 1'b0;
    wb_pending_addr = 32'b0;
    wb_pending_wdata = 32'b0;
    wb_pending_sel = 4'b0;
    wb_pending_we = 1'b0;
    wb_pending_error = 1'b0;
    wb_pending_delay = 0;
    main_state_seen = 16'b0;
    wb_state_seen = 4'b0;
    checks_failed = 0;
    checks_passed = 0;
    base_addr = 32'b0;
    expected_base_word = 32'b0;

    // Deterministic memory pattern catches swapped words and address errors.
    for (init_i = 0; init_i < MEM_WORDS; init_i = init_i + 1)
      backing_mem[init_i] = 32'hA500_0000 ^ (init_i * 32'h0000_1021);

    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (3) @(negedge clk);

    test_reset_and_idle();
    test_clean_miss_hit_and_refill_words();
    test_byte_and_halfword_stores();
    test_dirty_eviction();
    test_four_bank_isolation();
    test_high_line_index_addressing();
    test_variable_wishbone_latency();
    test_wishbone_error_path();
    test_cleanup_writeback();

    report_state_coverage();

    $display("\n=== SUMMARY ===");
    $display("Wishbone read beats : %0d", wb_read_beats);
    $display("Wishbone write beats: %0d", wb_write_beats);
    $display("Wishbone errors     : %0d", wb_error_count);
    $display("Checks passed       : %0d", checks_passed);
    $display("Checks failed       : %0d", checks_failed);
    if (checks_failed == 0)
      $display("TESTBENCH RESULT: PASS");
    else
      $display("TESTBENCH RESULT: FAIL (%0d checks failed)", checks_failed);
    $finish;
  end

  // Global watchdog in case an accidental testbench bug deadlocks the sequence.
  initial begin
    #(CLK_PERIOD_NS * 1000000);
    $display("[FATAL] Global simulation watchdog expired");
    $finish;
  end

endmodule