//pattern generator for 16 bit RGB565 colour pallette
//outputs are the three colours and the full 2 byte/16 bit pixel information
//Pattern generator works for a 640x480 HDMI screen input
//for other resolutions, the counters must be adjusted (not implemented)
//the main purpose of this pattern generator is to be a flexible dummy input mimicking DVP channels


module RGB565_pattern_single_frame
(
			input																pattern_clk, pattern_reset, pattern_generator_enable,
			input							[1:0]								pattern_selector,
			
			input							[12:0]							horizontal_resolution,						//up to 8192
			input							[11:0]							vertical_resolution,							//up to 4096
			
			output						[4:0]								RGB565_red, RGB565_blue,					//in RGB565, we have red and blue as 5 bits
			output						[5:0]								RGB565_green,									//and green as 6 bits
			output						[15:0]							RGB565_DVP,										//the entire RGB565 output will be r[4:0]g[5:0]b[4:0]
			output															frame_rdy
);

//pattern clock: the speed at which the pattern's each pixel is generated. It is a dummy for the camera's PCLK.
//pattern reset: the start button. Must be pulled HIGH to activate pixel generation. Dummy for a switch.
//pattern ready: goes high when one full pattern is generated. It is a dummy either for when both VSYCNH and HSYNCH are HIGH, or when the snapshot ready camera output goes high.
//RGB565 colours: the RGB565 elements of the pattern generated, published separately
//RGB DVP: the RGB565 data MUXed together into a 2 byte DVP dummy signal


//for debugging resons, currently the generator generates one frame, then keeps on publishing white pixels

			wire																pattern_generetor_clk;
			
			assign pattern_generetor_clk = pattern_clk & pattern_generator_enable;


////////////////Pattern input
//Define counters to run through the pattern itself

			reg 				[12:0] 				Pattern_X;																										//Needs to be more than 8192 to generate AR1820HS equvivalent 4912x3684 (currentl max is 2592x1944 data points)
			reg				[11:0]				Pattern_Y;																										//Needs to be more than 4096 to generate AR1820HS equvivalent 4912x3684 (currentl max is 2592x1944 data points)
			reg										rdy = 0;
		
//The below pattern is for 640x480		
always @(posedge pattern_generetor_clk or posedge pattern_reset) begin
			if (pattern_reset == 1) begin																																			//reset the pattern counters upon receiving a reset
						Pattern_X <= 13'b0;
						Pattern_Y <= 12'b0;
						rdy <= 1'b0;
			end
			else begin																																									//If rdy flag is engaged, only ONE pattern will be generated.
				if(rdy == 0) begin																																					//we use the ready flag to stop pattern generation
						Pattern_X <= (Pattern_X ==(horizontal_resolution - 1)) ? 0 : Pattern_X+1;																	//cycle pattern generator for X - draw a line
						if(Pattern_X== (horizontal_resolution - 1)) Pattern_Y <= (Pattern_Y==(vertical_resolution - 1)) ? 0 : Pattern_Y+1;			//cycle pattern generator for Y when X is 800 - we are at the end of the line, go to the next line
						rdy <= (Pattern_X==(horizontal_resolution - 1) && Pattern_Y==(vertical_resolution - 1)) ? 1 : 0;									//pattern ready flag
				end
			end
end
	

//Define colour registers (hard wired at 8-bit)
		reg 				[7:0] 				red, green, blue;																			//pixel color 8-bit registers

//Define a pattern variables
		wire 				[7:0] 				W = {8{Pattern_X[7:0]==Pattern_Y[7:0]}};
		wire 				[7:0] 				A = {8{Pattern_X[7:5]==3'h2 && Pattern_Y[7:5]==3'h2}};

////Feed the colour pattern into colour registers
always @(posedge pattern_generetor_clk or posedge pattern_reset) begin
			if (pattern_reset == 1) begin																							//reset the colours upon receiving a reset
						red <= 8'b0;
						green <= 8'b0;
						blue <= 8'b0;
			end else
				if(rdy == 0) begin
						if (pattern_selector == 2'b00) begin
								//wider lines of 4
								//simple debugging pattern output
								red <= ((Pattern_X[3:2] == 2'b0)) ? 8'b11111111: 8'b0;
								green <= ((Pattern_X[3:2] == 2'b01)) ? 8'b11111111: 8'b0;
								blue <= ((Pattern_X[3:2] == 2'b10)) ? 8'b11111111: 8'b0;										
						end		
						
						else if (pattern_selector == 2'b01) begin
								//one colour pixel output test to align output to screen
								//red <= Pattern_X[11:4];
								red <= Pattern_X[12:5];
						end	
						
						else if (pattern_selector == 2'b10) begin
								//one pixel lines of 4 - Red, Green, Blue, Black
								//used for pixel debugging - if burst if lower than 4
								red <= ((Pattern_X[1:0] == 2'b0)) ? 8'b11111111: 8'b0;
								green <= ((Pattern_X[1:0] == 2'b01)) ? 8'b11111111: 8'b0;
								blue <= ((Pattern_X[1:0] == 2'b10)) ? 8'b11111111: 8'b0;									
						end	
						
						else if (pattern_selector == 2'b11) begin
								//full special pattern
								red <= ({Pattern_X[5:0] & {6{Pattern_Y[4:3]==~Pattern_X[4:3]}}, 2'b00} | W) & ~A;		//Generate red pattern
								green <= (Pattern_X[7:0] & {8{Pattern_Y[6]}} | W) & ~A;											//Generate green pattern
								blue <= Pattern_Y[7:0] | W | A;																			//Generate blue pattern											
						end

		//Alternative patterns
						
		//Red, Blue, Green, White
		//						red <= ((Pattern_X[1:0] == 2'b0) || (Pattern_X[1:0] == 2'b11)) ? 8'b11111111: 8'b0;					
		//						blue <= ((Pattern_X[1:0] == 2'b01) || (Pattern_X[1:0] == 2'b11)) ? 8'b11111111: 8'b0;
		//						green <= ((Pattern_X[1:0] == 2'b10) || (Pattern_X[1:0] == 2'b11)) ? 8'b11111111: 8'b0;
		
		
		//	
		//pixel lines of 8
		//used for pixel debugging if burst is higher than 4
		
		//						red <= ((Pattern_X[2:0] == 3'b000) || (Pattern_X[2:0] == 3'b100) || (Pattern_X[2:0] == 3'b110) || (Pattern_X[2:0] == 3'b111)) ? 8'b11111111: 8'b0;
		//						green <= ((Pattern_X[2:0] == 3'b001) || (Pattern_X[2:0] == 3'b100) || (Pattern_X[2:0] == 3'b101) || (Pattern_X[2:0] == 3'b111)) ? 8'b11111111: 8'b0;
		//						blue <= ((Pattern_X[2:0] == 3'b010) || (Pattern_X[2:0] == 3'b101) || (Pattern_X[2:0] == 3'b110) || (Pattern_X[2:0] == 3'b111)) ? 8'b11111111: 8'b0;

		
				
				end else	begin
						red <= 8'b11111111;
						green <= 8'b11111111;
						blue <= 8'b11111111;						
					end
end

//Assign outputs

assign RGB565_red = red[4:0];
assign RGB565_green = green[5:0];
assign RGB565_blue = blue[4:0];
assign RGB565_DVP = {red[4:0], green[5:0], blue[4:0]};																					//we string the registers together
assign frame_rdy = rdy;

endmodule

			//Note:
			//Current resetting and flagging makes it so that the pattern is generated only once fully. Afterwards, all counters are pulled to zero.
			//Outputs are pulled to "undefined" with 8'hZ. This should not allow the next module to get any data out of this module which is not a pattern
			//Second time we want to generate a pattern, the module must be resetted.
			//Also, while the reset signal is active, the pattern will generate a full blank output. This blank will be considered as output. Thus, resetting should last just one cycle


