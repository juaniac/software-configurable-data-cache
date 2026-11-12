// `timescale 1ns/1ps

// // -----------------------------------------------------------------------------
// // Testbench for data_cache.v
// //
// // Assumptions inferred from the DUT supplied with this request:
// //   * AHB-like requests use i_ahb5_trans[1] == 1 for a valid transfer.
// //   * A cache line contains four 32-bit words (16 bytes).
// //   * The apparent address layout is {tag[18:0], bank[1:0], line[6:0], byte[3:0]}.
// //   * The DUT's internal FSM registers are named req_state and wb_state, with the
// //     encodings copied below. Update the coverage hooks if those names change.
// //   * sdp_ram is a synchronous RAM. Prefer your real sdp_ram model/IP when
// //     possible; sdp_ram_model.v is provided as an optional simulation model.
// //
// // This is a directed, coverage-oriented testbench rather than a formal proof.
// // It deliberately checks bank isolation, high line-index addressing, writeback,
// // cleanup, and response/error behaviour; those tests may expose existing DUT
// // bugs and therefore are not guaranteed to pass against the original RTL.
// // -----------------------------------------------------------------------------
// module tb_data_cache;

//   localparam integer CLK_PERIOD_NS       = 5;
//   localparam integer MEM_WORDS           = 65536;
//   localparam integer MAX_WAIT_CYCLES     = 6000;
//   localparam integer MAX_CLEANUP_CYCLES  = 6000;

//   // Main FSM encodings from the supplied data_cache RTL.
//   localparam [3:0] ST_ADDR                 = 4'h0;
//   localparam [3:0] ST_CACHE                = 4'h1;
//   localparam [3:0] ST_LOOKUP               = 4'h2;
//   localparam [3:0] ST_MEM_EVICT            = 4'h3;
//   localparam [3:0] ST_MEM_WAIT             = 4'h4;
//   localparam [3:0] ST_MEM_READ             = 4'h5;
//   localparam [3:0] ST_UPDATE_META          = 4'h6;
//   localparam [3:0] ST_REDO_ADDR            = 4'h7;
//   localparam [3:0] ST_MEM_ERR              = 4'h8;

//   localparam [1:0] WB_ST_IDLE       = 2'h0;
//   localparam [1:0] WB_ST_WDATA_WAIT = 2'h1;
//   localparam [1:0] WB_ST_TRANSFER   = 2'h2;

//   reg clk;
//   reg rst_n;

//   reg [31:0] ahb_addr;
//   reg        ahb_we;
//   reg [1:0]  ahb_trans;
//   reg [2:0]  ahb_size;
//   reg [31:0] ahb_wdata;
//   wire [31:0]  ahb_rdata;
//   wire         ahb_ready;
//   wire         ahb_resp;

//   wire         wb_cyc;
//   wire         wb_stb;
//   wire         wb_we;
//   wire [1:0]   wb_bte;
//   wire [2:0]   wb_cti;
//   wire [3:0]   wb_sel;
//   wire [31:0]  wb_addr;
//   wire [31:0]  wb_wdata;
//   reg [31:0] wb_rdata;
//   reg        wb_ack;
//   reg        wb_err;

//   reg cleanup;

//   data_cache dut (
//     .i_clk       (clk),
//     .i_rst_n     (rst_n),
//     .i_ahb5_addr (ahb_addr),
//     .i_ahb5_we   (ahb_we),
//     .i_ahb5_trans(ahb_trans),
//     .i_ahb5_size (ahb_size),
//     .i_ahb5_wdata(ahb_wdata),
//     .o_ahb5_rdata(ahb_rdata),
//     .o_ahb5_ready(ahb_ready),
//     .o_ahb5_resp (ahb_resp),
//     .o_wb_cyc    (wb_cyc),
//     .o_wb_stb    (wb_stb),
//     .o_wb_we     (wb_we),
//     .o_wb_bte    (wb_bte),
//     .o_wb_cti    (wb_cti),
//     .o_wb_sel    (wb_sel),
//     .o_wb_addr   (wb_addr),
//     .o_wb_wdata  (wb_wdata),
//     .i_wb_rdata  (wb_rdata),
//     .i_wb_ack    (wb_ack),
//     .i_wb_err    (wb_err),
//     .i_flush     (cleanup),
//     .i_cache_on  (1'b1)
//   );

//   initial begin
//     $dumpfile("data_cache.vcd");
//     $dumpvars(0, dut);

//     // Cache lookup results
//     $dumpvars(0, dut.lookup_tag[0]);
//     $dumpvars(0, dut.lookup_tag[1]);
//     $dumpvars(0, dut.lookup_tag[2]);
//     $dumpvars(0, dut.lookup_tag[3]);

//     $dumpvars(0, dut.lookup_dirty[0]);
//     $dumpvars(0, dut.lookup_dirty[1]);
//     $dumpvars(0, dut.lookup_dirty[2]);
//     $dumpvars(0, dut.lookup_dirty[3]);

//     $dumpvars(0, dut.lookup_valid[0]);
//     $dumpvars(0, dut.lookup_valid[1]);
//     $dumpvars(0, dut.lookup_valid[2]);
//     $dumpvars(0, dut.lookup_valid[3]);

//     $dumpvars(0, dut.lookup_hit[0]);
//     $dumpvars(0, dut.lookup_hit[1]);
//     $dumpvars(0, dut.lookup_hit[2]);
//     $dumpvars(0, dut.lookup_hit[3]);

//     // Metadata RAM control and data
//     $dumpvars(0, dut.meta_update_we[0]);
//     $dumpvars(0, dut.meta_update_we[1]);
//     $dumpvars(0, dut.meta_update_we[2]);
//     $dumpvars(0, dut.meta_update_we[3]);

//     $dumpvars(0, dut.meta_update_addr[0]);
//     $dumpvars(0, dut.meta_update_addr[1]);
//     $dumpvars(0, dut.meta_update_addr[2]);
//     $dumpvars(0, dut.meta_update_addr[3]);

//     $dumpvars(0, dut.meta_update_in[0]);
//     $dumpvars(0, dut.meta_update_in[1]);
//     $dumpvars(0, dut.meta_update_in[2]);
//     $dumpvars(0, dut.meta_update_in[3]);

//     $dumpvars(0, dut.meta_update_out[0]);
//     $dumpvars(0, dut.meta_update_out[1]);
//     $dumpvars(0, dut.meta_update_out[2]);
//     $dumpvars(0, dut.meta_update_out[3]);

//     $dumpvars(0, dut.meta_lookup_addr[0]);
//     $dumpvars(0, dut.meta_lookup_addr[1]);
//     $dumpvars(0, dut.meta_lookup_addr[2]);
//     $dumpvars(0, dut.meta_lookup_addr[3]);

//     $dumpvars(0, dut.meta_lookup_out[0]);
//     $dumpvars(0, dut.meta_lookup_out[1]);
//     $dumpvars(0, dut.meta_lookup_out[2]);
//     $dumpvars(0, dut.meta_lookup_out[3]);

//     $dumpvars(0, dut.meta_lookup_out_[0]);
//     $dumpvars(0, dut.meta_lookup_out_[1]);
//     $dumpvars(0, dut.meta_lookup_out_[2]);
//     $dumpvars(0, dut.meta_lookup_out_[3]);

//     $dumpvars(0, dut.meta_fwd_valid[0]);
//     $dumpvars(0, dut.meta_fwd_valid[1]);
//     $dumpvars(0, dut.meta_fwd_valid[2]);
//     $dumpvars(0, dut.meta_fwd_valid[3]);

//     $dumpvars(0, dut.meta_fwd_data[0]);
//     $dumpvars(0, dut.meta_fwd_data[1]);
//     $dumpvars(0, dut.meta_fwd_data[2]);
//     $dumpvars(0, dut.meta_fwd_data[3]);

//     // Data RAM control and data
//     $dumpvars(0, dut.data_update_we[0]);
//     $dumpvars(0, dut.data_update_we[1]);
//     $dumpvars(0, dut.data_update_we[2]);
//     $dumpvars(0, dut.data_update_we[3]);

//     $dumpvars(0, dut.data_update_addr[0]);
//     $dumpvars(0, dut.data_update_addr[1]);
//     $dumpvars(0, dut.data_update_addr[2]);
//     $dumpvars(0, dut.data_update_addr[3]);

//     $dumpvars(0, dut.data_update_in[0]);
//     $dumpvars(0, dut.data_update_in[1]);
//     $dumpvars(0, dut.data_update_in[2]);
//     $dumpvars(0, dut.data_update_in[3]);

//     $dumpvars(0, dut.data_update_out[0]);
//     $dumpvars(0, dut.data_update_out[1]);
//     $dumpvars(0, dut.data_update_out[2]);
//     $dumpvars(0, dut.data_update_out[3]);

//     $dumpvars(0, dut.data_lookup_addr[0]);
//     $dumpvars(0, dut.data_lookup_addr[1]);
//     $dumpvars(0, dut.data_lookup_addr[2]);
//     $dumpvars(0, dut.data_lookup_addr[3]);

//     $dumpvars(0, dut.data_lookup_out[0]);
//     $dumpvars(0, dut.data_lookup_out[1]);
//     $dumpvars(0, dut.data_lookup_out[2]);
//     $dumpvars(0, dut.data_lookup_out[3]);

//     $dumpvars(0, dut.data_lookup_out_[0]);
//     $dumpvars(0, dut.data_lookup_out_[1]);
//     $dumpvars(0, dut.data_lookup_out_[2]);
//     $dumpvars(0, dut.data_lookup_out_[3]);

//     $dumpvars(0, dut.data_fwd_valid[0]);
//     $dumpvars(0, dut.data_fwd_valid[1]);
//     $dumpvars(0, dut.data_fwd_valid[2]);
//     $dumpvars(0, dut.data_fwd_valid[3]);

//     $dumpvars(0, dut.data_fwd_data[0]);
//     $dumpvars(0, dut.data_fwd_data[1]);
//     $dumpvars(0, dut.data_fwd_data[2]);
//     $dumpvars(0, dut.data_fwd_data[3]);
// end

//   // Clock generation.
//   initial clk = 1'b0;
//   always #(CLK_PERIOD_NS/2) clk = ~clk;

//   // ---------------------------------------------------------------------------
//   // Backing memory / Wishbone slave model
//   // ---------------------------------------------------------------------------
//   // The cache uses 32-bit word transfers. The model maps byte addresses through
//   // address bits [17:2], giving 64K words for directed tests. Keep test addresses
//   // in this region so that addresses don't alias in the model.
//   reg [31:0] backing_mem [0:MEM_WORDS-1];

//   integer wb_read_beats;
//   integer wb_write_beats;
//   integer wb_error_count;
//   integer wb_fixed_latency;
//   reg   wb_random_latency;
//   reg   wb_inject_error_next;

//   reg        wb_pending;
//   reg [31:0] wb_pending_addr;
//   reg [31:0] wb_pending_wdata;
//   reg [3:0]  wb_pending_sel;
//   reg        wb_pending_we;
//   reg        wb_pending_error;
//   integer      wb_pending_delay;

//   function integer memory_index;
//     input [31:0] byte_addr;
//     begin
//       memory_index = byte_addr[17:2];
//     end
//   endfunction

//   function [31:0] read_backing_word;
//     input [31:0] byte_addr;
//     begin
//       read_backing_word = backing_mem[memory_index(byte_addr)];
//     end
//   endfunction

//   function [31:0] apply_byte_select;
//     input [31:0] old_word;
//     input [31:0] new_word;
//     input [3:0] byte_sel;
//     reg [31:0] merged;
//     integer lane;
//     begin
//       merged = old_word;
//       for (lane = 0; lane < 4; lane = lane + 1) begin
//         if (byte_sel[lane])
//           merged[lane*8 +: 8] = new_word[lane*8 +: 8];
//       end
//       apply_byte_select = merged;
//     end
//   endfunction

//   function [31:0] make_addr;
//     input [18:0] tag;
//     input [1:0] bank;
//     input [6:0] line_index;
//     input [3:0] byte_offset;
//     begin
//       make_addr = {tag, bank, line_index, byte_offset};
//     end
//   endfunction

//   // Model accepts a beat, optionally waits, then returns a one-cycle ACK or ERR.
//   // Outputs are driven on the falling edge so they are stable at the DUT's next
//   // rising edge. Address/data are captured at the start of each beat as required
//   // by a conventional Wishbone slave.
//   integer wb_memory_idx;

//   always @(negedge clk) begin : wishbone_slave_model
//     if (!rst_n) begin
//       wb_rdata           = 32'b0;
//       wb_ack             = 1'b0;
//       wb_err             = 1'b0;
//       wb_pending         = 1'b0;
//       wb_pending_delay   = 0;
//       wb_pending_error   = 1'b0;
//       wb_pending_addr    = 32'b0;
//       wb_pending_wdata   = 32'b0;
//       wb_pending_sel     = 4'b0;
//       wb_pending_we      = 1'b0;
//     end else begin
//       wb_ack = 1'b0;
//       wb_err = 1'b0;

//       if (wb_pending) begin
//         if (wb_pending_delay > 0) begin
//           wb_pending_delay = wb_pending_delay - 1;
//         end else begin
//           wb_memory_idx = memory_index(wb_pending_addr);
//           if (wb_pending_error) begin
//             wb_err = 1'b1;
//             wb_error_count = wb_error_count + 1;
//           end else begin
//             wb_ack = 1'b1;
//             if (wb_pending_we) begin
//               backing_mem[wb_memory_idx] = apply_byte_select(
//                 backing_mem[wb_memory_idx], wb_pending_wdata, wb_pending_sel
//               );
//               wb_write_beats = wb_write_beats + 1;
//             end else begin
//               wb_rdata = backing_mem[wb_memory_idx];
//               wb_read_beats = wb_read_beats + 1;
//             end
//           end
//           wb_pending = 1'b0;
//         end
//       end else if (wb_cyc && wb_stb) begin
//         wb_pending_addr  = wb_addr;
//         wb_pending_wdata = wb_wdata;
//         wb_pending_sel   = wb_sel;
//         wb_pending_we    = wb_we;
//         wb_pending_error = wb_inject_error_next;
//         wb_inject_error_next = 1'b0;
//         if (wb_random_latency)
//           wb_pending_delay = ($random & 32'h7fffffff) % 4;
//         else
//           wb_pending_delay = wb_fixed_latency;
//         wb_pending = 1'b1;
//       end
//     end
//   end

//   // ---------------------------------------------------------------------------
//   // Lightweight FSM coverage hooks. These intentionally use hierarchical
//   // references because the request is specifically to cover the states in this
//   // implementation. If the RTL is renamed/refactored, update this section.
//   // ---------------------------------------------------------------------------
//   reg [15:0] main_state_seen;
//   reg [3:0]  wb_state_seen;
//   integer checks_failed;
//   integer checks_passed;

//   always @(posedge clk) begin
//     if (rst_n) begin
//       if ((^dut.req_state) !== 1'bx)
//         main_state_seen[dut.req_state] = 1'b1;
//       if ((^dut.wb_state) !== 1'bx)
//         wb_state_seen[dut.wb_state] = 1'b1;
//     end
//   end

//   task check;
//     input condition;
//     input [8*256-1:0] message;

//     begin : check_body
//       if (condition !== 1'b1) begin
//         checks_failed = checks_failed + 1;
//         $display("\033[31m[FAIL %0t] %0s\033[0m", $time, message);
//       end else begin
//         checks_passed = checks_passed + 1;
//         $display("\033[32m[PASS %0t] %0s\033[0m", $time, message);
//       end
//     end
//   endtask

//   // ---------------------------------------------------------------------------
//   // Reusable AHB-like request tasks
//   // ---------------------------------------------------------------------------
//   task wait_for_addr_state;
//     output reg success;

//     integer cycles;
//     begin : wait_for_addr_state_body
//       success = 1'b0;
//       cycles = 0;
//       while ((dut.req_state !== ST_ADDR) && (cycles < MAX_WAIT_CYCLES)) begin
//         @(negedge clk);
//         cycles = cycles + 1;
//       end
//       if (dut.req_state === ST_ADDR)
//         success = 1'b1;
//       else
//         check(1'b0, "Timed out waiting for CACHE_STATE_ADDR before AHB request");
//     end
//   endtask

//   task ahb_start_request;
//     input [31:0] address;
//     input is_write;
//     input [2:0] size;
//     input [31:0] write_data;
//     output reg success;

//     reg addr_ready;
//     begin : ahb_start_request_body
//       wait_for_addr_state(addr_ready);
//       if (!addr_ready) begin
//         success = 1'b0;
//         disable ahb_start_request_body;
//       end

//       // Leave a full falling-edge setup interval before the accepting rising edge.
//       @(negedge clk);
//       ahb_addr  = address;
//       ahb_we    = is_write;
//       ahb_size  = size;
//       ahb_wdata = write_data;
//       ahb_trans = 2'b10; // NONSEQ / valid transfer for this DUT

//       @(posedge clk); // request accepted in CACHE_STATE_ADDR
//       @(negedge clk);
//       ahb_trans = 2'b00; // no pipelined next request; keep other fields stable
//       success = 1'b1;
//     end
//   endtask

//   task ahb_wait_for_hit;
//     output reg [31:0] read_data;
//     output reg success;

//     integer cycles;
//     begin : ahb_wait_for_hit_body
//       read_data = 32'b0;
//       success = 1'b0;
//       for (cycles = 0; cycles < MAX_WAIT_CYCLES; cycles = cycles + 1) begin
//         // Check before waiting: a cache hit may be ready on the first negedge
//         // after ahb_start_request returns.
//         if ((dut.req_state === ST_CACHE) && (dut.req_hit === 1'b1) && (ahb_ready === 1'b1)) begin
//           read_data = ahb_rdata;
//           @(posedge clk); // let the hit/write complete
//           @(negedge clk);
//           success = 1'b1;
//           disable ahb_wait_for_hit_body;
//         end
//         @(negedge clk);
//       end
//       check(1'b0, "Timed out waiting for a cache hit/completed AHB request");
//     end
//   endtask

//   task ahb_transfer;
//     input [31:0] address;
//     input is_write;
//     input [2:0] size;
//     input [31:0] write_data;
//     output reg [31:0] read_data;
//     output reg success;

//     reg start_ok;
//     begin : ahb_transfer_body
//       ahb_start_request(address, is_write, size, write_data, start_ok);
//       if (!start_ok) begin
//         read_data = 32'b0;
//         success = 1'b0;
//         disable ahb_transfer_body;
//       end
//       ahb_wait_for_hit(read_data, success);
//     end
//   endtask

//   task cpu_read_word;
//     input [31:0] address;
//     output reg [31:0] value;
//     output reg success;
//     input [8*256-1:0] label;

//     begin : cpu_read_word_body
//       ahb_transfer(address, 1'b0, 3'b010, 32'b0, value, success);
//       check(success, label);
//     end
//   endtask

//   task cpu_write_word;
//     input [31:0] address;
//     input [31:0] value;
//     output reg success;
//     input [8*256-1:0] label;

//     reg [31:0] unused_data;
//     begin : cpu_write_word_body
//       ahb_transfer(address, 1'b1, 3'b010, value, unused_data, success);
//       check(success, label);
//     end
//   endtask

//   task cpu_write_byte;
//     input [31:0] address;
//     input [7:0] value;
//     output reg success;

//     reg [31:0] shifted_data;
//     reg [31:0] unused_data;
//     begin : cpu_write_byte_body
//       // This matches the lane-aligned write-data convention used by the DUT's
//       // (wdata & byte_mask) merge. Adjust if your AHB bridge uses another format.
//       shifted_data = {24'b0, value} << (8 * address[1:0]);
//       ahb_transfer(address, 1'b1, 3'b000, shifted_data, unused_data, success);
//       check(success, "byte store completed");
//     end
//   endtask

//   task cpu_read_byte;
//     input [31:0] address;
//     output reg [7:0] value;
//     output reg success;

//     reg [31:0] raw_data;
//     reg [31:0] shifted_data;
//     begin : cpu_read_byte_body
//       ahb_transfer(address, 1'b0, 3'b000, 32'b0, raw_data, success);
//       shifted_data = raw_data >> (8 * address[1:0]);
//       value = shifted_data[7:0];
//       check(success, "byte load completed");
//     end
//   endtask

//   task cpu_write_halfword;
//     input [31:0] address;
//     input [15:0] value;
//     output reg success;

//     reg [31:0] shifted_data;
//     reg [31:0] unused_data;
//     begin : cpu_write_halfword_body
//       shifted_data = {16'b0, value} << (address[1] ? 16 : 0);
//       ahb_transfer(address, 1'b1, 3'b001, shifted_data, unused_data, success);
//       check(success, "halfword store completed");
//     end
//   endtask

//   task cpu_read_halfword;
//     input [31:0] address;
//     output reg [15:0] value;
//     output reg success;

//     reg [31:0] raw_data;
//     reg [31:0] shifted_data;
//     begin : cpu_read_halfword_body
//       ahb_transfer(address, 1'b0, 3'b001, 32'b0, raw_data, success);
//       shifted_data = raw_data >> (address[1] ? 16 : 0);
//       value = shifted_data[15:0];
//       check(success, "halfword load completed");
//     end
//   endtask

//   task expect_wishbone_error;
//     input [31:0] address;
//     output reg success;

//     reg start_ok;
//     integer cycles;
//     begin : expect_wishbone_error_body
//       success = 1'b0;
//       ahb_start_request(address, 1'b0, 3'b010, 32'b0, start_ok);
//       if (!start_ok)
//         disable expect_wishbone_error_body;

//       for (cycles = 0; cycles < MAX_WAIT_CYCLES; cycles = cycles + 1) begin
//         if (dut.req_state === ST_MEM_ERR) begin
//           check(ahb_resp === 1'b1, "AHB response indicates the Wishbone error for 1 cycle");
//           @(posedge clk);
//           @(negedge clk);
//           check(ahb_resp === 1'b1, "AHB response indicates the Wishbone error for 2 cycles");
//           success = 1'b1;
//           disable expect_wishbone_error_body;
//         end
//         @(negedge clk);
//       end
//       check(1'b0, "Timed out waiting for CACHE_STATE_MEM_ERR after injected Wishbone error");
//     end
//   endtask

//   task request_cleanup;
//     output reg success;

//     integer cycles;
//     begin : request_cleanup_body
//       success = 1'b0;
//       @(negedge clk);
//       cleanup = 1'b1;
//       @(negedge clk);
//       cleanup = 1'b0;

//       for (cycles = 0; cycles < MAX_CLEANUP_CYCLES; cycles = cycles + 1) begin
//         // Avoid mistaking the initial, not-yet-latched cleanup request for done.
//         if ((cycles > 20) && (dut.req_state === ST_ADDR) &&
//             (dut.flush_pending === 1'b0)) begin
//           success = 1'b1;
//           disable request_cleanup_body;
//         end
//         @(negedge clk);
//       end
//       check(1'b0, "Timed out waiting for cache cleanup to finish");
//     end
//   endtask

//   // ---------------------------------------------------------------------------
//   // Directed tests
//   // ---------------------------------------------------------------------------
//   reg [31:0] base_addr;
//   reg [31:0] expected_base_word;
//   reg [31:0] bank_addr [0:3];

//   task test_reset_and_idle;
//     begin
//       check(dut.req_state === ST_ADDR, "reset leaves main FSM in CACHE_STATE_ADDR");
//       check(wb_cyc === 1'b0 && wb_stb === 1'b0, "Wishbone is idle after reset");
//     end
//   endtask

//   task test_clean_miss_hit_and_refill_words;
//     reg [31:0] got;
//     reg [31:0] address;
//     reg ok;
//     integer before_reads;
//     integer word_no;
//     begin
//       $display("\n=== TEST: clean miss, burst refill, hits, word ordering ===");
//       base_addr = make_addr(19'h00001, 2'b00, 7'd0, 4'd0);
//       expected_base_word = read_backing_word(base_addr);
//       before_reads = wb_read_beats;

//       cpu_read_word(base_addr, got, ok, "initial clean miss");
//       check(got === expected_base_word,
//             "miss returns backing-memory word");
//       check((wb_read_beats - before_reads) == 4,
//             "a line miss performs four acknowledged Wishbone read beats");

//       before_reads = wb_read_beats;
//       for (word_no = 0; word_no < 4; word_no = word_no + 1) begin
//         address = base_addr + (word_no * 4);
//         cpu_read_word(address, got, ok, "refilled word");
//         check(got === read_backing_word(address),
//               "refilled word has correct data");
//       end
//       check(wb_read_beats == before_reads,
//             "reads of all words in the resident line do not access Wishbone");
//     end
//   endtask

//   task test_byte_and_halfword_stores;
//     reg [31:0] got_word;
//     reg [7:0]  got_byte;
//     reg [15:0] got_half;
//     reg [7:0]  byte_value;
//     reg ok;
//     integer lane;
//     begin
//       $display("\n=== TEST: byte/halfword write masks and dirty tracking ===");
//       expected_base_word = read_backing_word(base_addr);

//       for (lane = 0; lane < 4; lane = lane + 1) begin
//         byte_value = 8'hA1 + lane;
//         cpu_write_byte(base_addr + lane, byte_value, ok);
//         case (lane)
//           0: expected_base_word[7:0]   = byte_value;
//           1: expected_base_word[15:8]  = byte_value;
//           2: expected_base_word[23:16] = byte_value;
//           3: expected_base_word[31:24] = byte_value;
//         endcase
//         cpu_read_word(base_addr, got_word, ok, "verify byte lane");
//         check(got_word === expected_base_word,
//               "byte lane merge");
//         cpu_read_byte(base_addr + lane, got_byte, ok);
//         check(got_byte === byte_value,
//               "byte lane readback");
//       end

//       cpu_write_halfword(base_addr + 2, 16'hBEEF, ok);
//       expected_base_word[31:16] = 16'hBEEF;
//       cpu_read_word(base_addr, got_word, ok, "verify upper-halfword store");
//       check(got_word === expected_base_word,
//             "halfword merge");
//       cpu_read_halfword(base_addr + 2, got_half, ok);
//       check(got_half === 16'hBEEF,
//             "halfword readback");
//     end
//   endtask

//   task test_dirty_eviction;
//     reg [31:0] new_addr;
//     reg [31:0] got;
//     reg [31:0] expected_old_word;
//     reg ok;
//     integer before_writes;
//     integer before_reads;
//     begin
//       $display("\n=== TEST: dirty eviction writes a victim line back ===");
//       expected_old_word = expected_base_word;
//       // A conflicting tag with the same bank and line index should evict base_addr.
//       new_addr = make_addr(19'h00002, 2'b00, 7'd0, 4'd0);
//       before_writes = wb_write_beats;
//       before_reads  = wb_read_beats;

//       cpu_write_word(base_addr, 32'hCAFE_1234, ok, "make victim dirty");
//       expected_old_word = 32'hCAFE_1234;
//       cpu_read_word(new_addr, got, ok, "read conflicting tag after dirty eviction");
//       check(got === read_backing_word(new_addr),
//             "replacement line data matches backing memory");
//       check((wb_write_beats - before_writes) >= 4,
//             "dirty eviction generates four Wishbone write beats");
//       check(read_backing_word(base_addr) === expected_old_word,
//             "victim word reaches backing memory");
//       check((wb_read_beats - before_reads) >= 4,
//             "replacement line is fetched from backing memory");
//     end
//   endtask

//   task test_four_bank_isolation;
//     reg [31:0] got;
//     reg ok;
//     integer bank;
//     integer before_reads;
//     begin
//       $display("\n=== TEST: four-bank isolation ===");
//       // Same tag/index but different bank bits should represent four independent
//       // resident lines under the apparent address layout.
//       for (bank = 0; bank < 4; bank = bank + 1)
//         bank_addr[bank] = make_addr(19'h0000A, bank[1:0], 7'd0, 4'd0);

//       before_reads = wb_read_beats;
//       for (bank = 0; bank < 4; bank = bank + 1) begin
//         cpu_read_word(bank_addr[bank], got, ok, "first read bank");
//         check(got === read_backing_word(bank_addr[bank]),
//               "bank returns its own data");
//       end
//       check((wb_read_beats - before_reads) == 16,
//             "one cold line in each bank causes four bursts (16 read beats)");

//       before_reads = wb_read_beats;
//       for (bank = 0; bank < 4; bank = bank + 1) begin
//         cpu_read_word(bank_addr[bank], got, ok, "second read bank");
//         check(got === read_backing_word(bank_addr[bank]),
//               "bank remains isolated");
//       end
//       check(wb_read_beats == before_reads,
//             "second reads of all four resident banks cause no extra refills");
//     end
//   endtask

//   task test_high_line_index_addressing;
//     reg [31:0] address;
//     reg [31:0] got;
//     reg ok;
//     begin
//       $display("\n=== TEST: nonzero/high line-index address arithmetic ===");
//       address = make_addr(19'h00011, 2'b00, 7'd40, 4'd0);
//       cpu_read_word(address, got, ok, "read line index 40");
//       check(got === read_backing_word(address),
//             "line-index 40 data/addressing");
//     end
//   endtask

//   task test_variable_wishbone_latency;
//     reg [31:0] address;
//     reg [31:0] got;
//     reg ok;
//     integer before_reads;
//     begin
//       $display("\n=== TEST: Wishbone acknowledgement stalls ===");
//       address = make_addr(19'h00015, 2'b00, 7'd3, 4'd0);
//       before_reads = wb_read_beats;
//       wb_random_latency = 1'b1;
//       cpu_read_word(address, got, ok, "read with randomized Wishbone latency");
//       wb_random_latency = 1'b0;
//       check(got === read_backing_word(address),
//             "delayed refill data");
//       check((wb_read_beats - before_reads) == 4,
//             "Wishbone wait states neither drop nor duplicate refill beats");
//     end
//   endtask

//   task test_wishbone_error_path;
//     reg [31:0] address;
//     reg ok;
//     integer before_errors;
//     begin
//       $display("\n=== TEST: Wishbone error and controller recovery ===");
//       address = make_addr(19'h00123, 2'b00, 7'd48, 4'd0);
//       before_errors = wb_error_count;
//       wb_inject_error_next = 1'b1;
//       expect_wishbone_error(address, ok);
//       check(ok, "injected Wishbone error reaches CACHE_STATE_MEM_ERR");
//       check(wb_error_count == before_errors + 1,
//             "Wishbone slave model injected exactly one error");
//       check(dut.req_state === ST_ADDR,
//             "controller returns to CACHE_STATE_ADDR after memory error");
//     end
//   endtask

//   task test_cleanup_writeback;
//     reg [31:0] address;
//     reg [31:0] got;
//     reg [31:0] expected_after_store;
//     reg ok;
//     integer before_writes;
//     begin
//       $display("\n=== TEST: cleanup scans lines and writes back dirty data ===");
//       address = make_addr(19'h00055, 2'b00, 7'd8, 4'd0);
//       cpu_read_word(address, got, ok, "load line to be cleaned");
//       check(got === read_backing_word(address), "cleanup test line initially matches backing memory");

//       expected_after_store = 32'hD00D_F00D;
//       cpu_write_word(address, expected_after_store, ok, "dirty line before cleanup");
//       before_writes = wb_write_beats;
//       request_cleanup(ok);
//       check(ok, "cleanup request completes");
//       check((wb_write_beats - before_writes) >= 4,
//             "cleanup writes back at least one four-word dirty line");
//       check(read_backing_word(address) === expected_after_store,
//             "cleanup persisted dirty word");
//       check(dut.flush_pending === 1'b0,
//             "cleanup_pending is cleared when cleanup completes");
//     end
//   endtask

//   // ---------------------------------------------------------------------------
//   // Coverage summary
//   // ---------------------------------------------------------------------------
//   task report_main_state;
//     input integer state_id;
//     input [8*256-1:0] state_name;

//     begin : report_main_state_body
//       check(main_state_seen[state_id] === 1'b1,
//             state_name);
//     end
//   endtask

//   task report_wb_state;
//     input integer state_id;
//     input [8*256-1:0] state_name;

//     begin : report_wb_state_body
//       check(wb_state_seen[state_id] === 1'b1,
//             state_name);
//     end
//   endtask

//   task report_state_coverage;
//     begin
//       $display("\n=== MAIN FSM STATE COVERAGE ===");
//       report_main_state(ST_ADDR,                "CACHE_STATE_ADDR");
//       report_main_state(ST_CACHE,               "CACHE_STATE_CACHE");
//       report_main_state(ST_LOOKUP,              "CACHE_STATE_LOOKUP");
//       report_main_state(ST_MEM_EVICT,            "CACHE_STATE_MEM_EVICT");
//       report_main_state(ST_MEM_WAIT,             "CACHE_STATE_MEM_WAIT");
//       report_main_state(ST_MEM_READ,             "CACHE_STATE_MEM_READ");
//       report_main_state(ST_UPDATE_META,          "CACHE_STATE_UPDATE_META");
//       report_main_state(ST_REDO_ADDR,            "CACHE_STATE_REDO_ADDR");
//       report_main_state(ST_MEM_ERR,              "CACHE_STATE_MEM_ERR");

//       $display("\n=== WISHBONE FSM STATE COVERAGE ===");
//       report_wb_state(WB_ST_IDLE,       "WB_STATE_IDLE");
//       report_wb_state(WB_ST_WDATA_WAIT, "WB_STATE_WDATA_WAIT");
//       report_wb_state(WB_ST_TRANSFER,   "WB_STATE_TRANSFER");
//     end
//   endtask

//   // ---------------------------------------------------------------------------
//   // Test sequence
//   // ---------------------------------------------------------------------------
//   integer init_i;
//   initial begin
//     rst_n = 1'b0;
//     ahb_addr = 32'b0;
//     ahb_we = 1'b0;
//     ahb_trans = 2'b00;
//     ahb_size = 3'b010;
//     ahb_wdata = 32'b0;
//     cleanup = 1'b0;

//     wb_rdata = 32'b0;
//     wb_ack = 1'b0;
//     wb_err = 1'b0;
//     wb_read_beats = 0;
//     wb_write_beats = 0;
//     wb_error_count = 0;
//     wb_fixed_latency = 1;
//     wb_random_latency = 1'b0;
//     wb_inject_error_next = 1'b0;
//     wb_pending = 1'b0;
//     wb_pending_addr = 32'b0;
//     wb_pending_wdata = 32'b0;
//     wb_pending_sel = 4'b0;
//     wb_pending_we = 1'b0;
//     wb_pending_error = 1'b0;
//     wb_pending_delay = 0;
//     main_state_seen = 16'b0;
//     wb_state_seen = 4'b0;
//     checks_failed = 0;
//     checks_passed = 0;
//     base_addr = 32'b0;
//     expected_base_word = 32'b0;

//     // Deterministic memory pattern catches swapped words and address errors.
//     for (init_i = 0; init_i < MEM_WORDS; init_i = init_i + 1)
//       backing_mem[init_i] = 32'hA500_0000 ^ (init_i * 32'h0000_1021);

//     repeat (5) @(negedge clk);
//     rst_n = 1'b1;
//     repeat (3) @(negedge clk);

//     test_reset_and_idle();
//     test_clean_miss_hit_and_refill_words();
//     test_byte_and_halfword_stores();
//     test_dirty_eviction();
//     test_four_bank_isolation();
//     test_high_line_index_addressing();
//     test_variable_wishbone_latency();
//     test_wishbone_error_path();
//     test_cleanup_writeback();

//     report_state_coverage();

//     $display("\n=== SUMMARY ===");
//     $display("Wishbone read beats : %0d", wb_read_beats);
//     $display("Wishbone write beats: %0d", wb_write_beats);
//     $display("Wishbone errors     : %0d", wb_error_count);
//     $display("Checks passed       : %0d", checks_passed);
//     $display("Checks failed       : %0d", checks_failed);
//     if (checks_failed == 0)
//       $display("TESTBENCH RESULT: PASS");
//     else
//       $display("TESTBENCH RESULT: FAIL (%0d checks failed)", checks_failed);
//     $finish;
//   end

//   // Global watchdog in case an accidental testbench bug deadlocks the sequence.
//   initial begin
//     #(CLK_PERIOD_NS * 1000000);
//     $display("[FATAL] Global simulation watchdog expired");
//     $finish;
//   end

// endmodule

`timescale 1ns/1ps

module data_cache_tb;
  parameter MEM_WORDS       = 262144; // 2^18 words, indexed by addr[19:2]
  parameter MAX_WAIT_CYCLES = 20000;

  reg         i_clk;
  reg         i_rst_n;
  reg [31:0]  i_ahb5_addr;
  reg         i_ahb5_we;
  reg [1:0]   i_ahb5_trans;
  reg [2:0]   i_ahb5_size;
  reg [31:0]  i_ahb5_wdata;
  wire [31:0] o_ahb5_rdata;
  wire        o_ahb5_ready;
  wire        o_ahb5_resp;

  wire        o_wb_cyc;
  wire        o_wb_stb;
  wire        o_wb_we;
  wire [1:0]  o_wb_bte;
  wire [2:0]  o_wb_cti;
  wire [3:0]  o_wb_sel;
  wire [31:0] o_wb_addr;
  wire [31:0] o_wb_wdata;
  reg [31:0]  i_wb_rdata;
  reg         i_wb_ack;
  reg         i_wb_err;

  reg         i_flush;
  reg         i_cache_on;

  integer     ahb_gap_min;
  integer     ahb_gap_max;
  integer     wb_delay_min;
  integer     wb_delay_max;
  integer     cfg_ahb_gap_min;
  integer     cfg_ahb_gap_max;
  integer     cfg_wb_delay_min;
  integer     cfg_wb_delay_max;
  integer     random_seed;
  integer     random_ops;
  integer     run_error_tests;
  integer     failures;
  integer     tests_run;
  integer     cycles_seen;

  reg [31:0]  wb_mem [0:MEM_WORDS-1];
  reg [31:0]  expected_mem [0:MEM_WORDS-1];
  reg         touched [0:MEM_WORDS-1];

  integer     wb_pending;
  integer     wb_wait_count;
  integer     wb_error_enable;
  reg [31:0]  wb_error_addr;
  integer     wb_error_fired;
  integer     wb_ack_count;
  integer     wb_read_ack_count;
  integer     wb_write_ack_count;
  integer     wb_error_count;

  // Wishbone stall stability monitor.
  integer     wb_was_stalled;
  reg [31:0]  wb_hold_addr;
  reg [31:0]  wb_hold_wdata;
  reg [3:0]   wb_hold_sel;
  reg [2:0]   wb_hold_cti;
  reg         wb_hold_we;

  // AHB stall stability monitor.
  integer     ahb_was_stalled;
  reg [31:0]  ahb_hold_addr;
  reg         ahb_hold_we;
  reg [1:0]   ahb_hold_trans;
  reg [2:0]   ahb_hold_size;

  integer     i;
  integer     idx;
  integer     rc;
  integer     b;
  integer     w;
  integer     n;
  integer     before_reads;
  integer     after_reads;
  integer     err_seen;
  reg [31:0]  addr;
  reg [31:0]  data_value;
  reg [31:0]  expected_value;
  reg [31:0]  old_line_addr;
  reg [31:0]  new_line_addr;

  data_cache dut (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .i_ahb5_addr(i_ahb5_addr),
    .i_ahb5_we(i_ahb5_we),
    .i_ahb5_trans(i_ahb5_trans),
    .i_ahb5_size(i_ahb5_size),
    .i_ahb5_wdata(i_ahb5_wdata),
    .o_ahb5_rdata(o_ahb5_rdata),
    .o_ahb5_ready(o_ahb5_ready),
    .o_ahb5_resp(o_ahb5_resp),
    .o_wb_cyc(o_wb_cyc),
    .o_wb_stb(o_wb_stb),
    .o_wb_we(o_wb_we),
    .o_wb_bte(o_wb_bte),
    .o_wb_cti(o_wb_cti),
    .o_wb_sel(o_wb_sel),
    .o_wb_addr(o_wb_addr),
    .o_wb_wdata(o_wb_wdata),
    .i_wb_rdata(i_wb_rdata),
    .i_wb_ack(i_wb_ack),
    .i_wb_err(i_wb_err),
    .i_flush(i_flush),
    .i_cache_on(i_cache_on)
  );

  // ------------------------------------------------------------------------
  // Clock and utility functions
  // ------------------------------------------------------------------------
  initial begin
    i_clk = 1'b0;
    forever #5 i_clk = ~i_clk;
  end

  function integer rand_between;
    input integer lo;
    input integer hi;
    integer r;
    begin
      if (hi <= lo) begin
        rand_between = lo;
      end else begin
        r = $random(random_seed);
        if (r < 0) r = -r;
        rand_between = lo + (r % (hi - lo + 1));
      end
    end
  endfunction

  function integer mem_index;
    input [31:0] a;
    begin
      mem_index = a[19:2];
    end
  endfunction

  function [31:0] make_addr;
    input [18:0] tag;
    input [1:0]  bank;
    input [6:0]  line_no;
    input [1:0]  word_no;
    begin
      make_addr = {tag, bank, line_no, word_no, 2'b00};
    end
  endfunction

  function [31:0] byte_mask;
    input [31:0] a;
    input [2:0]  size;
    begin
      case (size)
        3'b000: byte_mask = 32'h000000ff << (a[1:0] * 8);
        3'b001: byte_mask = a[1] ? 32'hffff0000 : 32'h0000ffff;
        default: byte_mask = 32'hffffffff;
      endcase
    end
  endfunction

  function [31:0] lane_data;
    input [31:0] a;
    input [2:0]  size;
    input [31:0] payload;
    begin
      case (size)
        3'b000: lane_data = {24'b0, payload[7:0]} << (a[1:0] * 8);
        3'b001: lane_data = {16'b0, payload[15:0]} << (a[1] * 16);
        default: lane_data = payload;
      endcase
    end
  endfunction

  // ------------------------------------------------------------------------
  // Synchronous Wishbone memory model. Each ACK is delayed independently.
  // ERR injection is disabled unless +ERRORS is supplied.
  // ------------------------------------------------------------------------
  always @(negedge i_clk) begin
    if (!i_rst_n) begin
      i_wb_ack = 1'b0;
      i_wb_err = 1'b0;
      i_wb_rdata = 32'b0;
      wb_pending = 0;
      wb_wait_count = 0;
    end else if (i_wb_ack || i_wb_err) begin
      i_wb_ack = 1'b0;
      i_wb_err = 1'b0;
      wb_pending = 0;
      wb_wait_count = 0;
    end else if (o_wb_cyc && o_wb_stb) begin
      if (!wb_pending) begin
        wb_pending = 1;
        wb_wait_count = rand_between(wb_delay_min, wb_delay_max);
      end else if (wb_wait_count > 0) begin
        wb_wait_count = wb_wait_count - 1;
      end else begin
        if (wb_error_enable && !wb_error_fired &&
            (o_wb_addr == wb_error_addr)) begin
          i_wb_err = 1'b1;
          wb_error_fired = 1;
        end else begin
          i_wb_rdata = wb_mem[mem_index(o_wb_addr)];
          i_wb_ack = 1'b1;
        end
      end
    end else begin
      wb_pending = 0;
      wb_wait_count = 0;
      i_wb_ack = 1'b0;
      i_wb_err = 1'b0;
    end
  end

  // Memory side effects occur only on a sampled ACK.
  always @(posedge i_clk) begin
    if (i_rst_n && o_wb_cyc && o_wb_stb && i_wb_ack) begin
      wb_ack_count = wb_ack_count + 1;
      idx = mem_index(o_wb_addr);
      if (o_wb_we) begin
        wb_write_ack_count = wb_write_ack_count + 1;
        if (o_wb_sel[0]) wb_mem[idx][7:0]   = o_wb_wdata[7:0];
        if (o_wb_sel[1]) wb_mem[idx][15:8]  = o_wb_wdata[15:8];
        if (o_wb_sel[2]) wb_mem[idx][23:16] = o_wb_wdata[23:16];
        if (o_wb_sel[3]) wb_mem[idx][31:24] = o_wb_wdata[31:24];
      end else begin
        wb_read_ack_count = wb_read_ack_count + 1;
      end
    end
    if (i_rst_n && o_wb_cyc && o_wb_stb && i_wb_err)
      wb_error_count = wb_error_count + 1;
  end

  // ------------------------------------------------------------------------
  // Protocol monitors: stable Wishbone request while stalled, and stable AHB
  // address/control while READY is low.
  // ------------------------------------------------------------------------
  always @(posedge i_clk) begin
    if (!i_rst_n) begin
      wb_was_stalled = 0;
      ahb_was_stalled = 0;
    end else begin
      if (wb_was_stalled) begin
        if (!o_wb_cyc || !o_wb_stb ||
            o_wb_addr !== wb_hold_addr ||
            o_wb_wdata !== wb_hold_wdata ||
            o_wb_sel !== wb_hold_sel ||
            o_wb_cti !== wb_hold_cti ||
            o_wb_we !== wb_hold_we) begin
          $display("FAIL: Wishbone request changed while waiting for ACK/ERR at time %0t", $time);
          failures = failures + 1;
        end
      end
      if (o_wb_cyc && o_wb_stb && !i_wb_ack && !i_wb_err) begin
        wb_was_stalled = 1;
        wb_hold_addr = o_wb_addr;
        wb_hold_wdata = o_wb_wdata;
        wb_hold_sel = o_wb_sel;
        wb_hold_cti = o_wb_cti;
        wb_hold_we = o_wb_we;
      end else begin
        wb_was_stalled = 0;
      end

      if (ahb_was_stalled && !o_ahb5_ready) begin
        if (i_ahb5_trans !== ahb_hold_trans ||
            i_ahb5_addr !== ahb_hold_addr ||
            i_ahb5_we !== ahb_hold_we ||
            i_ahb5_size !== ahb_hold_size) begin
          $display("FAIL: AHB address/control changed while READY was low at time %0t", $time);
          failures = failures + 1;
        end
      end
      if (i_ahb5_trans[1] && !o_ahb5_ready) begin
        ahb_was_stalled = 1;
        ahb_hold_trans = i_ahb5_trans;
        ahb_hold_addr = i_ahb5_addr;
        ahb_hold_we = i_ahb5_we;
        ahb_hold_size = i_ahb5_size;
      end else begin
        ahb_was_stalled = 0;
      end
    end
  end

  // ------------------------------------------------------------------------
  // AHB single-transfer driver. It observes the initial address-capture edge,
  // holds controls while READY is low, then removes HTRANS before the response
  // edge to avoid accidentally presenting a second pipelined request.
  // ------------------------------------------------------------------------
  task ahb_access;
    input [31:0] address;
    input        write_enable;
    input [2:0]  transfer_size;
    input [31:0] write_data;
    output [31:0] read_data;
    output integer response_error;
    integer wait_cycles;
    begin
      while (dut.req_state !== 4'b0000) @(negedge i_clk);
      repeat (rand_between(ahb_gap_min, ahb_gap_max)) @(negedge i_clk);
      @(negedge i_clk);
      i_ahb5_addr = address;
      i_ahb5_we = write_enable;
      i_ahb5_size = transfer_size;
      i_ahb5_wdata = write_data;
      i_ahb5_trans = 2'b10;

      // First edge captures address/control. Ignore READY in ADDR state.
      @(posedge i_clk);
      #1;
      wait_cycles = 0;
      while ((o_ahb5_ready !== 1'b1) && (wait_cycles < MAX_WAIT_CYCLES)) begin
        @(negedge i_clk);
        wait_cycles = wait_cycles + 1;
      end

      if (o_ahb5_ready !== 1'b1) begin
        $display("FAIL: AHB timeout addr=%08x write=%0d size=%0d state=%b", address,
                 write_enable, transfer_size, dut.req_state);
        failures = failures + 1;
        read_data = 32'bx;
        response_error = 1;
        i_ahb5_trans = 2'b00;
      end else begin
        // Capture response data before the completion edge changes FSM outputs.
        read_data = o_ahb5_rdata;
        response_error = (o_ahb5_resp === 1'b1) ? 1 : 0;
        i_ahb5_trans = 2'b00;
        @(posedge i_clk);
        #1;
      end
      @(negedge i_clk);
      i_ahb5_trans = 2'b00;
      i_ahb5_we = 1'b0;
    end
  endtask

  task check_read;
    input [31:0] address;
    input [2:0]  transfer_size;
    reg [31:0] got;
    reg [31:0] expected;
    integer response_error;
    begin
      ahb_access(address, 1'b0, transfer_size, 32'b0, got, response_error);
      expected = expected_mem[mem_index(address)] & byte_mask(address, transfer_size);
      if (response_error) begin
        $display("FAIL: unexpected AHB error on read addr=%08x", address);
        failures = failures + 1;
      end else if (got !== expected) begin
        $display("FAIL: READ addr=%08x size=%0d got=%08x expected=%08x", address,
                 transfer_size, got, expected);
        failures = failures + 1;
      end
      tests_run = tests_run + 1;
    end
  endtask

  task check_write;
    input [31:0] address;
    input [2:0]  transfer_size;
    input [31:0] payload;
    reg [31:0] ignored_data;
    reg [31:0] mask;
    reg [31:0] lane_value;
    integer response_error;
    integer memory_word;
    begin
      mask = byte_mask(address, transfer_size);
      lane_value = lane_data(address, transfer_size, payload);
      ahb_access(address, 1'b1, transfer_size, lane_value, ignored_data, response_error);
      if (response_error) begin
        $display("FAIL: unexpected AHB error on write addr=%08x", address);
        failures = failures + 1;
      end else begin
        memory_word = mem_index(address);
        expected_mem[memory_word] = (expected_mem[memory_word] & ~mask) |
                                    (lane_value & mask);
        touched[memory_word] = 1'b1;
      end
      tests_run = tests_run + 1;
    end
  endtask

  task wait_flush_complete;
    integer wait_cycles;
    begin
      wait_cycles = 0;
      while (((dut.flush_state !== 3'b000) || (dut.flush_pending !== 1'b0)) &&
             (wait_cycles < MAX_WAIT_CYCLES)) begin
        @(negedge i_clk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles >= MAX_WAIT_CYCLES) begin
        $display("FAIL: flush timeout state=%b pending=%b line=%0d", dut.flush_state,
                 dut.flush_pending, dut.flush_line);
        failures = failures + 1;
      end
      repeat (2) @(negedge i_clk);
    end
  endtask

  task pulse_flush;
    begin
      while (dut.req_state !== 4'b0000) @(negedge i_clk);
      @(negedge i_clk);
      i_flush = 1'b1;
      @(negedge i_clk);
      i_flush = 1'b0;
      wait_flush_complete;
    end
  endtask

  task check_touched_backing;
    integer k;
    integer bad_count;
    begin
      bad_count = 0;
      for (k = 0; k < MEM_WORDS; k = k + 1) begin
        if (touched[k] && (wb_mem[k] !== expected_mem[k])) begin
          if (bad_count < 8)
            $display("FAIL: backing memory mismatch word=%0d got=%08x expected=%08x",
                     k, wb_mem[k], expected_mem[k]);
          bad_count = bad_count + 1;
        end
      end
      if (bad_count != 0) begin
        $display("FAIL: %0d touched backing-memory words differ after flush", bad_count);
        failures = failures + bad_count;
      end
    end
  endtask

  task check_backing_word;
    input [31:0] address;
    begin
      idx = mem_index(address);
      if (wb_mem[idx] !== expected_mem[idx]) begin
        $display("FAIL: writeback addr=%08x got=%08x expected=%08x", address,
                 wb_mem[idx], expected_mem[idx]);
        failures = failures + 1;
      end
    end
  endtask

  // ------------------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------------------
  initial begin
    i_rst_n = 1'b0;
    i_ahb5_addr = 32'b0;
    i_ahb5_we = 1'b0;
    i_ahb5_trans = 2'b00;
    i_ahb5_size = 3'b010;
    i_ahb5_wdata = 32'b0;
    i_wb_rdata = 32'b0;
    i_wb_ack = 1'b0;
    i_wb_err = 1'b0;
    i_flush = 1'b0;
    i_cache_on = 1'b1;

    //PARAMS
    ahb_gap_min = 0;
    ahb_gap_max = 0;
    wb_delay_min = 0;
    wb_delay_max = 0;
    cfg_ahb_gap_min = 0;
    cfg_ahb_gap_max = 5;
    cfg_wb_delay_min = 0;
    cfg_wb_delay_max = 5;
    random_seed = 32'h13579bdf;
    random_ops = 150;
    run_error_tests = 0;

    failures = 0;
    tests_run = 0;
    cycles_seen = 0;

    wb_pending = 0;
    wb_wait_count = 0;
    wb_error_enable = 0;
    wb_error_addr = 32'b0;
    wb_error_fired = 0;
    wb_ack_count = 0;
    wb_read_ack_count = 0;
    wb_write_ack_count = 0;
    wb_error_count = 0;
    wb_was_stalled = 0;
    ahb_was_stalled = 0;

    if (cfg_ahb_gap_max < cfg_ahb_gap_min) cfg_ahb_gap_max = cfg_ahb_gap_min;
    if (cfg_wb_delay_max < cfg_wb_delay_min) cfg_wb_delay_max = cfg_wb_delay_min;

    $display("============================================================");
    $display("data_cache testbench: seed=%0d random AHB gap=%0d..%0d WB delay=%0d..%0d random_ops=%0d errors=%0d",
             random_seed, cfg_ahb_gap_min, cfg_ahb_gap_max,
             cfg_wb_delay_min, cfg_wb_delay_max, random_ops, run_error_tests);
    $display("============================================================");

    for (i = 0; i < MEM_WORDS; i = i + 1) begin
      wb_mem[i] = 32'h6a09e667 ^ (i * 32'h01010101);
      expected_mem[i] = wb_mem[i];
      touched[i] = 1'b0;
    end

    repeat (5) @(posedge i_clk);
    #1 i_rst_n = 1'b1;
    repeat (4) @(negedge i_clk);

    // TEST 1: First read miss, then a read hit (no second memory burst).
    $display("[1/7] cold miss, hit, and clean-only flush");
    addr = make_addr(19'd1, 2'd0, 7'd3, 2'd0);
    before_reads = wb_read_ack_count;
    check_read(addr, 3'b010);
    after_reads = wb_read_ack_count;
    if ((after_reads - before_reads) != 4) begin
      $display("FAIL: cold line fill used %0d read ACKs, expected 4", after_reads-before_reads);
      failures = failures + 1;
    end
    check_read(addr, 3'b010);
    if (wb_read_ack_count != after_reads) begin
      $display("FAIL: cache hit unexpectedly accessed Wishbone memory");
      failures = failures + 1;
    end
    // A clean-only flush must also finish and invalidate the clean line.
    pulse_flush;
    before_reads = wb_read_ack_count;
    check_read(addr, 3'b010);
    if ((wb_read_ack_count - before_reads) != 4) begin
      $display("FAIL: clean flush did not invalidate the cached line");
      failures = failures + 1;
    end

    // TEST 2: Word, halfword and byte writes/reads within one cache line.
    $display("[2/7] write merging and byte lanes");
    check_write(make_addr(19'd1, 2'd0, 7'd3, 2'd1), 3'b010, 32'h12345678);
    check_write(make_addr(19'd1, 2'd0, 7'd3, 2'd2) + 32'd2, 3'b001, 32'h0000beef);
    check_write(make_addr(19'd1, 2'd0, 7'd3, 2'd3) + 32'd1, 3'b000, 32'h000000a5);
    check_read(make_addr(19'd1, 2'd0, 7'd3, 2'd1), 3'b010);
    check_read(make_addr(19'd1, 2'd0, 7'd3, 2'd2), 3'b010);
    check_read(make_addr(19'd1, 2'd0, 7'd3, 2'd3), 3'b010);

    // TEST 3: All four banks use the same line index independently.
    // A conflict in bank 0 must not evict/overwrite banks 1, 2, or 3.
    $display("[3/7] four-bank isolation / no cross-bank overwriting");
    for (b = 0; b < 4; b = b + 1) begin
      addr = make_addr(19'd5, b[1:0], 7'd7, 2'd0);
      check_write(addr, 3'b010, 32'hb0000000 | (b * 32'h11111111));
    end
    for (b = 0; b < 4; b = b + 1) begin
      addr = make_addr(19'd5, b[1:0], 7'd7, 2'd0);
      check_read(addr, 3'b010);
    end
    old_line_addr = make_addr(19'd5, 2'd0, 7'd7, 2'd0);
    new_line_addr = make_addr(19'd6, 2'd0, 7'd7, 2'd0);
    check_read(new_line_addr, 3'b010); // forces dirty bank-0 eviction
    for (w = 0; w < 4; w = w + 1)
      check_backing_word(old_line_addr + (w * 4));
    for (b = 1; b < 4; b = b + 1)
      check_read(make_addr(19'd5, b[1:0], 7'd7, 2'd0), 3'b010);

    // TEST 4: Dirty eviction writes all four words to the correct old address.
    $display("[4/7] dirty eviction and writeback contents");
    old_line_addr = make_addr(19'd9, 2'd2, 7'd25, 2'd0);
    new_line_addr = make_addr(19'd10, 2'd2, 7'd25, 2'd0);
    for (w = 0; w < 4; w = w + 1)
      check_write(old_line_addr + (w * 4), 3'b010, 32'hcafe0000 + w);
    check_read(new_line_addr, 3'b010);
    for (w = 0; w < 4; w = w + 1)
      check_backing_word(old_line_addr + (w * 4));

    // TEST 5: Variable AHB idle spacing and independently delayed WB beats.
    $display("[5/7] variable request gaps and memory response latency");
    ahb_gap_min = cfg_ahb_gap_min;
    ahb_gap_max = cfg_ahb_gap_max;
    wb_delay_min = cfg_wb_delay_min;
    wb_delay_max = cfg_wb_delay_max;
    for (n = 0; n < random_ops; n = n + 1) begin
      b = rand_between(0, 3);
      w = rand_between(0, 127);
      idx = rand_between(0, 30);
      addr = make_addr(idx[18:0], b[1:0], w[6:0], rand_between(0, 3));
      rc = rand_between(0, 2);
      if (rc == 0) addr = addr + rand_between(0, 3);
      else if (rc == 1) addr = addr + (rand_between(0, 1) * 2);
      if (rand_between(0, 99) < 45) begin
        data_value = $random(random_seed);
        check_write(addr, rc[2:0], data_value);
      end else begin
        check_read(addr, rc[2:0]);
      end
    end

    // TEST 6: Explicit dirty flush, backing-memory audit, then refill after
    // invalidation. This also exercises all four banks during the flush scan.
    $display("[6/7] dirty flush, invalidation and cache refill");
    ahb_gap_min = 0;
    ahb_gap_max = 2;
    for (b = 0; b < 4; b = b + 1) begin
      addr = make_addr(19'd20, b[1:0], 7'd40 + b, 2'd0);
      check_write(addr, 3'b010, 32'hface1000 + b);
    end
    before_reads = wb_read_ack_count;
    pulse_flush;
    check_touched_backing;
    for (b = 0; b < 4; b = b + 1) begin
      addr = make_addr(19'd20, b[1:0], 7'd40 + b, 2'd0);
      for (w = 0; w < 4; w = w + 1)
        check_backing_word(addr + (w * 4));
    end
    check_read(make_addr(19'd20, 2'd0, 7'd40, 2'd0), 3'b010);
    if (wb_read_ack_count < (before_reads + 4)) begin
      $display("FAIL: read after flush did not appear to refill an invalidated line");
      failures = failures + 1;
    end

    // TEST 7: Cache disable automatically flushes; disabled accesses bypass.
    $display("[7/7] cache disable flush and bypass operation");
    addr = make_addr(19'd22, 2'd3, 7'd55, 2'd1);
    check_write(addr, 3'b010, 32'hdeadbeef);
    @(negedge i_clk);
    i_cache_on = 1'b0;
    // Allow the falling cache-enable edge to set flush_pending first.
    @(posedge i_clk);
    #1;
    wait_flush_complete;
    check_touched_backing;
    old_line_addr = addr & 32'hfffffff0;
    for (w = 0; w < 4; w = w + 1)
      check_backing_word(old_line_addr + (w * 4));
    // The cache is disabled: write should reach backing memory immediately.
    addr = make_addr(19'd23, 2'd1, 7'd56, 2'd2);
    check_write(addr, 3'b010, 32'h76543210);
    check_backing_word(addr);
    check_read(addr, 3'b010);
    @(negedge i_clk);
    i_cache_on = 1'b1;
    repeat (3) @(negedge i_clk);
    // Address bit 31 also selects bypass even while the cache is enabled.
    addr = make_addr(19'd24, 2'd2, 7'd57, 2'd0);
    addr[31] = 1'b1;
    check_write(addr, 3'b010, 32'h0badc0de);
    check_backing_word(addr);
    check_read(addr, 3'b010);

    // Optional final-stage error test: force a refill ERR after two successful
    // beats while replacing an existing clean line. The current RTL is expected
    // to expose the partial-refill/old-valid-tag hazard in this test.
    if (run_error_tests) begin
      $display("[ERRORS] partial refill error / stale metadata check");
      old_line_addr = make_addr(19'd30, 2'd0, 7'd101, 2'd0);
      new_line_addr = make_addr(19'd31, 2'd0, 7'd101, 2'd0);
      check_read(old_line_addr, 3'b010); // establish a valid clean line
      wb_error_addr = new_line_addr + 32'd8; // third word of replacement refill
      wb_error_fired = 0;
      wb_error_enable = 1;
      ahb_access(new_line_addr, 1'b0, 3'b010, 32'b0, data_value, err_seen);
      wb_error_enable = 0;
      if (!wb_error_fired || !err_seen) begin
        $display("FAIL: configured Wishbone ERR was not observed by the AHB request");
        failures = failures + 1;
      end
      // A correct cache must still return the old line's original contents.
      // This check is expected to fail on the current RTL if the partial refill
      // leaves the old metadata valid while overwriting the first two words.
      check_read(old_line_addr, 3'b010);
    end

    $display("------------------------------------------------------------");
    $display("Completed %0d checks; Wishbone ACKs=%0d reads=%0d writes=%0d ERRs=%0d",
             tests_run, wb_ack_count, wb_read_ack_count, wb_write_ack_count, wb_error_count);
    if (failures == 0)
      $display("PASS: no testbench checks failed");
    else
      $display("FAIL: %0d failures detected", failures);
    $display("------------------------------------------------------------");
    $finish;
  end

  // Global simulation watchdog.
  always @(posedge i_clk) begin
    if (i_rst_n) begin
      cycles_seen = cycles_seen + 1;
      if (cycles_seen > 2000000) begin
        $display("FATAL: global watchdog expired");
        $finish;
      end
    end
  end

endmodule