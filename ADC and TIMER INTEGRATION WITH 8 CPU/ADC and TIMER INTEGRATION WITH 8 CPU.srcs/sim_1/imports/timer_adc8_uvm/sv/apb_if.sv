`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

interface apb_if ( // Declare 8-bit APB interface bundle
    input logic clk,   // System clock input
    input logic rst_n  // Active-low asynchronous reset input
); // End of interface port list

    logic       psel;    // Peripheral select signal driven by master
    logic       penable; // Enable phase signal driven by master
    logic       pwrite;  // Transfer direction: 1 = write (ST), 0 = read (LD)
    logic [3:0] paddr;   // 4-bit register address (0x0 to 0xF)
    logic [7:0] pwdata;  // 8-bit write data bus driven by master
    logic [7:0] prdata;  // 8-bit read data bus driven by peripheral slave
    logic       pready;  // Slave ready handshake output (1 = single-cycle ready)
    logic       pslverr; // Slave error output (1 = illegal write to RO register)
    logic       irq;     // Peripheral interrupt request output to CPU

    task automatic reset_bus(); // Initialize all master-driven APB signals to idle
        psel    <= 1'b0;        // Deassert peripheral select
        penable <= 1'b0;        // Deassert enable signal
        pwrite  <= 1'b0;        // Set direction to read by default
        paddr   <= 4'h0;        // Clear address bus to 0x0
        pwdata  <= 8'h00;       // Clear write data bus to 0x00
    endtask // End of reset_bus task

    task automatic write_reg(input logic [3:0] addr, input logic [7:0] data, output logic err); // 1-cycle write
        @(posedge clk);         // Synchronize to rising clock edge
        psel    <= 1'b1;        // Assert peripheral select
        penable <= 1'b1;        // Assert enable for single-cycle transfer
        pwrite  <= 1'b1;        // Select write operation
        paddr   <= addr;        // Drive target register address
        pwdata  <= data;        // Drive 8-bit write payload
        @(posedge clk);         // Wait for active clock edge to commit write
        err      = pslverr;     // Capture slave error response before deasserting
        psel    <= 1'b0;        // Deassert peripheral select after transfer
        penable <= 1'b0;        // Deassert enable after transfer
        pwrite  <= 1'b0;        // Clear write control signal
    endtask // End of write_reg task

    task automatic read_reg(input logic [3:0] addr, output logic [7:0] data, output logic err); // 1-cycle read
        @(posedge clk);         // Synchronize to rising clock edge
        psel    <= 1'b1;        // Assert peripheral select
        penable <= 1'b1;        // Assert enable for single-cycle transfer
        pwrite  <= 1'b0;        // Select read operation
        paddr   <= addr;        // Drive target register address
        pwdata  <= 8'h00;       // Keep write data bus at zero during read
        @(posedge clk);         // Wait for clock edge where prdata is valid
        data     = prdata;      // Sample 8-bit read data from peripheral
        err      = pslverr;     // Capture slave error status
        psel    <= 1'b0;        // Deassert peripheral select after read
        penable <= 1'b0;        // Deassert enable after read
    endtask // End of read_reg task

endinterface // End of apb_if interface