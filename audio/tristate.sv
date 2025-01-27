// from lab6

module tristate #(N = 16) (
	input logic Clk, 
	input logic tristate_write_enable,
	input logic [N-1:0] Data_write, // Data from Mem2IO
	output logic [N-1:0] Data_read, // Data to Mem2IO
	inout wire [N-1:0] Data // inout bus to SRAM
);

// Registers are needed between synchronized circuit and asynchronized SRAM 
logic [N-1:0] Data_write_buffer, Data_read_buffer;

always_ff @(posedge Clk)
begin
	// Always read data from the bus
	Data_read_buffer <= Data;
	// Always updated with the data from Mem2IO which will be written to the bus
	Data_write_buffer <= Data_write;
end

// Drive (write to) Data bus only when tristate_write_enable is active.
assign Data = tristate_write_enable ? Data_write_buffer : {N{1'bZ}};

assign Data_read = Data_read_buffer;

endmodule