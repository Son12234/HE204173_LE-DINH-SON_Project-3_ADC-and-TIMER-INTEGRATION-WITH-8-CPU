// =============================================================================
// File   : dmem.sv
// Purpose: Data RAM, 256 bytes x 8 bits. The top 16 bytes (0xF0-0xFF) are
//          logically reserved for the I/O page once IO_ENABLE=1 in the core,
//          but that gating is done by the core's MEM stage (it simply never
//          asserts 'we' for an I/O-page address); dmem itself stays a plain,
//          fully generic 256-byte RAM so it is reusable unmodified by both
//          the IO_ENABLE=0 (stand-alone CPU regression) and IO_ENABLE=1
//          (SoC) configurations, exactly as the guide's file table shows
//          dmem.v carried over "unchanged".
// =============================================================================
import risc8_pkg::*;

module dmem (
  input  logic                   clk,
  input  logic                   we,      // write enable, already gated by (!io_hit) upstream
  input  logic [ADDR_W-1:0]      addr,
  input  logic [DATA_W-1:0]      wdata,
  output logic [DATA_W-1:0]      rdata
);

  logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];   // 256 x 8-bit array

  initial begin
    for (int i = 0; i < (1<<ADDR_W); i++) mem[i] = '0;   // known state for simulation
  end

  // Synchronous write: a store commits one clock after it is issued, same
  // as every other pipeline register in the design.
  always_ff @(posedge clk) begin
    if (we) mem[addr] <= wdata;
  end

  // Combinational read ("single-cycle bus" behavior required by the MEM
  // stage, matching the timer/ADC peripheral's own read timing).
  assign rdata = mem[addr];

endmodule : dmem
