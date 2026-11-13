// =============================================================================
// File   : sync_fifo.sv
// Purpose: Generic synchronous FIFO, parameterized in width and depth. Used
//          by timer_adc8_top.sv to queue ADC results (guide: "8-entry
//          FIFO"). Each entry here stores {channel[1:0], code[7:0]} so that
//          a read of ADC_RCH can report which channel the oldest queued
//          result came from without disturbing the queue.
//          Classic read/write pointer + count design: 'rd_data' is a
//          combinational peek at the front of the queue (valid whenever
//          !empty); asserting rd_en for one cycle pops it on the next edge.
//          This lets the register file read ADC_RCH (peek, no rd_en) and
//          ADC_DATA (pop, rd_en pulsed) from the exact same output bus.
// =============================================================================
module sync_fifo #(
  parameter int WIDTH = 10,   // 8-bit ADC code + 2-bit channel
  parameter int DEPTH = 8     // guide: "8-entry FIFO"
) (
  input  logic                   clk,
  input  logic                   rst_n,      // asynchronous, active-low (peripheral-side convention)

  input  logic                   wr_en,
  input  logic [WIDTH-1:0]       wr_data,

  input  logic                   rd_en,
  output logic [WIDTH-1:0]       rd_data,    // combinational peek at the oldest entry

  output logic                   full,
  output logic                   empty,
  output logic [$clog2(DEPTH+1)-1:0] level    // current fill count, 0..DEPTH
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0] wr_ptr, rd_ptr;   // circular-buffer pointers
  logic [$clog2(DEPTH+1)-1:0] count;          // number of entries currently stored

  assign full  = (count == DEPTH);
  assign empty = (count == 0);
  assign level = count;

  // Only pop/push when the operation is actually legal; a push to a full
  // FIFO or a pop from an empty one is silently ignored rather than
  // corrupting the pointers (defensive, matches how real FIFO IP behaves).
  logic do_push, do_pop;
  assign do_push = wr_en && !full;
  assign do_pop  = rd_en && !empty;

  assign rd_data = mem[rd_ptr];   // always a valid peek when !empty

  // Pointers and count: the only state that genuinely needs a reset value.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      if (do_push) begin
        wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
      end
      if (do_pop) begin
        rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
      end
      // count: +1 on a push-only cycle, -1 on a pop-only cycle, unchanged
      // on simultaneous push+pop (full-duplex) or when neither happens.
      case ({do_push, do_pop})
        2'b10:   count <= count + 1'b1;
        2'b01:   count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end

  // The storage array itself is kept in its own, reset-free always_ff
  // block on purpose: a real FIFO's data content never needs to be reset
  // (only the pointers/count do -- stale data behind the read pointer is
  // simply unreachable), and mixing a memory-array write with other
  // signals' asynchronous reset in one always_ff block is exactly what
  // triggers Vivado's "Register has both Set and reset with same
  // priority" warning (Synth 8-7137) during BRAM inference. Separating it
  // out removes the warning and better matches how real memory IP behaves.
  always_ff @(posedge clk) begin
    if (do_push) mem[wr_ptr] <= wr_data;
  end

endmodule : sync_fifo
