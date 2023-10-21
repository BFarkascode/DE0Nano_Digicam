//This an updated and modified clock divider that should be less sensitive to metastability

//It is slightly modified in a sense that it can time the first clock posedge it initiates.
//Initial clock count starts from 10 instead of 0 for the 16 clock divider. This will make the first generated clock arrive on the 4th falling edge of SPI_SCK.
//Changing the initial clock count moves the first posedge. Starting from 14 will make the transfer_clock will tick the first time on the last SCK falling edge of the START_READOUT command.


module mod_upd_clock_divider
#(
		parameter MODULO = 50000000
)
(
		input 			clk,
		input 			rst,
		output			tick

);

localparam WIDTH = (MODULO == 1) ? 1 : $clog2(MODULO);

reg [WIDTH-1:0] count =0;

assign tick = (count == MODULO - 1) ? 1'b1 : 1'b0;

always @ (posedge clk or posedge rst) begin
	if (rst == 1'b1) begin
		count <= 10;
	end else begin
		count <= count +1;
	end
end 

endmodule