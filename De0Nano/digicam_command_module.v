//this is the digicam's SPI-based command module
//its primary task is to convert any incoming SPI command into a state of the digicam hardware by modifying the command/status registers
//its secondary task is to define the response of the setup towards the SPI master microcontroller
//its terciary task is to allow debugging
//currently there are setup commands, functional commands, run commands, dummy commands, debugging commands and replies - see below


//Of note, there is a secondary command as well, relying on direct GPIO control from the microcontroller.
//This control is to bypass the this command module and offer a direct master control, for, for instance, resetting.
//These GPIO controls will be for
//1)Full initialization
//2)Turn on/off
//3)External triggers - if activated
//4)Error watchdogs - cycle counters


//Known BUGS:
//1)START always send a BUSY reply instead of ACKNOWLEDGE
//2)PADDING is currently bypassed with the DEBUG_DATA_TRANSFER command
		//Data transfer - reponse loading - doesn't occur here but in the SPI_driver module.
		//Since we currently control the data transfer ONLY using data_transfer, we are transferring non-image data also before the image. PADDING is/will be there to cut these off.
		//Current size of dummy data is unknown. Depends how the transferred image looks like. PADDING will be implemented accordingly.
		//MAYBE REPAIRED - currently, no PADDING might be necessary. Transferred image looks good already.
		


module digicam_command_module (
				input														sys_clk,
				
				input						[7:0]							command_byte,
				input						[7:0]							data_transfer_byte,
				
				output		reg		[7:0]							response_byte,
				
				output		reg										data_transfer,																//data transfer flag. Pulled HIGH when we are transferring data.

				output		reg		[1:0]							pattern_selector_register,												//selector is currently put to generate to wider lines.
				output		reg		[2:0]							resolution_selector_register,											//selector is put to 320x240
				output		reg		[1:0]							SDRAM_status_register,													//status register for the SDRAM
				output		reg		[1:0]							input_output_selector_register,										//input/out selector
				output		reg		[3:0]							module_selector_register,												//module enable selector
				output		reg		[1:0]							clock_selector_register,												//status register for the SDRAM				
				output		reg		[2:0]							run_command_register														//run command, triggers 
);


		//Note:
		//The digicam will run at 320x240 resolution and generate wide stripes without a specific command prior.

///////digicam command table///////

//Setup commands

localparam					SCOPE_STANDBY 		= 		8'hFF;		//255
localparam					PATTERN_IN 			= 		8'h33;		//51
localparam					HDMI_OUT 			= 		8'h66;		//102
localparam					STANDARD_OP 		= 		8'h99;		//153

//Functional commands

localparam					EXT_OUT_TRIG_MODE_ON 		= 		8'h43;		//67
localparam					EXT_OUT_TRIG_MODE_OFF 		= 		8'h44;		//68

localparam					ERASE_SDRAM 		= 		8'h51;		//81
localparam					READ_ONLY_ON 		= 		8'h52;		//82
localparam					READ_ONLY_OFF 		= 		8'h53;		//83

//Run commands

localparam					START					= 		8'h91;		//145
localparam					START_READOUT 		= 		8'h92;		//146							//this should allow the readout and already connect the output of the SPI data transfer to the response
localparam					TRANSMIT_DATA		=		8'h93;		//147
localparam					STOP			 		= 		8'h94;		//148

//Dummy commands

localparam					DUMMY_CMD			=		8'hE1;		//d225					//it is there to provide the answer to a command the same time when it is sent. Compensates for SPI duplex behaviour.
localparam					READOUT_PADDING	=		8'h95;									//needs two of these after START_READOUT to clock the data extraction from the capture module once

//Debugging commands

localparam					HALT						=		8'h90;	//144

localparam					QUICK_START_PATTERN	= 		8'h01;	//1
localparam					QUICK_START_IMAGE		= 		8'h02;	//2
localparam					DEBUG_DATA_TRANSFER	= 		8'h03;	//3

localparam					SELECT_PATTERN_0		=		8'h10;	//16						//wide stripes
localparam					SELECT_PATTERN_1		=		8'h11;	//17						//red progression
localparam					SELECT_PATTERN_2		=		8'h12;	//18						//1 pixel lines
localparam					SELECT_PATTERN_3		=		8'h13;	//19						//complex pattern				

localparam					SELECT_RESOLUTION_0	=		8'h20;	//32						//160x120
localparam					SELECT_RESOLUTION_1	=		8'h21;	//33						//320x240
localparam					SELECT_RESOLUTION_2	=		8'h22;	//34						//640x480
localparam					SELECT_RESOLUTION_3	=		8'h23;	//35						//800x525				-			original full screen HDMI output
localparam					SELECT_RESOLUTION_4	=		8'h24;	//36						//800x600
localparam					SELECT_RESOLUTION_5	=		8'h25;	//37						//1600x1200				-			1.2 MP
localparam					SELECT_RESOLUTION_6	=		8'h26;	//38						//2592x1944				-			5MP
localparam					SELECT_RESOLUTION_7	=		8'h27;	//39						//0x0						-			dummy

localparam					EXT_IN_TRIG_MODE_ON 	= 		8'h41;	//65
localparam					EXT_IN_TRIG_MODE_OFF = 		8'h42;	//66

//Replies
localparam					ACKNOWLEDGE			=		8'hAA;		//d170					//this is a reply to be always in the SPI response register to be sent over upon a new command arriving																								
localparam					SCOPE_BUSY			=		8'hBB;		//d187					//this reply is sent when we wish to extract data from the setup that is busy - occurs when data transfer is not enabled
localparam					UNKNOWN_COMMAND	=		8'hCC;		//d204					//sent when we can't find the command
localparam					INVALID_COMMAND	=		8'hDD;		//d221					//happens when we want to erase a read_only setup
localparam					DUMMY_RPL			=		8'hE2;		//d226

///////Update digicam state///////

//Note: where there is no change in the register below, we don't care, what value they originally hold

				reg												padding_done = 1'b0;				//internal control flag

always @(posedge sys_clk) begin																	//the reaction to command change comes with sys_clk edge
																											//as such, any change we want to implement will have a delay of 20 ns

	case (command_byte)
	
//Register explanation	
//			wire							[1:0]								SDRAM_status_register;															//erase SDRAM, read_only SDRAM
//			wire							[1:0]								input_output_selector_register;												//pattern (0) or image loader (1), data transfer (0) or HDMI (1)
//			wire							[3:0]								module_selector_register;														//enable pattern generator, enable image loader, enable HDMI, enable data transfer
//			wire							[1:0]								clock_selector_register;														//external clock enabled on the input (internal pclk or external pclk), external capture trigger enabled (external trigger or no external trigger)
//			wire							[1:0]								run_command_register;															//capture module "on/off" (technically standby "no/yes"), output enable
//			wire							[1:0]								pattern_selector_register;														//four different papperns can be generated using the pattern generator. This selector picks one
//			wire							[2:0]								resolution_selector_register;													//eight different resolutions from 160x120 to 2592x1944
	
	//Setup commands
	//After each, we have a full run reset
			SCOPE_STANDBY : begin
			
					SDRAM_status_register <= 2'b00;												//SDRAM is put to standby
					input_output_selector_register <= 2'b00;									//pattern generator and data transfer chosen as dummy modules for the selector
					module_selector_register <= 4'b0000;										//we deactivate all modules
					run_command_register <= 2'b00;												//we deactivate all the capture module functions
					clock_selector_register <= 2'b00;											//disable all external triggers
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
				
				end
			
			PATTERN_IN  : 	begin
					input_output_selector_register[1] <= 1'b0;								//we choose the pattern generator, we don't change the output
					module_selector_register[3:2] <= 2'b10;									//we activate the pattern generator and turn off the image loader
					run_command_register <= 2'b00;												//we reset the setup and keep the setup stand-by
					clock_selector_register[1] <= 1'b0;											//we choose pixel_clk
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
				end
			
			HDMI_OUT : 	begin
					input_output_selector_register[0] <= 1'b1;								//we keep the input as before, change to the the HDMI module as output
					module_selector_register[1:0] <= 2'b10;									//we activate the HDMI module and turn off the data transfer
					run_command_register <= 2'b00;												//we reset the setup and keep the setup stand-by
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
				end
			
			STANDARD_OP : 	begin
			
					SDRAM_status_register <= 2'b00;												//SDRAM is neither erased nor put to read_only mode
					input_output_selector_register <= 2'b10;									//we choose the image loader as input, the data transfer module as output
					module_selector_register <= 4'b0101;										//we enable the image loader and the data transfer module
					run_command_register <= 2'b00;												//we reset the setup and keep it stand-by, no external trigger defined
					clock_selector_register <= 2'b10;											//disable all external triggers
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
				end	

			
	//Functional commands - without full reset
			

			ERASE_SDRAM : 	begin
		
					SDRAM_status_register[1] <= 1'b1;											//SDRAM is erased but not put to read_only mode
					run_command_register[1] <= 1'b1;												//we run the setup
																											//erase is the only functional command that has an immediate action. The rest will force a stand-by.
																											
					if (SDRAM_status_register[0] == 1'b1) response_byte <= INVALID_COMMAND;
					else response_byte <= ACKNOWLEDGE;											//ACKNOWLEDGE is loaded into the response after it has been received																											
				end				
							
				
			READ_ONLY_ON : 	begin
			
					SDRAM_status_register[0] <= 1'b1;											//we put the SDRAM to read_only mode
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
					
				end		
	
	
	
	//Functional commands - with full reset
	


			EXT_OUT_TRIG_MODE_ON : 	begin
			
					clock_selector_register[0] <= 1'b1;											//we change the capture mode to external trigger 
					run_command_register[1] <= 1'b0;												//we reset the setup and keep the setup stand-by
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
					
				end
				
			EXT_OUT_TRIG_MODE_OFF : 	begin
			
					clock_selector_register[0] <= 1'b0;											//we change the capture mode to external trigger 
					run_command_register[1] <= 1'b0;												//we reset the setup and keep the setup stand-by
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
					
				end
	
		
			READ_ONLY_OFF : 	begin
			
					SDRAM_status_register[0] <= 1'b0;											//we turn off the SDRAM read_only mode
					run_command_register[1] <= 1'b0;												//we reset the setup and keep the setup stand-by	
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
					
				end			
			
	
	//Run commands
			//Run commands do not change the setup of the digicam. They merely run with whatever setup that has been defined by the setup commands above.
		
			START : 	begin

//					SDRAM_status_register[1] <= 1'b1;											//to be sure, we remove the erase functional command. We keep read_only unaffected.
					run_command_register[1] <= 1'b1;												//we initiate a run
					if (run_command_register[1] == 1'b1) response_byte <= SCOPE_BUSY;	//if we already had the START command, we will send a scope_busy response
					else response_byte <= ACKNOWLEDGE;											//ACKNOWLEDGE is loaded into the response after it has been received	
					
			end
		
		
			START_READOUT  : 	begin
			
					run_command_register[0] <= 1'b1;																					//we publish the data
					if (input_output_selector_register[0] == 1'b0 && run_command_register[1] == 1'b1) begin
							//response_byte <= data_transfer_byte;																	//Not used. Left in here in case SPI data transfer needs to be circumvented. Repsonse byte update current happens in the SPI_driver module.
																																				//The data_transfer_byte is loaded into the response if we have the data loader activated and had a start command alrready
																																				//Mind, upon receiving the command, the data_transfer_byte register will not have any data in it yet
																																				//data transfer will commence on the following command
																																				//we give this reply only if we have the data transfer module chosen
							data_transfer <= 1'b1;																						//we pull the data transfer control flag HIGH if we are in data transfer mode and we had a start command already
																																				//data_transfer flag will define the data loading with the SPI module
							padding_done <= 1'b0;																						//we pull the padding flag LOW
					end
					else if (run_command_register[1] == 1'b0) response_byte <= INVALID_COMMAND;						//if we have not had the START command yet, we will send an error response
					else 	response_byte <= SCOPE_BUSY;																				//if we don't have the data transfer active - because we use HDMI - the reply through SPI will be a simple "busy"
			end
			
			//Note: after START_READOUT command is received and processed, we will need the PADDING command sent over first to drop the fake data byte. This is made so we have time to generate one clock cycle for the transfer loader too.
			//Note: if padding is missed, the data transfer will only return INVALID_COMMAND
			
			
			//IMPORTANT!!!!: PADDING is currently bypassed (see SPI_driver and data_transfer control of response_byte_latch control there)
			
			READOUT_PADDING  : 	begin																									//we need to drop the one duplex reply so when TRANSMIT_DATA starts, it will already have a response_byte loaded with the data_transfer_byte

					if (input_output_selector_register[0] == 1'b0 && run_command_register[1] == 1'b1) begin
							//response_byte <= data_transfer_byte;																	//see above
																																				//data_transfer_byte is loaded into the response if we have the data loader activated and had a start command alrready
							padding_done <= 1'b1;																						//we pull the padding flag LOW					
					end
					else if (input_output_selector_register[0] == 1'b1 || run_command_register != 2'b11) response_byte <= INVALID_COMMAND;				//if we have not had the START command and the START_READOUT command yet, we will send an error response
					else 	response_byte <= SCOPE_BUSY;																				//if we don't have the data transfer active - because we use HDMI - the reply through SPI will be a simple "busy"
			end			
			
						
			TRANSMIT_DATA  : 	begin																	//command only makes sense when data transfer is active
			
					if (input_output_selector_register[0] == 1'b0 && run_command_register == 2'b11 && padding_done) response_byte <= data_transfer_byte;				//if we have chosen the data transfer module as output, and had a start and start_readout command, the data_transfer_byte is loaded into the response
																																				//mind, the first transfered byte will be a dummy
							//Note: actual data will come from the 2nd TRANSMIT_DATA until STOP_READOUT
							//Note: dta transfer will be controlled by the microcontroller SPI.
							//Note: the number of TRANSMIT_DATA bytes will be twice the number of pixels we have saved in the SDRAM!
					else if (input_output_selector_register[0] == 1'b1 || run_command_register != 2'b11 || !padding_done) begin
							response_byte <= INVALID_COMMAND;											//if we have not had the START and the START_READOUT commands yet or we don't have the data transfer module activated or we haven't passed the padding yet, we will send an error response
							data_transfer <= 1'b0;															//we close the data transfer							
					end
					else 	response_byte <= SCOPE_BUSY;																				//reply is a simply "busy" for all other cases
			end

			
			STOP : 	begin
				
					run_command_register[0] <= 1'b0;												//we stop the readout
					run_command_register[1] <= 1'b0;												//we stop the run
					SDRAM_status_register[1] <= 1'b0;											//we remove the SDRAM erase state					
					data_transfer <= 1'b0;															//we close the data transfer
					padding_done <= 1'b0;															//we remove the padding_done flag
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received	
					
			end
			

//Debugging commands - to be commented out in final version

			HALT : 	begin																				//this a dynamic stop where we can quickly cycle through functions. HALT is not foreseen to be used within the final version of the code 
			
					SDRAM_status_register[1] <= 1'b0;											//we remove the SDRAM erase state
					run_command_register[1] <= 1'b0;												//we stop all functions and reset the capture module
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received		
			end
		
			//Generate a pattern and then publish it to HDMI
			QUICK_START_PATTERN : 	begin
				
					SDRAM_status_register <= 2'b00;					
					input_output_selector_register <= 2'b01;
					module_selector_register <= 4'b1010;
					clock_selector_register <= 2'b00;
					run_command_register <= 2'b11;
					response_byte <= ACKNOWLEDGE;												
					data_transfer <= 1'b0;
					padding_done <= 1'b0;
					
			end
		
		
			//Pattern selection must be followed by a quick_start to actually generate the output
			SELECT_PATTERN_0 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					pattern_selector_register <= 2'b0;
			
			end		

			SELECT_PATTERN_1 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					pattern_selector_register <= 2'b01;
			
			end

			SELECT_PATTERN_2 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					pattern_selector_register <= 2'b10;
			
			end	

			SELECT_PATTERN_3 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					pattern_selector_register <= 2'b11;
			
			end				

			
			//Resolution selection must be followed by a quick_start to actually generate the output
			SELECT_RESOLUTION_0 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b001;
			
			end		

			SELECT_RESOLUTION_1 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b000;							//the standard - undefined - value of this register is always 3'b0. We move it here so it will engage 320x240 when no input is provided.
			
			end

			SELECT_RESOLUTION_2 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b010;
			
			end	

			SELECT_RESOLUTION_3 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b011;
			
			end				

			SELECT_RESOLUTION_4 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b100;
			
			end		

			SELECT_RESOLUTION_5 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b101;
			
			end

			SELECT_RESOLUTION_6 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b110;
			
			end	

			SELECT_RESOLUTION_7 : 	begin
				
					run_command_register[1] <= 1'b0;
					response_byte <= ACKNOWLEDGE;												
					resolution_selector_register <= 3'b111;
			
			end
		
			
			//Quick start to generate image output from the camera input
			QUICK_START_IMAGE : 	begin
				
					SDRAM_status_register <= 2'b00;
					input_output_selector_register <= 2'b11;
					module_selector_register <= 4'b0110;
					clock_selector_register <= 2'b10;					
					run_command_register <= 2'b11;
					response_byte <= ACKNOWLEDGE;										
					data_transfer <= 1'b0;
					padding_done <= 1'b0;
					
			end			

			//Quick start to generate one pixel line pattern and then load it for data transfer
			DEBUG_DATA_TRANSFER : 	begin
				
					SDRAM_status_register[1] <= 1'b0;											//only remove ERASE, but leave the read_only unchanged
//					SDRAM_status_register <= 2'b00;												//full reset and prepare for writing data
					input_output_selector_register <= 2'b00;
					module_selector_register <= 4'b1001;
					clock_selector_register <= 2'b00;
					run_command_register <= 2'b11;
					pattern_selector_register <= 2'b10;											//we will have a 1 pixel lines as a pattern here - Red, Green, Blue and Black
//					pattern_selector_register <= 2'b01;											//red transition
					data_transfer <= 1'b1;
					padding_done <= 1'b1;											
					
			end			
			
					
			//Shift to external triggering
			EXT_IN_TRIG_MODE_ON : 	begin															//flexibly changing the input clocks is a debug only operations
			
					clock_selector_register[1] <= 1'b1;											//we change the capture mode to external trigger 
					run_command_register[1] <= 1'b0;												//we reset the setup and keep the setup stand-by
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
					
				end
			
			//Turn off external triggering
			EXT_IN_TRIG_MODE_OFF : 	begin															//flexibly changing the input clocks is a debug only operations
			
					clock_selector_register[1] <= 1'b0;											//we change the capture mode to external trigger 
					run_command_register[1] <= 1'b0;												//we reset the setup and keep the setup stand-by
					response_byte <= ACKNOWLEDGE;													//ACKNOWLEDGE is loaded into the response after it has been received
					
				end			
	
	

//Dummy exchange
		
			DUMMY_CMD : 	begin
			
					response_byte <= DUMMY_RPL;													//DUMMY_RPL is loaded into the response after this has been received. Mind, a DUMMY_CMD is expected after each regualr command - except START_READOUT and DATA_TRANSFER to provide the right reponse for each command.
																											//DUMMY is technically there to align command and response - which are otherwise one byte missalinged due to duplex behaviour of SPI 
					
				end				
	
//Default state
		//It is here just in case we have trouble with the SPI communication
			default: begin
								
					response_byte <= UNKNOWN_COMMAND;											//UNKNOWN_COMMAND is loaded into the response if the command is not recognised
					
				end
	endcase
end

endmodule

//Validated progression of commands
//148 (stop)->145(start)->146(readout start)->149(padding - first clock of transfer loader at the 4th falling edge of SCK)->147(transmit first data byte)->...repeat 840000 times...->148(stop)

//Note: commands, if a SPI.transfer is used for the command, will have at least a 1 us buffer between themselves.
//Note: the micro/SPI master should walwasy send a command and then a DUMMY_CMD to receive the actual reply for the command