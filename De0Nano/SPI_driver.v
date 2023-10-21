//this is an SPI driver for an FPGA. It can receive data on the mosi pin and send data on the miso pin
//sck is the clock of a single bit captured or published by the module - rising edge for capture, falling edge for publish
//cs is the active LOW chip select. Need a tristate definition on the hardware implementation
//miso is the hardware output
//mosi is the hardware input
//command_byte is the driver output
//response_byte is the driver input

//The assumption is that we have an SPI0 style communicator with a big endian data format.
//The driver can not deal with SPI variations.

//So, what does this module do?
//Technically it latches into an 8 bit register whatever is coming over on the MOSI line
//and does the same to the data we want to send by transforming it into a serialized MISO output
//both MOSI and MISO are governed by the same counter to ensure duplex behaviour
//the communication occurs on the rising and the falling edges of SCK - the external SPI clock

//above, on a top level, one will need to define, what specific answer is expected to a specific command. In other works, what data_to_send repsonse the incoming_data byte will generate
//of note, there will be a delay between request and response. This will be important when we do the data transfer.


//IMPORTANT! This module clocks at sys_clk and all generated elements are already within that clock domain.

//Note:
		//Due to the 8 bit nature of SPI, the time between two SPI commands can be as high as 1 us.


module SPI_driver (
				//Hardware input
				input								spi_sck,									//incoming SPI SCK clock
				input								spi_cs,									//incoming SPI CS signal
				input								spi_mosi,								//incoming MOSI data input

				//Driver input
				input								sys_clk,									//top level system clock
				input				[7:0]			response_byte,							//turned into MISO output in the fpga
				input				[15:0]		data_input_16_bit,					//16 bit data input
				
				//Transfer clock generator input/output
				input								data_transfer,							//indicate that data transfer is ongoing. Pulled HIHG after a readout command is received with the appropriate parameters. Pulled LOW when readout is stopped.
				input								reset,
				output							transfer_input_clk,					//generated transfer clock for capture module output control

//				//Debug output
				output							sck_test,								//probe
				
				//Hardware output
				output							spi_miso,								//outgoing MISO data output
				
				//Driver output
				output	reg 	[7:0]			command_byte							//generated from MOSI input within the driver
);


//////Clock crossing into the clock domains of the FPGA//////

		//Note:
		//the internal workings of the module will not use the raw inputs. All internal actions should align to the generates inputs, not the raw ones.

//SPI clock signal

				reg 				[2:0] 		spi_sck_latch;

always @ (posedge sys_clk) spi_sck_latch <= {spi_sck_latch[1:0], spi_sck};

		//Note:
		//We want to detect rising and falling edges of SCK in order to adjust the SPI mode accordingly
		//We aim for the simped SPI0 version, where clock polarity is 0 and clock phase is 0. 
		
				wire 								spi_sck_risingedge = (spi_sck_latch[2:1] == 2'b01);					//rising edge is when we see a 0 first, followed by a 1  
				wire 								spi_sck_fallingedge = (spi_sck_latch[2:1] == 2'b10);					//falling edge is when we see a 1 first, followed by a 0

//SPI chip select
		//Note:
		//chip select is active whenever we have an active package in the pipe
		//CS is active LOW!
	
				reg 				[2:0] 		spi_cs_latch;
		
always @	(posedge sys_clk) spi_cs_latch <= {spi_cs_latch[1:0], spi_cs};

				wire 								spi_cs_com_active = (spi_cs_latch[1] == 1'b0);  						//we define CS active if we see that we have a 0 within our latch. Mind, CS is active LOW, so on the output we will need pul pull this pin HIGH with a pullup resistor.
																																			//when CS signal is 0, that's when we ground the pin
					
				wire 								spi_cs_startmessage = (spi_cs_latch[2:1] == 2'b10); 					//same as before
				wire 								spi_cs_endmessage = (spi_cs_latch[2:1] == 2'b01); 						//same as before


//MOSI data input				

				reg 				[1:0]			spi_mosi_latch;
				
always @ (posedge sys_clk) spi_mosi_latch <= {spi_mosi_latch[0], spi_mosi};

				wire 								spi_mosi_data = spi_mosi_latch[1];
				


//////Internal counter//////				
				
//Duplex counting
		//Note:
		//we define a counter that will govern both the data input and the data output
		//this ensures duplex behaviour, i.e. that only when a bit is sent can we receive one and vica versa

				reg 				[2:0] 		bitcnt;																				//8 bit counter since SPI is an 8 bit com protocol

always @ (posedge sys_clk) begin
  if(!spi_cs_com_active)																											//if we don't have the CS active LOW, then we should reset the SPI communication by resetting the counter
    bitcnt <= 3'b000;
  else if(spi_sck_risingedge) begin																								//otherwise, we count on the rising edge of the SCK clock
    bitcnt <= bitcnt + 3'b001;
  end
end

				reg 					byte_is_received;
				reg					load_next_message;																				//the original setup was loading the responses only on CS start message. The modified one can deal with continous communication.
	
always @ (posedge sys_clk) byte_is_received <= spi_cs_com_active && spi_sck_risingedge && (bitcnt==3'b111);	//if we have counted 8 active bits, we pull the byte received flag HIGH

always @ (posedge sys_clk) load_next_message <= spi_cs_com_active && spi_sck_fallingedge && (bitcnt==3'b0);	//if we have sent 8 active bits, we pull the load next message flag HIGH
																																				//bitcount will be 3'b0 after the last bit is received on the last rising edge, so on the very last sck fall edge, it will already be 3'b0, not 3'b111

//////SPI duplex communication/////
	

//Receiver

				reg				[7:0] 		command_byte_latch;																//this is for the incoming data to cycle into
	
always @ (posedge sys_clk) begin
  if(!spi_cs_com_active)
    command_byte_latch <= 8'b0;																									//we empty the input latch when we pull CS low - maybe messes up timing??????
  else if(spi_sck_risingedge) begin
    command_byte_latch <= {command_byte_latch[6:0], spi_mosi_data};													//we assume a big endian input. MSB comes in first!
  end
end
	
always @ (posedge sys_clk) if (byte_is_received) command_byte <= command_byte_latch;							//we latch the incoming data to the output of the driver. This needs to be clocked to have FF synch on it.



//Transmitter

				reg 				[7:0] 		response_byte_latch;																//similarly to the receiver, we define a latch that will be updated with new values at certain moments
				
always @ (posedge sys_clk) begin
	if(spi_cs_com_active) begin		

//with data transfer//	
	  if(spi_cs_startmessage || load_next_message) response_byte_latch <= (data_transfer)? data_output_8_bit : response_byte;  			// at the start of communication or when we have a next message queued in, we load the transmitter latch with the data we want to send, depending on the state of the setup
																																													//we currently funnel data_transfer_byte into response byte in the command module. Funnneling here is likely more stabile.
																																													

	  else if(spi_sck_fallingedge) begin																						//	we transmit on the falling edge of SCK - SPI0 format of SPI
		 response_byte_latch <= {response_byte_latch[6:0], 1'b0};
	  end
	end	
end

//Tristate definition for the output

assign spi_miso = (spi_cs_com_active)? response_byte_latch[7] : 1'bZ;  												// we send the MSB first
																																			// we also define the tristate so the setup would not bable on the bus

//////SPI duplex communication/////


////////Data transfer input clock generation//////////

			//Note:
			//Since we need to extract 16 bits of data from the capture module, but the SPI is only 8 bits, we need to generate a clock that will tick over every time 2 bytes have been sent over to the master

		wire									transfer_input_clk_latch;
		wire									transfer_clk_source;
		
assign 	transfer_clk_source = spi_sck_fallingedge & data_transfer;													//we should only count falling edges if data_transfer has been pulled HIGH

mod_upd_clock_divider #(
				.MODULO(16)
) transfer_clk_gen (
				.clk(transfer_clk_source),
				.rst(reset),
				.tick(transfer_input_clk_latch)
);

					//Note:
					//			the transfer_input_clk will have the posedge the first time on the fourth SCK_falling edge of the command arriving after START_READOUT. This is done so any changes within the load will not disturb any ongoing data and command transfer.
					//			in other words, the data will be extracted from the capture module in the middle of the READOUT_PADDING command is being transfered/received.
					
					//Note:
					//			clock generator uses a modified divider to adjust, on which sck_fallingedge shall the clock signal be. Change the count starting value according to timing demand (currently at 10, putting the first edge on PADDING skc_fallingedge 4th).


assign transfer_input_clk = transfer_input_clk_latch;												//this could be simplified/removed here

				wire								update_output;												//wire defined for clarity only

assign update_output = byte_is_received;																//this is here for clarification. We update the output when we have received a full command byte. That is, the 8th sck_risingedge.
																													//reponse loading - load_next_message - comes on the 8th sck_falling edge, allowing adequate time to update the response_byte - the two will be 24 MHz apart in case we use SPI 12 MHz
																													
																													

////////Data transfer input generator//////////

//We load the 24 bit latch with the 16 bit input from the SDRAM

				reg 				[23:0] 		data_input_24_bit_latch = 24'b0;
				reg				[2:0]			shift_counter = 3'b0;
				reg								input_latch_shifted = 1'b1;
				
				
				reg				[15:0]		data_input_16_bit_dummy = 16'b1111000000001111;			//dummy data input of 240 and 15
																															//this works, albeit the line is VERY noisy even on 4 MHz.
																															
////////Data transfer input clock generation//////////

////////Data transfer and reply//////////
																															
//always @ (posedge sys_clk or posedge transfer_input_clk or posedge reset) begin				//upon the first transfer_input_clk (when we extract the first 16 bit), here we will have only 16 bits of zeros to latch-in
																															//we will need 3 additional PADDING commands to properly erase the dummy data ftrom the 24 bit input latch
always @ (posedge sys_clk or posedge reset) begin
																												
	if (reset == 1) begin
			data_input_24_bit_latch<= 24'b0;
			shift_counter <= 3'b0;
			input_latch_shifted <= 1'b1;
	end
	else begin
//		if (transfer_input_clk) data_input_24_bit_latch[15:0] <= data_input_16_bit_dummy[15:0];//load dummy data input
		if (transfer_input_clk) data_input_24_bit_latch[15:0] <= data_input_16_bit[15:0];		//upon arrival, the data is immediatelly logged into the 24 bit latch. May not be the case with the real hardware due to clock skew.
																															//it needs to be tested if we can clock the data into the 24 latch on the same transfer_input_clk as where we extract it, or not
																															//if we don't then we need to run 3 PADDINGs. If yes, we only need to run it once.
																															//actually, the problem can be circumvented by simply removing posedge transfer_input_clk from the definition. This way, the latching in will surely happen afterwards.
		else begin
				if(!input_latch_shifted) begin																	//if we haven't shifted yet, we do the lines below
					data_input_24_bit_latch <= {data_input_24_bit_latch[22:0], 1'b0};
					shift_counter <= shift_counter + 1;
					if (shift_counter == 3'b111) input_latch_shifted <= 1'b1;							//and after 8 shifts, we pull the "shift done" flag HIGH
				end
				else if (update_output) input_latch_shifted <= 1'b0;										//we want the shifting to commence only after the 8 MSBs have been removed from the 24 bit latch
																															//if not, then we may lose data
																															//also, update_output should NEVER overlap with shifting. This should be doable since update output comes about, at best, with 12/8 = 1.5 MHz, while we shift the entire setup in 50/8 = 6.25 MHz 
		end
	end
end


//Update output
//Upon the reception of "update_output", we latch the last 8 bits of the 3 byte input register to the output

				reg				[7:0]			data_output_8_bit_latch;
				wire				[7:0]			data_output_8_bit;										//wire defined for clarity only

always @ (posedge update_output or posedge reset) begin											//this could also be clocked at sys_clk eventually
	if (reset == 1) data_output_8_bit_latch <= 8'b0;	
	else if (data_transfer) data_output_8_bit_latch [7:0] <= data_input_24_bit_latch[23:16];
end


assign			data_output_8_bit =	data_output_8_bit_latch;

////////Data transfer and reply//////////

assign sck_test = spi_sck_fallingedge;												//probe
																													
endmodule
