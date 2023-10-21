
//code works under 25 MHz with small FIFO
//1) Increase module speed
		//above 25 MHz, the logging in speed is too slow. With 30 MHz, we simply fill the FIFO.
		//We can force it to work by increasing the write side FIFO and thus, the write side buffer.	We need size 11 FIFO for 640x480. (Original size is 6.)
		//For 1600x1200, with 30 MHz load speed, the FIFO would need to be probably 14 or 15. (Mind, 15 is the Cyclone IV hardware limit.)
		//At any rate, increasing the FIFO is not a very good solution. It takes up too much memory.
		//Current code's absolute limit (with a size 15 write FIFO) is somewhere around 35 MHz. Mind, this is with an SDRAM clocking at 100 MHz.
		//Since output must be syncronous to not lose data upon continous image retreival (i.e. not roll the image), the speed increase can only be achieved by changing the SDRAM to something capable to do higher freq.
		//Due to reproduction issues, this needs to be 200 MHz. 133 and 143 are 7x19 and 11x13 only, respectively. The 100 / 16 * 4 = 25 formula won't work to generate 25 MHz, 1 pixel output (25 can't be divided by 7, 11, 13 or 19 to allow syncronous loading).
		//Nevertheless, 200 MHz loading with a 16 step state machine should be able to generate a 25 MHz, 1 pixel syncronous output if we burst for 2 pixels only on the read side. 

		
		//There are 3 ways to gain speed:
				//1 - increase the speed of the SDRAM
				//2 - increase the burst
				//3 - decrease the state machine step number
				
		//The only thing that must be kept in mind that (SDRAM_MHz / state_machine_steps) * read_side_burst = 25
		//Potentially the highest speed that could be achieved would be (200 MHz / 40) * 32 (theoretical max load speed of 160 MHz) on the write side and (200 MHz / 40) * 5 on the read side.
				//Note: Current setup is (100MHz / 16) * 8 (theoretical max load speed of 50 MHz) for write, (100MHz / 16) * 4 for read.
				//Note: With the 32 burst implemented at 100 MHz, we have (100MHz / (16 + 32 - 3)) * 32 (theoretical max load speed of 71.1 MHz)
				
		//REPAIRED - AUTO-PRECHARGE was activated, which meant that the rows were forced shut after each burst. Now the setup bursts for 32 on the write side. This increased the raw capacity of the module above the treshold of minimum.
		
		//For additional speed gain, consider clocking the SDRAM at 200 MHz and increase the burst from 32 to 64.
			//Note: speed bottleneck is likely the external pclk
			
		//Timing is off and also leads to low optimization.

//2) Test resolutions above 800x525 for images
		//Currently we can only generate 640x480 pixel images. Above, it is a question if we have everything working well or not.
		

		
//3) Noise
		//The setup is becoming very noisy, especially the external clock. Empirical eevidence suggests that the external clock is the real speed bottleneck, not the module.
		//Also, sometimes the DE0Nano board needs to be reset to get rid of noise on the HDMI channels.
		//trigger is extermely noisy
		//trigger cna be engaged by simply putting a finger close to the trigger cable
		//setup can generate enough noisy to shut down a radio
		//check if all signals are properly crossing domains - capture trigger, pclk mostly
		//FF synchronizers
				//gretaer stability is precveived after installing these on the inputs with 200 MHz sampling
				//sys_clk sampling already introduces noise
				//25Mhz sampling does not work, too noisy
				//12MHz sampling doesn't work at all
		
		//Use mutual GND and decrease antenna sizes
		//Move all clock generation to the top level. It might help with timing stability. After all, the HDMI module became faster after it was moved to the top too.
		

//4) RGB5656 to raw - encoding

//5) LVDS loader

//6) LED driver
	
//7)Write side optimization regarding memory and speed


//Implement debug
		//Currently two debug outcputs are being used:
		
		//1) seeing the output leaving the SDRAM on the blinky LEDS
//		assign LED [7:0] = capture_module_data_output[7:0];
		
		//2)Seeing the phase of the capture module on the blinky LEDS
//		assign 					LED[2:0] = idle_counter[2:0];
//		assign					LED[5:4] = write_counter[1:0];
//		assign					LED[7:6] = read_counter[1:0];

		//These two error detectors have been massively useful to understand that the proper functions are ongoing within the capture module. Detecting them on the micro side would be ideal watchdog for the digicam.

		
		
//Note:
		//A cool debugging image to generate: 35->17->1->34->16->1->33->19->1->32->18->1

		
//Bugs:
//1)Load bug - we have an initial pixel load misalignment independent of the resolution.
		//The issue is not particularly discomforting and can't even be noticed past 640x480 resolution. Recommendation is to ignore the issue unless it becomes a problem in the future.
		//If we change to ram_we from ram_write_start the address control, the faulty pixels shift to the other end of the image and decrease from 4 to 2. General functionality is not impacted by this change. ram_we is left as the trigger, even though it is hiding the bug only.
		
//2)Noise - the clock and the inputs are noisy. This can lead to texture failure.
		//The issue is probably related to capacitance within the system.

//3)Timing 		
		//Changing the setup now made it slower again, even on the pattern side. Pipelining and always block reworking will be necessary.
		//Clock skew
		//Counter replacement with gray counter
		
		//Actually, we don't have the official speed of the setup - what we could get to theoretically - because of the timing issue. As it goes, the timing constraint is done for 100 MHz, while, in reality, we only run a very small part of the code at this speed. The others at 25 MHz or slower.
		//This means that if we were to run everything at 100 MHz, we would have 5 ns of timing issue. Since we don't run it there, we effectively run the entire setup at a slower clock and thus elminiate the timing issue.
		//In practical sense, we have a theoretical maximum speed of 71 MHz with the 32 burst loader - with pattern generator input - but we actually start to have issues past 60 MHz.
		
		//Regarding the messy input, that is delayed likely due to it being in a different module. Experience suggests that the deeper a section is within the code, the slower data will get to it. The clocking may be repaired by moving the clock generators all to the top level.

		
//4)Output is pixelated on the screen sometimes.
		//This comes from the OV7670 camera. Images are pixelated on the TFT screen as well.
		
//5)Implement a flag to start data transfer and avoid serial monitor


module Digicam_top_module(
			//Internal sources
			input																sys_clk, top_module_reset,	data_transfer_btn,		//system clock (for DE0Nano, 50 MHz) and reset
																																					//top module reset is technically the "ON SWITCH". It is literally on one of the dip switches on the DE0Nano

			//External sources - controller

			input																spi_sck,															//external clock of the SPI and the data transfer			
			input																spi_cs,															//chip select - active LOW
			input																spi_mosi,														//the data input for the SPI
			
			input																external_trigger, 											//external trigger is an external resetting source
																																					//needs to be enabled within the setup - without, triggering occurs by SPI command (START_RUN)
			
			//External sources - camera
			input																pclk,																//this will be the input of the top module. Currently wired as pixel_12	
			input							[7:0]								image_input,													//this will be the input of the top module. Currently wired as pattern_out_DVP_wire
																																					//Note: this should be RGB565 format to allow comptability coming in as a DVP signal
			input																vsynch_input,															//frame is ready
			input																href,																//active pixel indicator
																																					//Note: this should be href, not hsync, that is, we don't want to consider the porches when we trigger the DVP loader
			
			//SPI output
			output															spi_miso,														//data output of the SPI communication module
		
			//HDMI output
			output						[2:0]								TMDS_signal,													//HDMI output
			output															TMDS_clk,														//HDMI output
			
			//SDRAM
			inout							[15:0]							sd_data_bus,													//SDRAM 16 DQ pins
			
			output															dram_clk,														//SDRAM hardware clock
			output															cke,																//clock enable for SDRAM (if needed)
			
			output						[12:0]							sd_addr,															// 13 A pins
			output						[1:0]								sd_ba,															//	2 BA pins
			output						[1:0]								sd_dqm,															// 2 DQM pins
			output															sd_cs,															// CS pin
			output															sd_we,															// we pin
			output															sd_cas,															// cas pin
			output															sd_ras,															// ras pin

			//Debugging output
			output						[7:0]								LED,																//feedback blinky LEDs
			
			//Microcontroller hardware input - data transfer switch
			output															data_transfer_switch,										//A signal connected to a pushbutton to start data transfer with the microcontroller
			
			//Camera hardware inputs - interface
			input																micro_scl, micro_sda, micro_xclk,						//camera conections pins
			
			//Camera hardware outputs - interface
//			output															cam_3v3, cam_gnd, 
			output															cam_scl, cam_sda, cam_xclk, OV2640_pwdn, OV2640_rst,		//camera connection pins
			
			output															probe1, probe2													//debug probe output
);


////////////Camera interface management////////////

//camera power wiring

//assign cam_3v3 = 1'bZ;									//this could be powering the camera through the GPIO of the FPGA. Mind, this voltage is only 3V instead of 3V3, so the outcome isn't as good as it is with a proper 3V3 power line.
//assign cam_gnd = 1'bZ;
assign OV2640_pwdn = 1'bZ; 
assign OV2640_rst = 1'bZ;

//camera control wiring
assign cam_scl = 1'bZ;									//the camera is currently externally connected to the Adalogger since the FPGA breaks the I2C bus For an integrated version, an I2C TX/RX would need to be coded.
assign cam_sda = 1'bZ;
assign cam_xclk = micro_xclk;
//assign cam_xclk = 1'bZ;									//we temporarily remove all camera drive from the scope driver

		//Note: we currently do not power nor control the camera through the FPGA but using external cabling

//vsycnh input management
			//Note:
			//how the code is written, vsynch needs to be LOW when we have an active frame (that is, we have a VSYNC that is NEGATIVE)
			//this setup may not always be available on a camera
			//the following section simply inverts vsynch in case the camera could not do it on its own - or if it is not set up to do so
			//within the OV7670, COM10 Bit[1] does the inversion. Within the OV2640, much of the DSP needs to be bypassed to change the VSYNC to negative (not recommended)

			wire																vsynch;

assign	vsynch = vsynch_input;


////////////Camera interface management////////////

////////////digicam SPI communication driver module////////////
//Module interfaces the digicam with an external element using SPI

			//Note:
			//the module is calibrated for SPI SPI0 mode and Big Endian

			wire						[7:0]									command_byte;
			wire						[7:0]									response_byte;

			wire																transfer_input_clk;
			wire																sck_test;

			
SPI_driver SPI_driver (
				//Hardware input
				.spi_sck(spi_sck),
				.spi_cs(spi_cs),
				.spi_mosi(spi_mosi),	

				//Driver input
				.sys_clk(sys_clk),								
				.response_byte(response_byte),
				.data_input_16_bit(capture_module_data_output),

				//Transfer clock generator input				
				.data_transfer(data_transfer),
				.reset(image_capture_reset_state),
				
				//Transfer clock generator output
				.transfer_input_clk(transfer_input_clk),
				.sck_test(sck_test),										//clock testing output - to be removed
				
				//Hardware output
				.spi_miso(spi_miso),								
				
				//Driver output
				.command_byte(command_byte)
);

			
////////////digicam SPI communication driver module////////////


////////////digicam command module////////////

//Upon receiving a command byte, the module below changes the control registers of the digicam

			reg							[7:0]								data_transfer_byte = 8'hFF;													//this will be where the data transfer module will connect to

			wire																data_transfer;
			
			wire							[1:0]								SDRAM_status_register;															//erase SDRAM, read_only SDRAM
			wire							[1:0]								input_output_selector_register;												//pattern (0) or image loader (1), data transfer (0) or HDMI (1)
			wire							[3:0]								module_selector_register;														//enable pattern generator, enable image loader, enable HDMI, enable data transfer
			wire							[2:0]								clock_selector_register;														//pclk (1) or pattern_gen_clk (0), external trigger (1) or no trigger
			wire							[1:0]								run_command_register;															//capture module "on/off" (technically standby "no/yes"), output enable
			
																																										//Note: external trigger is there for a periodic, non command-based reset of the setup. If external triggers are not allowed, the "on/off" switch becomes the capture trigger.
			wire							[1:0]								pattern_selector_register;
			wire							[2:0]								resolution_selector_register;
																																							
																																							
digicam_command_module command_control (
				.sys_clk(sys_clk),				
				.command_byte(command_byte),
				.data_transfer_byte(data_transfer_byte),
				.data_transfer(data_transfer),
				.response_byte(response_byte),
				.pattern_selector_register(pattern_selector_register),
				.resolution_selector_register(resolution_selector_register),
				.SDRAM_status_register(SDRAM_status_register),
				.input_output_selector_register(input_output_selector_register),
				.module_selector_register(module_selector_register),
				.clock_selector_register(clock_selector_register),
				.run_command_register(run_command_register)
);


////////////digicam command module////////////

//Register explanation	
//			wire							[1:0]								SDRAM_status_register;															//erase SDRAM, read_only SDRAM
//			wire							[1:0]								input_output_selector_register;												//pattern (0) or image loader (1), data transfer (0) or HDMI (1)
//			wire							[3:0]								module_selector_register;														//enable pattern generator, enable image loader, enable HDMI, enable data transfer
//			wire							[1:0]								clock_selector_register;														//pclk (1) or pattern_gen_clk (0), external trigger (1) or no trigger
//			wire							[1:0]								run_command_register;															//capture module "on/off" (technically standby "no/yes"), output enable
//			wire							[1:0]								pattern_selector_register;														//four different papperns can be generated using the pattern generator. This selector picks one
//			wire							[2:0]								resolution_selector_register;													//eight different resolutions from 160x120 to 2592x1944
		
																																										//Note: external trigger is there for a periodic, non command-based reset of the setup. If external triggers are not allowed, the standby switch becomes the capture trigger.

																																										//Note:
																																										//For the regular user, the image will allways be clocked by pclk, the generator, by pattern_gen_clk
																																										//Being able to change that is useful for debugging though, to see if we have a clock generating an input. Mind, pattern_gen_clk and pattern generator allways work, so we can cross-test them with pclk and pixel input to see, what doesn't work.
																																										//No general SPI command should change the standard clocking.
	
																																										
//////Internal control signal/////

//SDRAM reinitialization
		//Note:
		//This signal reinitializes the SDRAM. Can overwrite reset state.
		//This is NOT the module functional reset! The module functional reset is separate from the initialization of the SDRAM for timing reasons.
		//Techninally, we need to reinitialize the SDRAM, then reset the image capture module, then reset the data loaders to ensure that no data is lost
		
		//Note:
		//This is currently on a dip switch (4th one). It works as an external ON/OFF
			wire																init = ~top_module_reset;
		
//Data transfer indicator
//If we push the push button, a data transfer signal is published towards the microcontroller to commence data transfer

			wire																data_transfer_switch_wire = ~data_transfer_btn;

			reg																transfer_on_off = 1'b0;

always @ (posedge init or posedge data_transfer_switch_wire) begin
		if (init == 1) transfer_on_off = 1'b0;
		else transfer_on_off = 1'b1;
end

assign data_transfer_switch = transfer_on_off;
		
		
/////External control signals/////
		
		//Note:
		//Need syncronization
		//FF sampling is with 200 MHz. Any trigger/pclk that is 100 MHz or faster, could be difficult to manage
		//also, the signals will be delayed by a clock cycle - not a problem here, but might be in the future
		//with an adequately fast sample clock, this part could be used for noise filtering

//1) External (capture) trigger
		//Note:
		//Resets all internal counters and readies the image capture module for input
		//Does not reinitialize the SDRAM!
		//Must stay HIGH for all functions!

		//This is currently an external trigger coming over on GPIO. Will be replaced by run_command_register[1].
			reg							[1:0]								ext_start_trigger_latch;									

always @	(posedge clk_200MHz) ext_start_trigger_latch <= {ext_start_trigger_latch[0], external_trigger};
																																	
			wire																ext_start_trigger = ext_start_trigger_latch[1];
																																																																					
//2) External input clock
		//Clock signal of the incoming signal
		//Can only be as high as 100 MHz with the current clock as the FF clock
		
			reg							[1:0]								ext_data_input_clock_latch;									

always @	(posedge clk_200MHz) ext_data_input_clock_latch <= {ext_data_input_clock_latch[0], pclk};
																																	
			wire																ext_data_input_clock = ext_data_input_clock_latch[1];

//3) 	External "image line active" input
		//Flag to show that we have active pixel values coming in
		//Must be set within the camera to be href, not hsync!
		
			reg							[1:0]								line_active_latch;									

always @	(posedge clk_200MHz) line_active_latch <= {line_active_latch[0], href};
																																	
			wire																line_active = line_active_latch[1];			

//4) External "frame end" input
		//Flag to show that we have an image published
		
			reg							[1:0]								frame_end_latch;									

always @	(posedge clk_200MHz) frame_end_latch <= {frame_end_latch[0], vsynch};
																																	
			wire																frame_end = frame_end_latch[1];

																																			

////////////PLLs, internal clocks//////////////

		wire																	pixel_clk_25MHz;										// 25 MHz - necessary for HDMI output generation
		
PLL_25MHz PLL25 (
			.inclk0(sys_clk),
			.c0(pixel_clk_25MHz)
);


		wire 																	clk_200MHz;												// 200 MHz - necessary for HDMI output generation
		
PLL_200MHz PLL200 (
			.inclk0(sys_clk),
			.c0(clk_200MHz)
);


		wire 																	bit_clk_250MHz;										// 250 MHz - necessary for HDMI output generation
		
PLL_250MHz PLL250 (
			.inclk0(sys_clk),
			.c0(bit_clk_250MHz)
);




////////////digicam calibration parameters////////////

//Resolution selection

				wire						[12:0]							horizontal_resolution;
				wire						[11:0]							vertical_resolution;
				wire						[22:0]							pixel_number;				

assign 	horizontal_resolution = ((resolution_selector_register == 3'b000)	?	320 : 									//register standard - undefined - value is 3'b0
																																					//mind, the command side is adjusted accordingly to deal with the swapping of 160 with 320 so the commands will be properly ascending when increasing resolution
											((resolution_selector_register == 3'b001)	?	160 : 
											((resolution_selector_register == 3'b010)	?	640 :
											((resolution_selector_register == 3'b011)	?  800 :
											((resolution_selector_register == 3'b100)	?  800 :
											((resolution_selector_register == 3'b101)	? 1600 :
											((resolution_selector_register == 3'b110)	? 2592 :
											((resolution_selector_register == 3'b111)	? 4096 : 0))))))));						//currently a dummy




assign 	vertical_resolution =((resolution_selector_register == 3'b000)	?	240 : 										//register standard - undefined - value is 3'b0
																																					//mind, the command side is adjusted accordingly to deal with the swapping of 120 with 240 so the commands will be properly ascending when increasing resolution
										((resolution_selector_register == 3'b001)	?	120 : 
										((resolution_selector_register == 3'b010)	?	480 : 
										((resolution_selector_register == 3'b011)	?  525 :
										((resolution_selector_register == 3'b100)	?  600 :
										((resolution_selector_register == 3'b101)	? 1200 :
										((resolution_selector_register == 3'b110)	? 1944 :										
										((resolution_selector_register == 3'b111)	? 2048 : 0))))))));							//currently a dummy
										
										
assign 	pixel_number = 		((resolution_selector_register == 3'b000)	?	23'b00000010010101111111111 :			//register standard - undefined - value is 3'b0
																																					//mind, the command side is adjusted accordingly to deal with the swapping so the commands will be properly ascending when increasing resolution

										((resolution_selector_register == 3'b001)	?	23'b00000000100101011111111 : 
										((resolution_selector_register == 3'b010)	?	23'b00001011010011000010111 : 
										((resolution_selector_register == 3'b011)	?  23'b00001100110100010011111 :
										((resolution_selector_register == 3'b100)	?  23'b00001110101001011111111 :
										((resolution_selector_register == 3'b101)	?  23'b00111010100101111111111 :
										((resolution_selector_register == 3'b110)	?  23'b10011001110001011111111 :
										((resolution_selector_register == 3'b111)	?  23'b11111111111111111111111 : 0))))))));								//currently a dummy				
		
		

////////////Module enable wires////////////
		//These are all defined from the output of the command module
			
			wire																pattern_generator_enable;
			assign					pattern_generator_enable = module_selector_register[3];									//enable to activate the pattern generator
			
			wire																image_loader_enable;
			assign					image_loader_enable = module_selector_register[2];											//enable to activate the image loader

			wire																HDMI_output_enable;
			assign					HDMI_output_enable = module_selector_register[1];											//enable to activate the HDMI module
			
			wire																data_transfer_enable;
			assign					data_transfer_enable = module_selector_register[0];										//enable to activate the data transfer module			


////////////Run command wires////////////		
		//These are all defined from the output of the command module

			wire																reset_trigger;
			assign					reset_trigger = (clock_selector_register[0])? (ext_start_trigger & run_command_register[1]) : run_command_register[1];				//run_command_regsiter[1] defines the capture trigger
																																																					//for external triggering of the on/off, the setup needs to be in "capture" mode first
			
			wire																image_capture_output_enable;
			assign					image_capture_output_enable = run_command_register[0];
	

			
////////////Pattern generator module////////////

		wire 																	clk_3MHz;												// 6 MHz - for write side modification and memory leak debugging
		
PLL_3MHz PLL3 (
			.inclk0(sys_clk),
			.c0(clk_3MHz)
);


		wire 																	clk_6MHz;												// 6 MHz - for write side modification and memory leak debugging
		
PLL_6MHz PLL6 (
			.inclk0(sys_clk),
			.c0(clk_6MHz)
);

		wire 																	clk_12MHz;												// 6 MHz - for write side modification and memory leak debugging
		
PLL_12MHz PLL12 (
			.inclk0(sys_clk),
			.c0(clk_12MHz)
);

		wire 																	clk_24MHz;												// 6 MHz - for write side modification and memory leak debugging
		
PLL_24MHz PLL24 (
			.inclk0(sys_clk),
			.c0(clk_24MHz)
);


			wire 																pattern_gen_clk = clk_24MHz;							//pattern generator will always provide output at 25 MHz. Pattern will also be fixed at wider lines of 4 colours.
																																						//change is only possible by modifying the pattern generator code
			wire							[4:0]								pattern_out_blue_wire, pattern_out_red_wire;
			wire							[5:0]								pattern_out_green_wire;
			wire							[15:0]							pattern_out_16bit_wire;
			wire																frame_rdy_wire;

RGB565_pattern_single_frame
single_frame
(

//Choose pattern generator clock
				.pattern_clk(input_clk),
				.pattern_generator_enable(pattern_generator_enable),
				.pattern_reset(image_capture_reset_state),
				.pattern_selector(pattern_selector_register),														//coming from command module
				.horizontal_resolution(horizontal_resolution),
				.vertical_resolution(vertical_resolution),
				.RGB565_red(pattern_out_red_wire),
				.RGB565_blue(pattern_out_blue_wire),
				.RGB565_green(pattern_out_green_wire),
				.RGB565_DVP(pattern_out_16bit_wire),																	//the entire RGB565 output will be r[4:0]g[5:0]b[4:0]	
				.frame_rdy(frame_rdy_wire)
);

////////////Pattern generator module////////////

////////////DVP_RGB565_loader module//////////////

			wire							[15:0]							loader_output_16_bit;
			wire																loader_output_clk;
			wire																image_frame_active;							//signal to indicate, when we have an active image
			

DVP_RGB565_loader image_loader(
				.pclk(input_clk),																								//external pixel clock
				.image_loader_enable(image_loader_enable),
				.href(line_active),
				.vsynch(frame_end),
				.image_frame_active(image_frame_active),																//used to deal with the asynch nature of the camera compared to the rest of the setup reset, in particular, the HDMI module which will reset differently than the camera input every time
				.reset(image_capture_reset_state),
				.input_8_bit(image_input),
				.output_clk(loader_output_clk),
				.output_16_bit(loader_output_16_bit)
);

////////////DVP_RGB565_loader module//////////////


////////////Image capture module////////////
			wire																image_capture_reset_state;					//the reset signal of the image capture module
			wire							[15:0]							capture_module_data_input;
			wire							[15:0]							capture_module_data_output;											
			
			wire																input_clk;
			wire																capture_clk;
			wire																readout_clk;

//Choose data input clock

assign input_clk = (clock_selector_register[1] == 1'b1)? ext_data_input_clock : pattern_gen_clk;
			
//Choose data source		

assign capture_module_data_input = (input_output_selector_register[1] == 1'b1)? loader_output_16_bit : pattern_out_16bit_wire;														//image loader input

//Choose capture clock

assign capture_clk = (input_output_selector_register[1] == 1'b1)? loader_output_clk : pattern_gen_clk;	

//Choose readout clock

assign readout_clk = (input_output_selector_register[0] == 1'b1)? pixel_clk_25MHz : transfer_input_clk;																						//transfer_input_clk clocks once on every 16th SCK falling edge

////Image capture module input selector////
			
Image_capture
image_capture
(
			.sys_clk(sys_clk),
			.init(init),															//reinitialize	SDRAM. Can overwrite reset state.							
			
			//Input clock
			.capture_clk(capture_clk),
			
			//Resolution selection
			.horizontal_resolution(horizontal_resolution),
			.vertical_resolution(vertical_resolution),
			.pixel_number(pixel_number),
			.resolution_selector(resolution_selector_register),
			.HDMI_enabled(HDMI_output_enable),

			//Capture data input
			.write_side_data_input(capture_module_data_input),
			.image_capture_output_enable(image_capture_output_enable),

			//Output clock
			.readout_clk(readout_clk),

			//Capture data output			
			.read_side_FIFO_out_16bit_wire(capture_module_data_output),
			
			//SDRAM
			.sd_data_bus(sd_data_bus),													
			.SDRAM_read_only(SDRAM_status_register[0]),
			.SDRAM_erase(SDRAM_status_register[1]),

//Choose capture trigger
			.reset_trigger(reset_trigger),									//reset functions - counters, flag, FIFOs, etc. Can be external or internal, depending on selection in the command register.					
			.dram_clk(dram_clk),													//SDRAM hardware clock
			.cke(cke),																//clock enable for SDRAM (if needed)
			
			.sd_addr(sd_addr),													// 13 A pins
			.sd_ba(sd_ba),															//	2 BA pins
			.sd_dqm(sd_dqm),														// 2 DQM pins
			.sd_cs(sd_cs),															// CS pin
			.sd_we(sd_we),															// we pin
			.sd_cas(sd_cas),														// cas pin
			.sd_ras(sd_ras),														// ras pin

			.image_capture_reset_state(image_capture_reset_state),	//reset signal that comes after SDRAM initializationa dn image capture module setup.
																						//Used to time input arriving after the image capture module is set.
//			.LED(LED),																//feedback blinky LEDs
	
			.capture_module_output_active(output_active),
			
			.probe1(probe1),														//Debug probe
			.probe2(probe2)														//Debug probe
);

////////////Image capture module////////////

////////////HDMI 640x480 screen module//////////////
		
			wire								[2:0]								TMDS_encoded_out;
			wire																	TMDS_encoded_clk;
			
			wire																	HDMI_module_reset;

			
//assign HDMI_module_reset = (image_loader_enable)? ~image_frame_active : image_capture_reset_state;							//we reset the HDMI module always the same time relative to data capture			
	
assign HDMI_module_reset = ~output_active;
	
output_HDMI_640x480_mod (
				.pixel_clk(pixel_clk_25MHz),									//this must be always 25MHz for a steady output
				.bit_clk(bit_clk_250MHz),										//this must be always 250MHz for a steady output
				.HDMI_output_enable(HDMI_output_enable),
				.screen_reset(HDMI_module_reset),
				.red_input_HDMI(eightbit_red_wire),
				.blue_input_HDMI(eightbit_blue_wire),
				.green_input_HDMI(eightbit_green_wire),
				.TMDS_encoded_out(TMDS_encoded_out),
				.TMDS_encoded_clk(TMDS_encoded_clk)
);


//Register size matching
//Since the HDMI module expects 8 bit colour input, we add some dummy zeros to the extracted RGB565 input

			wire							[7:0]								eightbit_blue_wire, eightbit_red_wire, eightbit_green_wire;  

//pattern-to-SDRAM-to-FIFO feed to HDMI
assign		eightbit_blue_wire = {capture_module_data_output[4:0], 3'b0};
assign 		eightbit_red_wire = {capture_module_data_output[15:11], 3'b0};
assign		eightbit_green_wire = {capture_module_data_output[10:5], 2'b0};


////HDMI output assignment

assign 					TMDS_signal[0] = TMDS_encoded_out [0];
assign 					TMDS_signal[1] = TMDS_encoded_out [1];
assign 					TMDS_signal[2] = TMDS_encoded_out [2];
assign					TMDS_clk = TMDS_encoded_clk;

////////////HDMI 640x480 screen module//////////////

////Debug signals/////

//Blinky LED assignment//

//assign LED [7:0] = command_byte [7:0];

assign LED [7:0] = capture_module_data_output[7:0];



//Debug probes for the top level

//probe1 BLUE cable
//probe2 GREEN cable

//Testing the SPI inputs/outputs of the entire setup
//assign					probe1 = spi_sck;
////assign					probe2 = spi_mosi;
//assign					probe2 = spi_miso;

//For data transfer input clock debug
//assign					probe1 = sck_test;
//assign					probe2 = transfer_input_clk;
//assign					probe1 = data_transfer;
//assign					probe2 = capture_module_data_output[9];

////Debug signals/////


endmodule




//Command system

//Through SPI

//1)Erase SDRAM
		//necessary before every capture in order to wipe noise
		//currently on dip-switch 2

//2)Capture trigger (micrroscope functional reset)
		//take an image
		//currently coming from GPIO using the micro

//3)Read-only mode
		//put the setup to read-only mode
		//currently on dip-switch 1
		
//4)Commence data transfer
		//periodic signal expected a response from the digicam
		//data transfer shall occur using the external clock of the SPI master
		//reply shall be 11111111 (0xFF) or something for debugging mode
		//reply shall be the image data for operational mode

//5)Switch output to debug mode
		//divert data output to the HDMI module from the data transfer module
		//currently not implemented

//6)Switch input to debug mode
		//hijack data input from image loader to pattern generator
		//currently done by changing verilog code
		
//7)Calibrate digicam
		//define parameters for image resolution and pixel number
		//currently done by changing verilog code
		

//Through GPIO, towards micro

//1) Reinitialize setup
		//reinitializes the SDRAM driver - flags and functions at the same time
		//currently on push button 1
		
//2)Turn on/turn off
		//activates the digicam
		//currently starts by uploading the verilog code

//3) idle, read and write cycle flags for error detection
		//we count the cycle over flags for debugging and error detection
		//currently wired to the LEDs on the FPGA
		//in the future: if read cycles don't start, we have a problem. One GPIO back to the micro to detect a GPIO pulled HIGH - to be implemented!

//4) Data transfer clock
		//we need to clock the SPI slave driver and the SPI loader

		
//Through GPIO, from camera

//1)External clock
		//pclk input clock
		
//2)HREF
		//goes HIGH when active pixels are coming in

//3)vsynch
		//goes HIGH when a frame is ready
		
//4)D0-D7 data pins
		//DVP data pins
		
//So, what do we need?
//1)We need an SPI slave module for detecting communication and to churn out commands
//2)We need an SPI loader module to format the data to SPI standard
//3)We need a command structure module or implement it directly into the top level

//Once done, we will be able to control the digicam using a micro only and change, where we want to send our data.

//Where do we leave off?
//All major commands work through SPI, including debugging - see gateway code
//Data transfer works under 800x525 - validated 640x480 image logging
//Above 640x480, patterns and BMP generation work, except for 2592x1944.
//Downstream - command and data transfer - of the digicam can be technically considered DONE.
		//Note: command order is very important for resetting and timing.