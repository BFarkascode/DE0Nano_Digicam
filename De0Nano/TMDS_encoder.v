//TMDS encoder module. Turns incoming pixel data into TMDS encoded version.
//TMDS is a 10-bit data fortmat that include 8 bit of pixel data, plus 2 control bits.
//Depending on VDE flag value, we either send the 8 bit pixel data or the 2 bit control data, but never both


module TMDS_encoder(
	input 							TMDS_local_clk,		//module's local clock
	input 		[7:0] 			VD,  			// video data (red, green or blue)
														//this is the 8 bit pixel data
	input 		[1:0] 			CD,  			// control data
														//this is the 2 bit control daya
	input 							VDE,  		// video data enable, to choose between CD (when VDE=0) and VD (when VDE=1)
														//depending on VDE flag value, we either send the control 2 bits or the 8 bits pixel data. We don't send them both at the same time
	output 	reg [9:0] 			TMDS = 0		//this is the output that will leave the encoder
);

wire 				[3:0] 			Nb1s = VD[0] + VD[1] + VD[2] + VD[3] + VD[4] + VD[5] + VD[6] + VD[7];
wire 									XNOR = (Nb1s>4'd4) || (Nb1s==4'd4 && VD[0]==1'b0);
wire 				[8:0] 			q_m = {~XNOR, q_m[6:0] ^ VD[7:1] ^ {7{XNOR}}, VD[0]};

reg 				[3:0] 			balance_acc = 0;
wire 				[3:0] 			balance = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7] - 4'd4;
wire 									balance_sign_eq = (balance[3] == balance_acc[3]);
wire 									invert_q_m = (balance==0 || balance_acc==0) ? ~q_m[8] : balance_sign_eq;
wire 				[3:0] 			balance_acc_inc = balance - ({q_m[8] ^ ~balance_sign_eq} & ~(balance==0 || balance_acc==0));
wire 				[3:0] 			balance_acc_new = invert_q_m ? balance_acc-balance_acc_inc : balance_acc+balance_acc_inc;

wire 				[9:0] 			TMDS_data = {invert_q_m, q_m[8], q_m[7:0] ^ {8{invert_q_m}}};
wire 				[9:0] 			TMDS_code = CD[1] ? (CD[0] ? 10'b1010101011 : 10'b0101010100) : (CD[0] ? 10'b0010101011 : 10'b1101010100);

always @(posedge TMDS_local_clk) TMDS <= VDE ? TMDS_data : TMDS_code;							//If VDE is HIGH, we publish the TMDS_data. If note, the TMDS_code
always @(posedge TMDS_local_clk) balance_acc <= VDE ? balance_acc_new : 4'h0;


endmodule