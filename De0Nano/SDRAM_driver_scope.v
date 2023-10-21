////the SDRAM driver for a IS42S16160J from ISSI
////it has 4M x 16 x 4 banks distribution
////it can be run at 100 MHz up to 166 MHz
////has an RCD time between 14 and 18 ns
////in case a different SDRAM is used, the parameters must be adjusted.
//
//
////driver has a write state, a read state, an idle state and an interrupt state
////write side can be flexible on how much it bursts
////full page burst use is not recommended do to timing difficulties



//known BUGS

//1)the driver is running at 100 MHz while the hardware is set for 143 MHz - at least on the DE0Nano (7TLI model of the RAM)
		//this makes the CAS latency definition weird (2 + 1) since it is kinda neither 2, nor 3, in reality
		//it also confuses the RASCAS delay which should be 3, but actually defined as 2 instead
		//in the end we lose one state machine step we otherwise need desperately
		//solution can not be implemented without changing the RAM and breaking the devboard - not recommended
		
		//BUG outcome: we lose the 8th pixel, so the image will be slightly pixelated


//2) resetting
		//init is used as a general reset, while, in relaity, init should be just the initialization
		//the state machine functions should be reset with the rest of the top functions
		//external reset is very noisy and engages all functions at the same time
		//resetting change recommended only after a good trigger has been generated
		
module SDRAM_driver_scope #(
			parameter					BURST_LENGTH = 9'b111,					//length is 8
			parameter					BURST_TYPE	 = 3'b11						//type is 8
)
(
			input 			[15:0]	data_from_sdram, 		// 16 bit bidirectional data bus. Ddata that is being received from the SDRAM
			output 			[15:0]  	data_to_sdram,			// 16 bit bidirectional data bus
																		// note: bidirectional buses must be defined teice on the top level, once as inputs and once as outputs

//SDRAM hardware interface																		
			output 			[12:0]	sd_addr,    			// A12-A0
			output 			[1:0] 	sd_dqm,     			// two byte masks. Assigned to the dqm pins. Allows the latching of multiple words. Not used.
			output 			[1:0] 	sd_ba,      			// BA1-BA0
			output 						sd_cs,      			// CS pin
			output 						sd_we,      			// WE pin
			output 						sd_ras,     			// RAS pin
			output 						sd_cas,     			// CAS pin

// command interface
			input 					 	init,	    				// init flag to reinitialize the SDRAM. Needs to be done once.
			input							top_level_reset,		// top reset flag. not used. bugs out functions
																		// since the SDRAM needs a very clear reset, any kind of noisy mess coming from outside would not work
			input 					 	fpga_clk,				// driver internal clock
			input							clkref,	   			// referece clock or top level (integration) clock = whatever is above the module, will be clocking with this clkref		
			
			input 			[25:0]   addr,       			// 26 bit byte address										
																		// addr is the concat of the 2 bank address ([25:24]), 13 the row address ([23:11]) and the 10 column address ([9:0])
																		// addr[10] is the A10 precharge bit, left ambigous

			input				[15:0]  	din,																																
			input 		 				we,         			// write enable flag
			input 			[3:0]    dqm,        			// data byte write mask
			input 		 				oeA,        			// read enable pin

			input							h_synch,					// image horzontal synch flag. Not used if input control aligns burst end to image row end.
			input							change_page,			// page change flag. Not used if input control aligns burst end to page change.
			
			output 	reg	[15:0]  	dout,

			output 	reg 				write_cycle_over = 1'b1,		//to track the state machine functions, we gave three different flags, depending on what the state machine was doing
			output 	reg 				read_cycle_over = 1'b1,
			output 	reg 				idle_cycle_over = 1'b1,
			output 	reg 				interrupt_cycle_over = 1'b1,		

			output 	reg 				input_ready = 1'b0,				// pulled high for 4 steps (5 in case of an interrupt) to step the write pixel counter 4 times (5 times) and log the incoming pixel burst
			output 	reg 				output_ready = 1'b0,				// ready flag. Only updates while reading.
			
			output 	reg 				write_is_interrupted = 1'b0,	//used to "lock" an interrupt state in until at least one idle state has come through. Used as a ram_we control above
			output 	reg 				SDRAM_initialized = 1'b0,		//will be pulled HIGH when the SDRAM is initialized. Used to sequentially reset the entire code with the SDRAM first and then the rest.

			
//debugging tool
			output 			[3:0]		q_debugger
);
	
	
//for our SDRAM, the mode register thus will be:

			localparam 					ACCESS_TYPE    = 1'b0;				//sequential access
			localparam 					CAS_LATENCY    = 3'd2;				//the amount of time it takes for the read data to emerge from the SDRAM
			localparam 					OP_MODE        = 2'b00;				//standard operation
			localparam 					WRITE_BURST 	= 1'b0;				//write burst


//this is the data to be published into the MODE REGISTER:
			localparam 					MODE = {5'b00000, WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_TYPE};
			
// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

			localparam 					RASCAS_DELAY   = 3'd2;  											// tRCD is between 14 ns and 18 ns
			localparam 					STATE_FIRST     = 4'd0;   											// first state in cycle																																									//0000
			localparam 					STATE_CMD_START = 4'd1;   											// state in which a new command can be started																																	//0001
			localparam 					STATE_CMD_CONT  = STATE_CMD_START + RASCAS_DELAY; 			//necessary RCD time has passed (measured in clock cycles/state steps)																	//0011
			localparam 					STATE_CMD_READ1  = STATE_CMD_CONT + CAS_LATENCY + 1;   	//the read information has arrived with CAS delay (with CAS of 2, it would be 10 ns, just past 2 cycles)						//0111
			localparam 					STATE_CMD_READ2  = STATE_CMD_READ1 + 1;																																														//1000
			localparam 					STATE_CMD_READ3  = STATE_CMD_READ2 + 1;																																														//1001
			localparam 					STATE_CMD_READ4  = STATE_CMD_READ3 + 1;																																														//1010
			localparam 					STATE_CMD_READ5  = STATE_CMD_READ4 + 1;
			localparam 					STATE_CMD_READ6  = STATE_CMD_READ5 + 1;
			localparam 					STATE_CMD_READ7  = STATE_CMD_READ6 + 1;
			localparam 					STATE_CMD_READ8  = STATE_CMD_READ7 + 1;

			localparam 					STATE_LAST      = 4'd15;  											// last state in cycle																																											//1111
		
			reg 				[3:0] 	q = STATE_FIRST;														//state machine will be 16 steps
			
//Note: 	the actual clock over speed of the SDRAM driver will be the driver clock divided by the number of steps. For 100 MHz and 16 steps, that will be 6.25 MHz. For 166 MHz and 8 steps, it will be 20.75 MHz.
//			The steps will follow each other with the driver clock.
//			The clock over speed is a mayor element and must always be kept in mind when changing the timing a layer above the driver.
//			When bursting, we eventually capture the burst with this clock over speed and not the driver clock. For 6.25 MHz and 8 burst, it will be the same data flux as 50 MHz and no burst (single element action).

//clkref is there to harmonize the SDRAM state machine to the external clock. Likely needed because we introduce some clock skew within the SDRAM.			
always @(posedge fpga_clk) begin
		if (init) q = STATE_FIRST;
   // force counter to pass state LAST->FIRST exactly after the rising edge of clkref
	// freeze state machine is to block the state machine during a longer write or read cycle
		else if (((q == STATE_LAST) && (clkref == 1)) || ((q == STATE_FIRST) && (clkref == 0)) || ((q != STATE_LAST) && (q != STATE_FIRST)) && !freeze_state_machine) q <= q + 4'd1;	
end

//above, we lack a reset
//generally, within the SDRAM we have a synch reset, not an asynch one. Could also be the source of many bugs.
//also, we reset everything according

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 3.2 us (32 100Mhz cycles) after FPGA config is done before going into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
			reg 				[4:0] 	reset;
			
always @(posedge fpga_clk) begin
	if (init) begin													//we initialize here using init. init is not the same as reset. init resets all, reset only the state of the SDRAM driver
		reset <= 5'h1f;												//init flag resets the reset register to full 1
		SDRAM_initialized <= 1'b0;
	end
	else if ((q == STATE_LAST) && (reset != 0))
		reset <= reset - 5'd1;										//reset must be 0 in order to proceed
	else SDRAM_initialized <= 1'b1;
end



// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

			localparam 					CMD_INHIBIT         = 4'b1111;
			localparam 					CMD_ACTIVE          = 4'b0011;						
			localparam 					CMD_READ            = 4'b0101;						
			localparam 					CMD_WRITE           = 4'b0100;						
			localparam 					CMD_BURST_TERMINATE = 4'b0110;						//burst terminate
			localparam 					CMD_PRECHARGE       = 4'b0010;						//we only use this during the reset sequence
			localparam 					CMD_AUTO_REFRESH    = 4'b0001;						
			localparam 					CMD_LOAD_MODE       = 4'b0000;						//we only use this during the reset sequence	
		
		
			wire 				[3:0] 	sd_cmd;   													// current command sent to sd ram

//assign command pins
assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];



// ---------------------------------------------------------------------
// ------------------ put things together ---------------------
// ---------------------------------------------------------------------

//read enable latched to a wire
			wire 									oe = oeA;		

//register used to store writing or reading enable commands
			reg 									acycle;

//counter to count, how many pixels we skip after an interrupt		

			reg				[8:0]				column_counter = 9'b0;					//count where we are in the burst, at which element (that is, which column we are writing into at the moment)

//Note: 	we can't change page while bursting, we only cycle columns (0-511 or a register sized [8:0])
//			If we don't change page, the burst will loop around and start again.
//			Changing page means restarting a state machine cycle and loading in a brand new address with the updated page number.

			reg									freeze_state_machine = 1'b0;			//this is the flag to force the state machine to stop while we want more steps than 16. Used only for bursts longer than 8.
			
//State machine assignment

//enables latched to wires internal to the state machine
			reg									in_state_we = 0;							//these are internal registers to store we and oeA values during an entire state machine clock over
			reg									in_state_oeA = 0;
			
always @(posedge fpga_clk) begin
	
	//SDRAM flag and signal reset
	if (init) begin																	//upon reset, we zero out all the flags
																									//mind, this is not the initialization reset. This is the functional reset.
		//internal write and read latches
		in_state_we <= 0;
		in_state_oeA <= 0;
		
		//write and read signals
		input_ready <= 0;
		output_ready <= 0;

		//cycle indicators
		write_cycle_over <= 1;																//the cycle over flags are HIGH when the cycle is over.
		read_cycle_over <= 1;
		idle_cycle_over <= 1;
		interrupt_cycle_over <= 1;
		
		//interrupt flag
		write_is_interrupted <= 0;															

		//burst length control
		freeze_state_machine <= 1'b0;													
		column_counter <= 9'b0;
	end

	
	else begin
		//acycle definition
		if (q == STATE_CMD_START) begin		//0010
				acycle <= oeA | we;
				in_state_we <= we;															//we want the we and the oeA to take effect only at the start of a state machine. No interrupts allowed.
				in_state_oeA <= oeA;
				
		end
	
	
		//Idle cycle
		if (!acycle) begin																	//we force idle on startup in the image capture module
			if (q == STATE_CMD_START + 1) begin
				idle_cycle_over <= 0;	//0011
			end
			else if (q == STATE_LAST) begin
				idle_cycle_over <= 1;			//1111
				write_is_interrupted <= 0;													//interrupt flag is zeroed out only once we know we have incremendted the idle state counter
																									//zeroing out before would mean that r_empty could confuse the setup
			end
		end
	
		//Write cycle for full page/flexible burst															//we have a flexible burst rate between either 4 and 8. 
		else if (acycle && in_state_we && !write_is_interrupted && !h_synch && !change_page) begin
			if(freeze_state_machine == 1) begin
				column_counter <= column_counter + 1;
				if(column_counter == (BURST_LENGTH - 3)) freeze_state_machine <= 0;					//freeze the state machine while bursting for 8/64/128/256/512 counts
																															//can't burst below 4 since it takes 3 write steps already to get to this spot
																															//Note: this freezing introduces a slight delay of 4 steps within the state machine when we burst for 8 compared to hardware-adjusted 8 burst.
																															//This delay is negligible under 25 MHz loading for a 100 MHz SDRAM (will be 1 pixel per write cycle, speed loss of 12.5%). It will be negligable under 50 MHz for 200 MHz SDRAM.
			end
			else
			if (q == STATE_CMD_CONT - 1) begin							//0011
					input_ready <= 1;																												
					write_cycle_over <= 0;
					//ADDED
					column_counter <= 9'b0;																			//if we don't have a zeroing here too, we may not zero out the column_counter whatsoever.
			end
			//following two lines removed would lead to a full rollback to 4 burst
			else if (q == STATE_CMD_CONT + 1)	freeze_state_machine <= 1;								//this is necessary to not confuse the command dynamics	
			else if (q == STATE_CMD_CONT + 2) begin
//			else if (q == STATE_CMD_CONT + 3) begin			
					input_ready <= 0;
					column_counter <= 9'b0;
					write_cycle_over <= 1;																			//might need to be one cycle later
			end
		end	
		
		//Read cycle											
						//Note:
						//This is hard-wired to be a 4-burst read. It is necessary to generate fast enough output for the HDMI.
		else if (acycle && in_state_oeA) begin
			if (q == STATE_CMD_READ1) begin
				dout[15:0] <= data_from_sdram[15:0];															//we publish the first element here
				output_ready <= 1;
				read_cycle_over <= 0;			
			end
			else if (q == STATE_CMD_READ2) dout[15:0] <= data_from_sdram[15:0];						//we publish the second element here
			else if (q == STATE_CMD_READ3) dout[15:0] <= data_from_sdram[15:0];						//we publish the third element here
			else if (q == STATE_CMD_READ4) dout[15:0] <= data_from_sdram[15:0];						//we publish the fourth element here
			else if (q == STATE_CMD_READ4 + 1) output_ready <= 0;											//for 4 burst, close here and 		
			else if (q == STATE_LAST) read_cycle_over <= 1;													//last step should be kept as-is to avoid bugs in timing
		end
		
		//Interrupt cycle
		//The interrupt cycle is only used when the burst and the input don't align.
		//Left in here in case an interrupt cycle will be used for later iterations.
		
//		else if (h_synch || change_page || !interrupt_cycle_over) begin
//			write_is_interrupted <= 1;													//interrupt flag is to force the interrupt and the following idle to occur
//			freeze_state_machine <= 0;
//			interrupt_cycle_over <= 0;
//			input_ready <= 0;																//we shut off the input ready signal the moment we enter the interrupt cycle
//			column_counter <= 9'b0;
//			write_cycle_over <= 1;
//			if (q == STATE_LAST) interrupt_cycle_over <= 1;
//		end	
	end
end


//Command registers definition

			wire 				[3:0] 	reset_cmd = ((q == STATE_CMD_START) && (reset == 13)) ? CMD_PRECHARGE : ((q == STATE_CMD_START) && (reset ==  2)) ? CMD_LOAD_MODE : CMD_INHIBIT;

			wire 				[3:0] 	run_cmd = 	((we || oe) && (q == STATE_CMD_START)) ? CMD_ACTIVE : 														//this need to stay we and oe since we assign the in_state_we values afterwards within teh state machine
			
															(in_state_we && (q == STATE_CMD_CONT))  ? CMD_WRITE : 
															
															(!in_state_we &&  oe && (q == STATE_CMD_CONT))  ? CMD_READ :
															
															(!in_state_we &&  oe && (q == STATE_CMD_READ3)) ? CMD_PRECHARGE :														//read burst end for 4 burst													
																																															//Note: we use the PRECHARGE command to close the read cycle
															
															((in_state_we && !write_is_interrupted && write_cycle_over) 															//write burst end
															|| (h_synch || change_page || !interrupt_cycle_over))  ? CMD_BURST_TERMINATE :						//interrupt burst terminate (not used)
																																															//Note: we use the BURST_TERMINATE command to "close" the full page burst. Since we want to carry on from where we started, PRECHARGE will not work here.
																																																	//BURST_TERMINATE leaves the bank active to restart writing.
															
															(!in_state_we && !oe && (q == STATE_CMD_START)) ? CMD_AUTO_REFRESH :
															
															CMD_INHIBIT;

															//Note:	write is instant after a command has been sent.
															//			burst write interrupt blocks the element it is engaged in parallel with
															//			burst read interrupt blocks the element after it is engaged
															//			read comes after cas delay
			
//Address registers
			
			wire 				[12:0] 	reset_addr = reset == 13 ? 13'b0010000000000 : MODE[12:0];

			wire 				[12:0] 	run_addr = q == STATE_CMD_START ? {addr[23:11]} : {2'b00, addr[10:0]}; 			//addr <= {5'b000000, write_pixel_counter[18:9], 1'b1 , 1'b0 , write_pixel_counter[8:0]};
																																					//A10 is the auto precharge bit. Needs to be HIGH for bursts that are not full page to automatically precharge the active row after use.
																																					//If no AUTO-PRECHARGE is used, the PRECHARGE command needs to be sent to the SDRAM to close the row, otherwise it will remain open and we can't change rows.
			
			
//Assignments
		 
assign sd_cmd = reset != 0 ? reset_cmd : run_cmd;

assign sd_addr = reset != 0 ? reset_addr : run_addr;

assign sd_ba = reset != 0 ? 2'b0 : addr[25:24];

assign data_to_sdram = din[15:0];

assign sd_dqm = in_state_we ? (q >= STATE_CMD_CONT + 1 ? dqm[3:2] : dqm[1:0]) : 2'b0;

//Debug tools
assign q_debugger = q;

endmodule