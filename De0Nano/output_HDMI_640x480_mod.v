//This is the separated module for the HDMI output at 640x480 resolution
//Be aware that HDMI at 640x480 has standards (VGA) that must be met
//As such, the pixel clock coming into the module must always be 25 MHz and the bit clock, 250 MHz
//Failing to meet these requirements likely leads to failure

module output_HDMI_640x480_mod (																										
		input									pixel_clk, bit_clk, screen_reset,				//The two clocks. Pixel clock defines the frequency of a pixel, bit clock defines the 10-bit TMDS value of that pixel
																											//Bit clock is always 10 times the pixel clock due to how TMDS encoding works
																											//screen reset is to remove pattern creep and always publish the same 640x480 piece of the 800x525 pattern
																										
		input									HDMI_output_enable,
		
		input				[7:0]				red_input_HDMI, blue_input_HDMI, green_input_HDMI,									//The three colour inputs, each 8-bit wide
		output			[2:0]				TMDS_encoded_out,										//The TMDS encoded output. For HDMI, this is a differential output pair.
		output								TMDS_encoded_clk										//The "TMDS encoded" clock. In reality, this is not encoded at all, but will simply be the pixel clock. Runs through module without change for ease of understanding.
																											//Important to note that the output will need to be defined as LVDS outputs.
																											//For Altera devices, this is defined within the pin planner by picking LVDS as pin output type in the planner. The pair will be assigned automatically.
																											//For Xilinx, this is done through OBUFDS buffer primitives.
																											//Mind, the pairs can be generated just in one way, thus we can't randomly pick one for negative pair and the other, positive pair.

);

//On/off control
		wire								HDMI_pixel_clk;
		
		assign HDMI_pixel_clk = pixel_clk & HDMI_output_enable;
		

		wire								HDMI_bit_clk;
		
		assign HDMI_bit_clk = bit_clk & HDMI_output_enable;



/////////////////
//Define the image itself using the counters - 640 x 480 pixel with 800 x 525 image size - porches included
//Section runs at PIXEL CLOCK

		reg 				[9:0] 			Count_X, Count_Y;									//counters to go through the image area
		reg 									hSync, vSync, Img_Area;							//hsynch and vsynch and an area flag
																										//the area flag will be fed into the TMDS encoder to tell, when we are encoding pixel data (image area) or command data (outside the image area)
always @(posedge HDMI_pixel_clk) Img_Area <= (Count_X<640) && (Count_Y<480);			//area flag is HIGH when counter is within 640 x 480 - ignores front porch

always @(posedge HDMI_pixel_clk or posedge screen_reset) begin
		if (screen_reset == 1) begin
			Count_X <= 10'b0;
			Count_Y <= 10'b0;
		end else begin
			Count_X <= (Count_X==799) ? 0 : Count_X+1;			//cycle counter for X
			if(Count_X==799) Count_Y <= (Count_Y==524) ? 0 : Count_Y+1;
		end
end

always @(posedge HDMI_pixel_clk) hSync <= (Count_X>=656) && (Count_X<752);			//back porch definition - hsynch HIGH for 96 columns (back porch) - 48 columns are the front porch
always @(posedge HDMI_pixel_clk) vSync <= (Count_Y>=490) && (Count_Y<492);			//side porch definition - vsynch HIGH for 2 lines (side porch after image) - 33 lines before image



////////////////
//Encode the data into TMDS by using function
//Section runs at PIXEL CLOCK

wire 						[9:0] 				TMDS_red, TMDS_green, TMDS_blue;

TMDS_encoder encode_R(
						.TMDS_local_clk(HDMI_pixel_clk),
						.VD(red_input_HDMI),
						.CD(2'b00),
						.VDE(Img_Area),
						.TMDS(TMDS_red));
						
TMDS_encoder encode_G(
						.TMDS_local_clk(HDMI_pixel_clk),
						.VD(green_input_HDMI),
						.CD(2'b00),
						.VDE(Img_Area),
						.TMDS(TMDS_green));
						
TMDS_encoder encode_B(
						.TMDS_local_clk(HDMI_pixel_clk),
						.VD(blue_input_HDMI),
						.CD({vSync,hSync}),
						.VDE(Img_Area),
						.TMDS(TMDS_blue));


////////////////
//Generate the output
//Shift tregisters clocking at the bit_clk (10 times faster than the pixel clock)
//Section runs at BIT CLOCK
		reg 				[3:0] 				TMDS_mod10=0;  															//modulus 10 counter
		reg 				[9:0] 				TMDS_shift_red=0, TMDS_shift_green=0, TMDS_shift_blue=0;		//three empty shift registers for the three TMDS encoded signals
		reg 										TMDS_shift_load=0;														//flag to load the shift registers


always @(posedge HDMI_bit_clk) TMDS_shift_load <= (TMDS_mod10==4'd9);											//if the counter reached 4'd9 (which is decimal 9 at 4 bits, mind), we put the shift load flag HIGH

always @(posedge HDMI_bit_clk)
		begin
			TMDS_shift_red   <= TMDS_shift_load ? TMDS_red   : TMDS_shift_red  [9:1];						//if the flag is HIGH, we load the shift registers. Otherwise, we flush them out.
			TMDS_shift_green <= TMDS_shift_load ? TMDS_green : TMDS_shift_green[9:1];
			TMDS_shift_blue  <= TMDS_shift_load ? TMDS_blue  : TMDS_shift_blue [9:1];	
			TMDS_mod10 <= (TMDS_mod10==4'd9) ? 4'd0 : TMDS_mod10+4'd1;											//if the counter is at decimal 9, we reset it to 0, otherwise we step it through 0 to 9
		end


////////////////
//Output assignment towards module output
//We assign the number 0 element of the shift registers above towards the outputs of the module
//The outputs will be paired into LVDS outputs upon pin assignment. Just need to connect them up properly
assign 					TMDS_encoded_out[0] = TMDS_shift_blue  [0];														//we always publish the [0] of the shift register above. Since we flush them out with bit_clk, this will result in a signal changing with bit_clk
assign 					TMDS_encoded_out[1] = TMDS_shift_green  [0];
assign 					TMDS_encoded_out[2] = TMDS_shift_red  [0];
assign					TMDS_encoded_clk = pixel_clk;

endmodule