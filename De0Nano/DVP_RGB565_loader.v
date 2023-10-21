//DVP loader module for RGB565 format
//Module converts incoming 8 bit RGB565 serial input into 16 bit RGB565 pixel values compatible with the image capture module


//Pixel output is expected to arrive on the posedge of the first pclk
//The loader expects HREF values - a signal indicating active pixels - and not HSYNCH - an image syncronization signal for the rows of the image
//The loader expects a pclk that can be divided by 2

//Note: the clock division likely introduces extra noise to the setup. A review of it is recommended in case of timing issues.

//KNOWN BUGS:
//1) Loading of the image is soemtimes pixelated. THis problem does not occur when using internal clocking.

module DVP_RGB565_loader (
		input								pclk, reset, href, vsynch,		//this is the hardware clock of the image capture device
		input								image_loader_enable,				//module enable
		input			[7:0]				input_8_bit,						//this is the 8 bit DVP output
		output		reg				output_clk,							//this will be the pixel clock
																					//for RGB565, pclk is simply 1/2 the input clock																					
		output							image_frame_active,				//goes HIGH at the moment when we have an active frame coming in															
		output	reg [15:0]			output_16_bit						//this is the 16-bit DVP output
);

		reg								byte_selector = 1;				//selector to choose, which part of the 16 bits are we loading
																					//if this selector is flipped, we have inverted colours on the output
		reg			[15:0]			output_latch;						//local storage of the 16 bit pixel data before publish


//on/off control		
		wire								image_loader_clk;
		
		assign image_loader_clk = pclk & image_loader_enable;
		
		
always @ (posedge image_loader_clk or posedge reset) begin
		if (reset == 1) begin
			byte_selector <= 1;
			output_latch <= 16'b0;
		end
		else begin
			if(href == 1 && active_frame) begin							//href goes HIGH when we have pixels coming in. Href is defined within the camera's initialization.
				byte_selector <= byte_selector + 1;
				if (byte_selector == 0) output_latch[7:0] = input_8_bit;
				else output_latch[15:8] =  input_8_bit;
			end
		end
end

		reg									active_frame = 0;

always @ (posedge image_loader_clk or posedge reset) begin
		if (reset == 1) begin
			active_frame <= 0;
		end
		else if (!vsynch) active_frame <= 1;							//we defined an active frame when we see vsynch go LOW the first time
																					//we capture only one frame due to how the image capture module works
end

assign image_frame_active = active_frame;

//the clock divider below divides the input clock by 2
//the input clock needs to be divided to gain the pixel clock for RGB565 format (but not for RAW and YUV!)

		wire								output_clk_latch;

upd_clock_divider #(
				.MODULO(2)
) pclk_gen (
				.clk(image_loader_clk),
				.rst(reset),
				.tick(output_clk_latch)
);


//assign the output clock
always @ (posedge image_loader_clk or posedge reset) begin
		if (reset == 1) begin
			output_clk <= 0;
		end
		else begin
			output_clk <= (href && active_frame)? output_clk_latch : 0;		//we only have an output clock signal when we have an active frame and we have pixel data coming on
		end
end


//assign the output
always @ (posedge output_clk) begin
		 output_16_bit <= output_latch;
end


endmodule
