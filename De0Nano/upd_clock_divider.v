//This an updated clock divider that should be less sensitive to metastability


module upd_clock_divider
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
		count <= 0;
	end else begin
		count <= count +1;
	end
end 

endmodule
