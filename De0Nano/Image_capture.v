//Functioning image capture module
//Adjusted to run on a DE0Nano board with a Cyclone IV and an IS42S16160J SDRAM


//Output full synchronous and hard-wired to be a 25 MHz VGA HDMI for a screen (800x525 pixels)
//Input is asynchronous and can be anything in speed up to 25 MHz
//Input can be fine with higher frequencies too (up to 35 MHz) if the write side FIFO size is manually increased (can be as high as size 15 on a Cyclone IV). This is not recommended.
//Input maximum size is currently 800x525. Due to how elements are logged in a block of 32, all typical resolutions below that are fine. If needed be, 800x600 is also okay with some minor data loss. Not recommended.


//Module expects a 16 bit RGB565 input and its respective pattern clock
//Module expects a 50MHz sys_clk for internal PLL generation
//Module has three external command switches for read only, erase and capture trigger
//Module has a sequential reset, meaning that evertyhing else resets after the SDRAM has been initialized
//Module expects resolution values and the number of pixels to work with (how many pixels are in the image)


//KNOWN BUGS:
//1)Write side control is shaky/crude and could use a rework

//2)When using higher resolutions (1600x1200 and above), we may have a readout issue. Problem can not be debugged without proper image input. X direction is fine so we might be just looking at the wrong part of the image with all the mess coming up...
			//REAPIRED seemingly for 1600x1200 by adjusting the addressing. It fails for 2592x1944. Guess is that we need to deal with bank change there.
					//We are probably just looking at the edge of the image and that's the weird pattern for 800x600 and 1600x1200.
					//It also works for 4096x2048
			//The bug is only obviously recurring for 2592x1944 resolution. It is a write side problem since we don't write into section of the image: when we run at lower resolution, the 2592x1944 version does not overwrite the readout section completely.
			//Guess is that we are stuck in the same bank with 2592x1944 and end up losing 3 MP out of the 2MP.
			//Debugging only possible after data transfer has been succesfully implemented.
			//Workaround is to generate 8MP images and then put the 5MP data in the corner of it, like we do under 800x525.
			//Running a 30x240 input at resolution 1600x1200 brings a result of multiple images at size 14 write side FIFO
			//also, running the setup at 1600x1200 indeed shows that we are in the middle of the image shifting, so no bugs there
			//REPAIRED. Adjusting the HDMI module reset solved the iamge positioning issue. Now it is clear that the only resolution not working properly is 2592x1944.
			//REPAIRED. Logging BMP images shows the same output as seen on the HDMI screen. Reason unknown.
			

module Image_capture

(
			input																sys_clk, init,													//system clock (for DE0Nano, 50 MHz) and init (already inverted reset from top module)
			input																capture_clk,													//data input clock - asymetric to system clock
			input																readout_clk,													//data output clock - potentially asymetric to system clock
			input							[15:0]							write_side_data_input,										//image capture module data input

			input																image_capture_output_enable,								//image capture module output enable
			
			input							[12:0]							horizontal_resolution,										//horizontal resolution register
			input							[11:0]							vertical_resolution,											//vertical resolution register	
			input							[22:0]							pixel_number,													//this is the register to hold the number of pixels we intend to work with - the multiple of horizontal resolution and vertical resolution
																																					//the math is not done within the FPGA since it likely would take too much computing and time
			
			input							[2:0]								resolution_selector,											//this is what we use to pick the resolutions
			input																HDMI_enabled,													//HDMI enable register. Used to switch the readout dyanamics depending on if we have the HDMI module activated or not.
																																							//Note:
																																							//HDMI needs 25 MHz input and exactly 420000 pixels.
																																							//The limitations of the HDMI module does not apply to data transfer. Thus this needs to be controlled on the output of the capture module.
			
			output						[15:0]							read_side_FIFO_out_16bit_wire,							//image capture module data output
			
			//SDRAM
			inout							[15:0]							sd_data_bus,													//SDRAM 16 DQ pins
			
			input																SDRAM_read_only, SDRAM_erase,	reset_trigger,			//SDRAM external control switches
					
			output															dram_clk,														//SDRAM hardware clock
			output															cke,																//clock enable for SDRAM (if needed)
			
			output						[12:0]							sd_addr,															// 13 A pins
			output						[1:0]								sd_ba,															//	2 BA pins
			output						[1:0]								sd_dqm,															// 2 DQM pins
			output															sd_cs,															// CS pin
			output															sd_we,															// we pin
			output															sd_cas,															// cas pin
			output															sd_ras,															// ras pin

			output															image_capture_reset_state,
			output						[7:0]								LED,																//feedback blinky LEDs
			
			output															capture_module_output_active,								//signal used for resetting modules above the capture module when output is coming
			output															probe1, probe2													//probe output
);


////////Module definitions and variables//////////////////

////////////Reset and erase////////////

////Reset definition (reset inversion happens on the top level!)
										
assign 			reset = reset_trigger?  ~SDRAM_initialized : 1'b1;												//sequential reset: everything else after the SDRAM has been initialized
																																	//depending on the capture_trigger input, we are either resetting, or we wait for the SDRAM to be initialized
																																	//capture trigger can be an external trigger one layer above

assign 			image_capture_reset_state = reset;																	//we output the reset signal of the iamge capture module so on the top module things can reset the same time as the image capture module

////SDRAM erase definition


//if resolution_selector_register is > 3'b100, we are above the HDMI limit
																										
			wire							[21:0]							pixel_wire;										//we define a wire for the pixel number
			wire							[12:0]							horizontal_resolution_wire;
			wire							[11:0]							vertical_resolution_wire;			
			
assign 			pixel_wire = (resolution_selector >= 3'b100)? pixel_number : (SDRAM_erase? 22'b0001100110100010011111 : pixel_number);									//the pixel wire should be the same as the original resolution for resolutions greater than 800x525. Under 800x525, when we erase, it should be 800x525 otherwise it should be the defined PIXEL_NUMBER parameter
assign 			horizontal_resolution_wire = (resolution_selector >= 3'b100)? horizontal_resolution : (SDRAM_erase? 800 : horizontal_resolution);					//the horizontal resolution wire should be the same as the original resolution for resolutions greater than 800x525. Under 800x525, when we erase, it should be 800x525 otherwise it should be the defined HORIZONTAL_RESOLUTION parameter
																																																					//we have 1024 here so we are working in two full pages
assign 			vertical_resolution_wire = (resolution_selector >= 3'b100)? vertical_resolution : (SDRAM_erase? 525 : vertical_resolution);							//the vertical resolution wire should be the same as the original resolution for resolutions greater than 800x525. Under 800x525, when we erase, it should be 800x525 otherwise it should be the defined VERTICAL_RESOLUTION parameter

											//Note:
											//			resolution_selector >= 3'b100 means resolutions above 800x525. Since 800x525 is our standard HDMI resolution, we need to divide the functions there.
											
assign 			write_side_FIFO_in_16bit_wire = SDRAM_erase ? 16'b0 : write_side_data_input;																							//empty input when erasing																																										

										
////////////Reset and erase////////////
																														
////////////Write side FIFO////////////

			wire 		      												write_side_r_en;	

			wire          													write_side_w_en;
			
			wire																write_side_r_empty;
			
			wire																write_side_r_almost_empty;

			wire																write_side_w_full;

			wire																write_side_w_almost_full;

			wire							[15:0]							write_side_FIFO_in_16bit_wire;				//write side FIFO input
			
			wire							[15:0]							write_side_FIFO_out_16bit_wire;				//write side FIFO output
				
			
working_FIFO_mod # (
				.DATA_SIZE(16),									
//				.ADDR_SIZE(6),											//size 8 is enough for 320x240				
//				.ALMOST_FULL_FLAG_POS(18),
//				.ALMOST_EMPTY_FLAG_POS(31)
				.ADDR_SIZE(10),			
				.ALMOST_FULL_FLAG_POS(400),
				.ALMOST_EMPTY_FLAG_POS(511)

) write_side_FIFO (
				//input
				.w_data(write_side_FIFO_in_16bit_wire),   	// FIFO input							

				//write control
				.w_en(write_side_w_en),							// Write domain enable       				
				.w_clk(capture_clk),								// Write domain clock
				.w_rst(w_rst),      								// Write reset

				//read control
				.r_en(write_side_r_en),       				// Read data and increment addr.
				.r_clk(ram_clk_100MHz),      					// Read domain clock. It must clock with SDRAM driver clock to capture/provide all the bursting elements.
				.r_rst(r_rst),      								// Read domain reset. Same as all other reset.
				
				//output flags
				.w_full(write_side_w_full),     				// Used only for debugging
				.w_almost_full(write_side_w_almost_full),				
				.r_empty(write_side_r_empty),					// Used only for debugging
				.r_almost_empty(write_side_r_almost_empty),	
				
				
				//output
				.r_data(write_side_FIFO_out_16bit_wire)     // Data to be read from FIFO
);



////////////Write side FIFO////////////



////////////SDRAM implementation//////////////

//set up the variables towards the SDRAM
			reg 							[15:0]  							data_from_sdram;								//SDRAM hardware output 16 bit latch - DQ pins
			wire							[15:0]  							data_to_sdram; 								//SDRAM hardware input 16 bit latch - DQ pins

//registers and wires to run the SDRAM driver itself																						
			reg							[3:0]								dqm = 4'b0;										//SDRAM masking - not used
			reg							[25:0]							addr = 26'b0;									//SDRAM address

			wire							[15:0]							SDRAM_out_16bit_wire;							//SDRAM driver output
			wire							[15:0]							din;												//SDRAM driver input
			
			reg																ram_we = 1'b0;									//write enable on the SDRAM driver				
			wire																ram_oeA;											//read enable on the SDRAM driver
		
			wire							[3:0]								q_debugger;
																					
////SDRAM call
SDRAM_driver_scope #(
				.BURST_LENGTH(BURST_LENGTH),
				.BURST_TYPE(BURST_TYPE)
)
SDRAM_w_burst(
				//hardware data input/output
				.data_from_sdram(data_from_sdram), 					// data that is being received from the SDRAM
				.data_to_sdram(data_to_sdram),						// 16 bit bidirectional data bus			

				//hardware control registers
				.sd_addr(sd_addr),    									// A12-A0
				.sd_dqm(sd_dqm),     									// two byte masks															
				.sd_ba(sd_ba),      										// BA1-BA0
				.sd_cs(sd_cs),     										// CS pin
				.sd_we(sd_we),      										// WE pin
				.sd_ras(sd_ras),     									// RAS pin
				.sd_cas(sd_cas),     									// CAS pin
				.init(init),	    										// init/reset flag
				.fpga_clk(ram_clk_100MHz),								// Driver internal clock
				.clkref(sys_clk),	   									// referece clock or top level (integration) clock = whatever is above the module, will be clocking with this clkref

				//driver control registers
				.addr(addr),       										// 26 bit byte address												
				.din(write_side_FIFO_out_16bit_wire),					//now erasing should occur before the write side FIFO																							
				.we(ram_we),												// write enable flag - it will be "we", not ram_we
				.dqm(dqm),        										// data byte write mask
				.oeA(ram_oeA),        									// read enable pin
				.dout(SDRAM_out_16bit_wire),
				
				//driver cycle flags
				.write_cycle_over(write_cycle_over),
				.read_cycle_over(read_cycle_over),
				.idle_cycle_over(idle_cycle_over),
				.interrupt_cycle_over(interrupt_cycle_over),		//not used
				
				//driver input/output signals
				.input_ready(ram_write_start),	
				.output_ready(ram_read_start),						// ready flag for the read side of the SDRAM
				
				//driver control signals
				.top_level_reset(reset),								//not used
				.h_synch(h_synch),
//				.change_page(change_page),								//not used
				.write_is_interrupted(write_is_interrupted),		//not used
				.SDRAM_initialized(SDRAM_initialized),				//will be HIGH when the SDRAM is initialized. Used to sequentially reset the setup.
				
				//debug tools(only for probing)
				.q_debugger(q_debugger)
);
	
//Clock enable assignment
assign 			cke = 1'b1;

//SDRAM hardware clocking
assign 			dram_clk = ram_clk_100MHz;

//Assignment for the DQ bidirectional data bus
//write side: DQs are inputs
//assign 			sd_data_bus = ram_we == 1? data_to_sdram : 16'hZZZZ; ram_write_start

//REPLACED
assign 			sd_data_bus = ram_write_start == 1? data_to_sdram : 16'hZZZZ;

//read side: DQs are outputs
always @ (posedge ram_clk_100MHz) data_from_sdram <= sd_data_bus;	

////////////SDRAM implementation//////////////



////////////Read side FIFO implementation//////////////

			reg            												read_side_r_en = 0;
			wire            												r_rst = reset;
			wire           												read_side_w_en;
			wire            												w_rst = reset;

			wire																read_side_r_empty;				//read pointer clocks at PIXEL_CLK!!!!!!
			wire																read_side_r_almost_empty;
			wire																read_side_w_full;					//write pointer clocks at RAM_CLK!!!!!!
			wire																read_side_w_almost_full;		


working_FIFO_mod # (
				.DATA_SIZE(16),														// We need 16 elements in a row
				.ADDR_SIZE(4),															// Changing the size of the FIFO will change the amount of pixels we store and then burst.
																							// addr 3 with flag pos 5 will be the only one capable to show the flags changing at debugging. All other cases will be hidden due to full sunch behaviour
																							// addr 3 with flag pos 5 generates so much radio noise that it messes up the radio in the kitchen
																							// in general, the breadboard model can be messed up by touching the trigger wire
																							// addr 8 is used so when we change to SPI - a readout clock that is potentially only 500 kHz, 50 times slower than the write clock - we will not have the almost flags asserted the same time for sure
																							
																							// with good almost flag control, the size of the read side FIFO could potentially be decreased
																							// addr 3 does not work with the flagging. addr 4 works with manual data extraction as well as HDMI.
				.ALMOST_FULL_FLAG_POS(5),											// we burst for 4
				.ALMOST_EMPTY_FLAG_POS(5)
				
) read_side_FIFO (
				//inputs
				.w_data(SDRAM_out_16bit_wire),     								// Data to be written to FIFO. This will be sampled. Clocks (currently) at PIXEL_CLK!!!!!!!! Will be the SDRAM driver's clock eventually.
				.w_en(read_side_w_en),       										// Write data and increment addr. This will trigger the sampling.
				.w_clk(ram_clk_100MHz),												// Write domain clock. This is the sampling clock of the FIFO write side.
				.w_rst(w_rst),      													// Write domain reset
				.r_en(read_side_r_en),       										// Read data and increment addr.
				.r_clk(readout_clk),      											// Read domain clock.
				.r_rst(r_rst),      													// Read domain reset
				
				//outputs
				.w_full(read_side_w_full),     									// Flag for FIFO is full
				.w_almost_full(read_side_w_almost_full),
				.r_data(read_side_FIFO_out_16bit_wire),    					// Data to be read from FIFO
				.r_almost_empty(read_side_r_almost_empty),			
				.r_empty(read_side_r_empty)										// not used
);



////////////Read side FIFO implementation//////////////


////////////PLLs, Clocks//////////////

		wire																		unload_clk_25MHz;										// 25 MHz - necessary to match bursting of 4 with a state machine clocking at 100 MHz, stepping 16 times (4 x 100 / 16).
		
PLL_25MHz PLL25 (
			.inclk0(sys_clk),
			.c0(unload_clk_25MHz)
);


			wire 																	ram_clk_100MHz;									// 100 MHz
		
PLL_100MHz PLL100 (
			.inclk0(sys_clk),
			.c0(ram_clk_100MHz)
);
		


////////////PLLs, Clocks//////////////

////////////SDRAM driver state machine flag counters////////////

//Write state counter
			reg					[1:0]					write_counter = 2'b0;

always @ (posedge write_cycle_over or posedge reset) begin
	if (reset == 1) begin
		write_counter <= 2'b0;
	end
	else write_counter <= write_counter + 1'b1;
end


//Read state counter
			reg					[1:0]					read_counter = 2'b0;

always @ (posedge read_cycle_over or posedge reset) begin
	if (reset == 1) begin
		read_counter <= 2'b0;
	end
	else read_counter <= read_counter + 1'b1;
end


//Idle state counter
			reg					[2:0]					idle_counter = 3'b0;
			reg											SDRAM_is_idle = 1'b1;
						
always @ (posedge idle_cycle_over or posedge reset) begin
	if (reset == 1) begin
		idle_counter <= 3'b0;
		SDRAM_is_idle <= 1'b1;
	end
	else begin
		idle_counter <= idle_counter + 1'b1;
		SDRAM_is_idle <= 1'b1;
		if (idle_counter == 3'b111) SDRAM_is_idle <= 1'b0;
	end	
end

////////////SDRAM driver idle state machine flag counters////////////



/////////////////////////////////////////////////////////////////////////////////////////////////


		
/////////////////Command and control systems////////////////////

			localparam									BURST_LENGTH 	= 9'b111111111;
//			localparam									BURST_LENGTH 	= 9'b11111;							//Used as an adjustment tool for the SDRAM driver. Should be kept as 9'b1111		-	burst for 32
																														//Note: burst is currently set to 32. Some tests indicate that 16 may actually be more stabile.
			localparam									BURST_TYPE	   = 3'b111;								//Used as an adjustment tool for the SDRAM driver. Should be kept as 3'b111		-	full page burst
			localparam									WRITE_SIDE_BLOCK_SIZE		= 5'b11111;			//write side block size is adjusted to 32 since it is the biggest common divider amongst typical resolutions. Burst length must be a divider of the block size (currently both are 32).
			localparam									READ_SIDE_BLOCK_SIZE		= 3'b111;				//read side block size is set to 8. This is NOT (!) adjustable but lifted out of context for clarity's sake.
																														//why is the read size set to 8 constanly? Because we need that 4 to be constant for the debugging interface and another 4 for slack when we control the read side.
																														//Also, currently we do not pursue any speed on the read side - on the contrary, actually. 4 should be fine speedwise, since it is already 25 MHz. We do need to go higher to have some slack for control.
			
////Write side control////
								//Note:
								//We enable writing in the write_side_FIFO when the capture trigger goes HIGH. We enable reading from the write_side_FIFO when the write cycle of the SDRAM driver is in the appropriate phase.
								//We read from the write_side_FIFO in block of 32 (32 burst write on the SDRAM activated). We read this 32 element from the write_side_FIFO when we have counted 32 elements coming into it.
								//We also count the 32 elements leaving the write_side_FIFO. While that is going on, we generate a flag that prevents ram_we to go LOW accidentally.



//Assignments to connect the enable signals of the write_side_FIFO

assign 			write_side_r_en = ram_write_start;														//we open the FIFO the moment we start writing with the SDRAM driver
assign 			write_side_w_en = reset_trigger;															//write side FIFO uses an external trigger


//Write_side_FIFO harmonization
			
//			reg											write_side_FIFO_ready = 1'b0;			//signal to indicate that we have the right amount of elements writtent into the write side FIFO already
//			reg					[5:0]					write_side_input_counter = 6'b0;		//counter for the incoming elements - set to 64, in case we accidently move past 32 (we don't want to loop accidentally)


//Note: 	We log the elements in 32 element blocks. This is because 32 is the biggest number that, once divided with all common horizontal resolutions, we get an integer.
//			Current iteration generates the 32 block as 1 x 32 burst. It is possible to generate it as also as 2 x 16 or 4 x 8, albeit these version will be slower (4 x 8 is exactly half as fast as 1 x 32)
	
//always @ (posedge capture_clk or posedge reset or posedge write_block_logged_flag) begin
//	if (reset == 1) begin
//		write_side_FIFO_ready <= 1'b0;
//		write_side_input_counter <= 6'b0; 
//	end
//	else if(write_block_logged_flag == 1) begin
//		write_side_FIFO_ready <= 1'b0;										//we temporarily close the FIFO when we have read a 32 element sized block from it
//		end
//	else begin
//		write_side_input_counter <= (write_side_w_en) ? write_side_input_counter + 1 : 6'b0;
//		if(write_side_input_counter >= WRITE_SIDE_BLOCK_SIZE) begin													//we ready the FIFO when we have a full block of 32 elements already in it
//			write_side_FIFO_ready <= 1'b1;
//			write_side_input_counter <= 6'b0;
//		end
//	end	
//end 



//the problem is here above, where we don't reactivate the write side FIFO fast enough
//at 24 MHz, it will take 750 kHz to load 32 elements
//rework part above and remove the asyncronous write_block_logged_flag



//Write side trigger

		reg											write_side_FIFO_ready = 1'b0;														//signal to indicate that the read side FIFO is ready to receive the next burst of data

always @ (posedge write_side_w_almost_full or posedge write_side_r_almost_empty or posedge reset) begin
		if (reset == 1) write_side_FIFO_ready <= 1'b0;
		else begin
			if (write_side_w_almost_full == 1) write_side_FIFO_ready <= 1'b1;
			else begin
				if (write_side_r_almost_empty == 1) write_side_FIFO_ready <= 1'b0;
			end		
		end
end
	
		
//Read_side_FIFO_ready control//

//always @ (posedge reset or posedge read_side_r_en or posedge read_side_w_full or posedge read_side_r_almost_empty or posedge read_side_almost_full_signal) begin																															
//			if (reset == 1) read_side_FIFO_ready <= 1'b1;
//			else begin
//				if (read_side_r_en == 1'b1) begin
//					if (read_side_almost_full_signal == 1) read_side_FIFO_ready <= 1'b0;										//this may or may not work. Can't be tested without an appropraitely slow readout clock. It should work actually.
//					else if (read_side_r_almost_empty == 1'b1) read_side_FIFO_ready <= 1'b1;								//if it does, read side FIFO side could be decreased. Optimization?
//				end
//				else if (read_side_w_full == 1 ) read_side_FIFO_ready <= 1'b0;													//we shut off ram_oeA if the FIFO is full in the setup phase. If we don't we lose data initially.
//			end
//		end		
//								//Note:
								//Since the flags are just indicators, we define a signal that will keep the flag's indication after the flag has gone LOW
								//We only apply this to the almost_full flag. If we are too slow for the almost_empty - i.e. if we load the FIFO too slow and the read_side r_clk catches up - signal definition would not help speed up the loading of the FIFO.
								//With the almost_full, this is not the case. We can slow down the loading - or stop it temporarily - to cater to a slow read_side r_clk.
		
//			reg													write_side_almost_full_signal = 1'b0;
//		
//always @ (posedge write_side_w_almost_full or posedge write_side_r_almost_empty or posedge reset) begin
//		if (reset == 1) read_side_almost_full_signal <= 1'b0;
//		else begin
//			if (read_side_w_almost_full == 1) read_side_almost_full_signal <= 1'b1;
//			else begin
//				if (read_side_r_almost_empty == 1) read_side_almost_full_signal <= 1'b0;
//			end		
//		end
//end







////Write trigger control for the SDRAM driver and hardware

always @ (posedge ram_clk_100MHz or posedge reset) begin
	if (reset == 1) begin
		ram_we <= 1'b0;		
	end
	else ram_we <= (writing_done || write_is_interrupted || !write_side_FIFO_ready) ? 1'b0 : 1'b1;		//we don't write when we are reading, when we are interrupted or when the write side FIFO is not ready
end

//implement a reset for the write pixel counter when we have an image coming in. Image active will be on the image_data_active input

////Write side pixel counter - we count pixels IN PARALLEL to the burst
					//Note:
					//Pixel is being used to describe the 16 bit input and output for the SDRAM here. They are just data points of any sort.
					//This reflects on the variables too. At any rate, this is just a naming choice and does not reflect on the actual type of data we extract from the SDRAM.

			reg						[21:0]								write_pixel_counter = 22'b1000000000;
			
			reg																v_synch = 1'b0;																					//frame is ready flag
			reg																h_synch = 1'b0;																					//image row is active flag
//			reg																change_page = 1'b0;
		
			reg						[12:0]								write_side_horizontal_counter = 13'b0;
			reg						[11:0]								write_side_vertical_counter = 12'b0;

			reg						[8:0]									w_logged_element_counter = 9'b0;
			reg																write_block_logged_flag = 1'b0;																						//flag to interrupt a write burst when we have reached the end of the image line
		
//always @ (posedge ram_clk_100MHz or posedge reset) begin																												//Read side needs to clock 4 times the speed of the state machine to "skip" the burst pixels
//		if (reset == 1) begin																																					//we reset when we reset, or when we don't have an active frame coming in yet. Only applicable to when the image loader is active.
//			write_pixel_counter <= 22'b0;																																		//page counter is [22:9], column counter is [8:0]
//			v_synch <= 1'b0;
//			h_synch <= 1'b0;
////			change_page <= 1'b0; 
//			write_side_horizontal_counter <= 13'b0;
//			write_side_vertical_counter <= 12'b0;
//			w_logged_element_counter <= 9'b0;
//			write_block_logged_flag <= 1'b0;
//		end
//		else begin		
//			if (ram_write_start == 1'b1) begin		
//			
//			//write side pixel counter control
//				write_pixel_counter <= (write_pixel_counter == pixel_wire)? 0 : 
//											  (write_side_horizontal_counter == (horizontal_resolution_wire - 1))? ((resolution_selector >= 3'b100)? write_pixel_counter + 1'b1 : (write_pixel_counter + (800 - (horizontal_resolution_wire - 1)))) : 		//the 800 part is there to jump the write pixel counter to 800 in case we have a smaller input than the mimimum HDMI 800x525 resolution
//																																																																												//it is there to provide a "padding" for smaller images when we read out the data below into the HDMI module
//																																																																												//for bigger resolutions, it is practically meaningless and need to be bypassed
//											  (write_pixel_counter + 1'b1);	
//											  
//			//resolution control
//				write_side_horizontal_counter <= (write_side_horizontal_counter == (horizontal_resolution_wire - 1))? 0 : write_side_horizontal_counter + 1'b1;		
//				if(write_side_horizontal_counter == (horizontal_resolution_wire - 1)) write_side_vertical_counter <= (write_side_vertical_counter == (vertical_resolution_wire - 1)) ? 0 : write_side_vertical_counter + 1;	
//				
//			//read transition control
//				if((write_side_horizontal_counter==(horizontal_resolution_wire - 1)) && (write_side_vertical_counter == (vertical_resolution_wire - 1)) || (write_pixel_counter == pixel_wire)) v_synch <= 1'b1;		
//			
//			//burst control
//				w_logged_element_counter <= w_logged_element_counter + 1;											//counter for the elements that are being logged
//			
//			end else w_logged_element_counter <= 9'b0;			//ADDED else element to zero out the element counter when we are not writing. Reason: we might keep it at a value non zero at the end of the loop.
//																							//Note: this forces the setup to only run at 32 burst mode. In any other scenario, we are constantly zeroing out the counter an the FIFO doesn't stop spewing data at the SDRAM.
//			
//			//interrupt control
////			change_page <= (w_logged_element_counter == (512 - 1)) ? 1 : 0;														//we need a forced interrupt at page change. Since we burst for 32, page change should always fall between write cycle bursts
//																																				//currently not used
//			h_synch <= (write_side_horizontal_counter == (horizontal_resolution_wire - 1)) ? 1 : 0;								//horizontal resolution should always be a multiple of 32 (applies to all standard resolutions)
////			write_block_logged_flag <= (w_logged_element_counter == WRITE_SIDE_BLOCK_SIZE) ? 1 : 0;				//flag to indicate that a block of elements have been logged into the SDRAM
//		end
//end
//
//		wire																	change_page;
//
//assign change_page = (w_logged_element_counter == (512 - 1)) ? 1 : 0;
////assign change_page = (w_logged_element_counter == (32 - 1)) ? 1 : 0;


always @ (posedge write_cycle_over or posedge reset) begin																												//Read side needs to clock 4 times the speed of the state machine to "skip" the burst pixels
		if (reset == 1) begin																																					//we reset when we reset, or when we don't have an active frame coming in yet. Only applicable to when the image loader is active.
			write_pixel_counter <= 22'b1000000000;																																		//page counter is [22:9], column counter is [8:0]
			v_synch <= 1'b0;
		end
		else begin
			write_pixel_counter <= write_pixel_counter + 512;
			if (write_pixel_counter >= pixel_wire) v_synch <= 1'b1;			
		end
end


assign change_page = 1'b1;



////Read control using "almost flags"////

								//Note:
								//This uses a different control scheme than the write side. It practically forces the read_side to remain in a section of the FIFO and NEVER get close to w_full or r_empty - the two extremes resulting in data loss.
								//It also needs to be fluent to transmit data for HDMI and data transfer, but limited enough that it would be able to stop running, should we have a very slow readout clock or even would want manual data extraction.

//Read trigger control for the SDRAM driver and hardware

assign 		writing_done = SDRAM_read_only? 1'b1 : v_synch;																	//read-only control

assign 		ram_oeA = writing_done && read_side_FIFO_ready;

assign 		read_side_w_en = ram_read_start;																							//this step harmonizes the 16 state machine to the FIFO write side: we write into the FIFO when the SDRAM's rady flag is pulled high

//Read side trigger - initial load/setup phase

always @ (posedge ram_clk_100MHz or posedge reset or posedge read_side_w_full) begin
			if (reset == 1) read_side_r_en <= 1'b0;
			else if (read_side_w_full == 1) read_side_r_en <= (image_capture_output_enable)? 1'b1 : 1'b0;			//if the FIFO is full  - first time fill-up/setup phase - and we have the output enabled, we open the read_side FIFO and enter the recurring phase																								
		end		
		
//Read side trigger

		reg											read_side_FIFO_ready = 1'b1;														//signal to indicate that the read side FIFO is ready to receive the next burst of data

//Read_side_FIFO_ready control//

always @ (posedge reset or posedge read_side_r_en or posedge read_side_w_full or posedge read_side_r_almost_empty or posedge read_side_almost_full_signal) begin																															
			if (reset == 1) read_side_FIFO_ready <= 1'b1;
			else begin
				if (read_side_r_en == 1'b1) begin
					if (read_side_almost_full_signal == 1) read_side_FIFO_ready <= 1'b0;										//this may or may not work. Can't be tested without an appropraitely slow readout clock. It should work actually.
					else if (read_side_r_almost_empty == 1'b1) read_side_FIFO_ready <= 1'b1;								//if it does, read side FIFO side could be decreased. Optimization?
				end
				else if (read_side_w_full == 1 ) read_side_FIFO_ready <= 1'b0;													//we shut off ram_oeA if the FIFO is full in the setup phase. If we don't we lose data initially.
			end
		end		
								//Note:
								//Since the flags are just indicators, we define a signal that will keep the flag's indication after the flag has gone LOW
								//We only apply this to the almost_full flag. If we are too slow for the almost_empty - i.e. if we load the FIFO too slow and the read_side r_clk catches up - signal definition would not help speed up the loading of the FIFO.
								//With the almost_full, this is not the case. We can slow down the loading - or stop it temporarily - to cater to a slow read_side r_clk.
		
			reg													read_side_almost_full_signal = 1'b0;
		
always @ (posedge read_side_w_almost_full or posedge read_side_r_almost_empty or posedge reset) begin
		if (reset == 1) read_side_almost_full_signal <= 1'b0;
		else begin
			if (read_side_w_almost_full == 1) read_side_almost_full_signal <= 1'b1;
			else begin
				if (read_side_r_almost_empty == 1) read_side_almost_full_signal <= 1'b0;
			end		
		end
end


//Read side pixel counter control


			reg						[21:0]								read_pixel_counter = 22'b0;

//			reg						[18:0]								read_pixel_counter = 19'b0;
			reg						[18:0]								pixels_HDMI_read_out = 19'b0;								//Starting from 1 instead of 0 repairs a loading bug
			
			reg						[12:0]								read_side_horizontal_counter = 13'b0;
			reg						[11:0]								read_side_vertical_counter = 12'b0;

always @ (posedge ram_clk_100MHz or posedge reset) begin																		//We count pixels, publish addresses and burst in synch
				if (reset == 1) begin
						pixels_HDMI_read_out <= 19'b0;																				//this must never exceed 19'b1100110100010011111 to avoid rolling image
//						read_pixel_counter <= 19'b0;
						read_pixel_counter <= 22'b0;				//Note:
																									//Kernelling or sampling the center area should be doable by simply picking the appropriate first pixel to count from.
																									//In case for 1600x1200, the center will start at pixel number 400x1200 + 400 (we skip 400 rows and then 400 columns)
						read_side_horizontal_counter <= 13'b0;
						read_side_vertical_counter <= 12'b0;
				end
				else 	begin
					
				
					if (ram_read_start == 1) begin
						//Pixel readout control
						pixels_HDMI_read_out <= (pixels_HDMI_read_out == 19'b1100110100010011111)? 0 : pixels_HDMI_read_out + 1'b1;																			//It must always be in chunks of 420000 (800x525) to avoid image rolling using a 640x480 HDMI output.
						
						
						//resolution control
						read_side_horizontal_counter <= (read_side_horizontal_counter == 799)? 0 : read_side_horizontal_counter + 1'b1;												//we step the read side horizontal counter only 800 steps to match the HDMI output
						if(read_side_horizontal_counter == 799) read_side_vertical_counter <= (read_side_vertical_counter == 524) ? 0 : read_side_vertical_counter + 1;		//we step the read side vertical counter only 525 steps to match the HDMI output		

						read_pixel_counter <= (HDMI_enabled)? 
																	//HDMI read pixel definition
																	((pixels_HDMI_read_out == 19'b1100110100010011111)? 0 :
																							((resolution_selector >= 3'b100)? ((read_side_horizontal_counter == 799)? (read_pixel_counter + ((horizontal_resolution_wire - 800) + 1)) :
																																												read_pixel_counter + 1'b1) :
																														read_pixel_counter + 1'b1)) 									//to stop image rolling, we read out exactly (!) 420000 pixels for 640x480
																																																//changing the 0 here would position the HDMI readout kernel at different places.
																						
																	//Data transfer read pixel definition					
																						: ((resolution_selector >= 3'b100)? ((read_pixel_counter == pixel_wire)? 0 : (read_pixel_counter + 1'b1))
																																						: ((read_pixel_counter == 22'b1100110100010011111)? 0 : (read_pixel_counter + 1'b1)));			//if we don't have the HDMI module active, we just read out pixels until we run out of them. Then we start from the beginning
																																																																					
																																						//Note:
																																						//			The read pixel counter must go until 800x525 under 800x525 reoslution due to how the data logging was designed.
																																						//			Under 800x525, pixel wire will be less than 800x525, but the readout should be 800x525 exactly. If this is not met, the image will be stripes of repeating patterns
	

	
					end																																										
				end
end


////Read control with almost flags////
 

////Address control for write and read////

always @ (posedge ram_clk_100MHz or posedge reset) begin																				//assigning the address. They don't actually change with ram_clk!
				dqm = 4'b0;
				if (reset == 1) addr <= 26'b0;
				else begin
				//ram_we control removed
				if (ram_write_start	== 1) begin	
//					if (ram_we	== 1) begin																										//this is a bug that works. Should be ram_write_start	instead.	The ram_we definition repairs the loading bug.
																																						//reson why ram_we works here is due to how the write side needs to have an address before the writing starts. The read side can occur simultaneously.
							addr <= {2'b00, write_pixel_counter[21:9], 1'b0 , 1'b0 , write_pixel_counter[8:0]};				//last 3 bits are ignored due to bursting for 8
																																						//Note: A10 of the address is the auto-precharge bit. If HIGH, it will automatically close an active row after use.
																																									//Auto precharge is necessary 
					end
//original address read control
					if (ram_read_start == 1) begin																																																												
//							addr <= {2'b00, read_pixel_counter[21:9], 1'b0 , 1'b0 ,read_pixel_counter[8:2], 2'b0};		//This is a bug: the last 2 bits are ignored due to bursting for 4, but shouldn't be.																								
//							addr <= {5'b00000, read_pixel_counter[18:9], 1'b0 , 1'b0 ,read_pixel_counter[8:2], 2'b0};
							addr <= (resolution_selector >= 3'b100)? ({2'b00, read_pixel_counter[21:9], 1'b0 , 1'b0 ,read_pixel_counter[8:2], 2'b0}) : ({5'b00000, read_pixel_counter[18:9], 1'b0 , 1'b0 ,read_pixel_counter[8:2], 2'b0});
																																						//Note:
																																						//The address definition is divided as well. The reason for this is that things loop if we don't. Not sure why.
																																						//If looping comes up as an issue for higher resolutions, this part needs to be further investigated.
																																						//For now, it works for under 800x525 and seemingly for 1600x1200 as well.

					end					
									
				end		
				
////Address control for write and read////
				
end			


//Output active signal for higher level functions
								//Note:
								//This is used to activate/reset modules above the capture module
								//It goes HIGH after the read side FIFO has been full and readout has been enabled

assign capture_module_output_active = read_side_r_en;	
	

/////Blinky LEDs/////
								//Note:
								//These are for error detection. If we are stuck at one type of run for too long, it should indicate that the digicam is frozen
								//Error signal sampling should occur on the gateway side due to the relative delays the control may introduce
								
assign 					LED[2:0] = idle_counter[2:0];
assign					LED[5:4] = write_counter[1:0];
assign					LED[7:6] = read_counter[1:0];


//Debug probes for the image capture module

//probe1 BLUE cable
//probe2 GREEN cable

//assign					probe1 = ram_write_start;
//assign					probe2 = write_is_interrupted;
//assign					probe2 = idle_cycle_over;
//assign					probe2 = !write_side_FIFO_ready;
//assign					probe2 = write_side_w_full;
//assign					probe2 = write_side_r_empty;
//assign					probe2 = change_page;
//assign					probe2 = write_pixel_counter[0];

//assign					probe1 = q_debugger[1];
//assign					probe2 = q_debugger[0];


//assign					probe1 = read_side_r_almost_empty;											//Note: probing the almost flags at 25 MHz is difficult since we will be in full synch - reading 4 elements and writing 4 elements at the same time
//assign					probe2 = read_side_w_almost_full;

//assign					probe1 = read_side_FIFO_out_16bit_wire[0];
//assign					probe2 = read_side_FIFO_out_16bit_wire[1];

//assign					probe2 = readout_clk;
//assign					probe2 = read_side_FIFO_ready;
//assign					probe2 = read_side_r_almost_empty;											//Note: probing the almost flags at 25 MHz is difficult since we will be in full synch - reading 4 elements and writing 4 elements at the same time
//assign					probe2 = read_side_w_almost_full;
//assign					probe2 = read_side_w_full;

assign					probe2 = write_cycle_over;
//assign					probe1 = write_side_w_almost_full;
assign					probe1 = change_page;
//assign					probe1 = write_side_r_almost_empty;
//assign					probe1 = write_side_FIFO_ready;

endmodule