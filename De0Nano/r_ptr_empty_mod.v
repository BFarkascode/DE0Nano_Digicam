// Increment read address and check if FIFO is empty
module r_ptr_empty_mod #(

    // Parameters
    parameter   															ADDR_SIZE = 4,   // Number of bits for address
	 parameter																ALMOST_EMPTY_FLAG_POS = 4	 //decimal number up to 64

) (
    
    // Inputs
    input       					[ADDR_SIZE:0]   					r_syn_w_gray,   // Synced write Gray pointer
    input                       										r_inc,          // 1 to increment address
    input                       										r_clk,          // Read domain clock
    input                       										r_rst,          // Read domain reset

    // Outputs
    output      					[ADDR_SIZE-1:0] 					r_addr,         // Mem address to read from
    output  			reg 		[ADDR_SIZE:0]   					r_gray,         // Gray address with +1 MSb
    output  			reg                 							r_almost_empty,	 
    output  			reg                 							r_empty         // 1 if FIFO is empty
);
    
    // Internal signals
    wire    						[ADDR_SIZE:0]   					r_bin_next;     // Binary version of address
    wire    						[ADDR_SIZE:0]   					r_gray_next;    // Gray code version of address
    wire    						[ADDR_SIZE:0]   					r_bin_almost_next;     // Binary version of address
    wire    						[ADDR_SIZE:0]   					r_gray_almost_next;    // Gray code version of address
	 wire																		r_almost_empty_val;
    wire                    											r_empty_val;    // FIFO is empty
    
    // Internal storage elements
    reg     						[ADDR_SIZE:0]   					r_bin;          // Registered binary address

	 //changed to 512 max
    wire								[8:0]									r_increment;		 // distance check is maximum 32 elements


    
    assign r_addr = r_bin[ADDR_SIZE-1:0];
    
    //We generate the next pointer positions
	 
	 assign r_bin_next = r_bin + (r_inc & ~r_empty);
    
    assign r_gray_next = (r_bin_next >> 1) ^ r_bin_next;
	 
	 //We generate the next pointer position for the almost flag
	 
	 assign r_increment = (r_inc)? ALMOST_EMPTY_FLAG_POS : 0;
	 
	 assign r_bin_almost_next = r_bin + r_increment;	 

	 assign r_gray_almost_next = (r_bin_almost_next >> 1) ^ r_bin_almost_next;
    
    // If the synced write Gray code is equal to the current read Gray code,
    // then the pointers have caught up to each other and the FIFO is empty
    assign r_empty_val = (r_gray_next == r_syn_w_gray);
	 
	 assign r_almost_empty_val = (r_gray_almost_next == r_syn_w_gray);			
	 
//Example: 	16 step pointer
	 
	//  0000
	//	 0001
	//	 0011			<-read pointer
	//	 0010
	//	 0110
	//	 0111
	//	 0101
	//	 0100
	
	//	 1100
	//	 1101
	//	 1111
	//	 1110
	//	 1010
	//	 1011
	//	 1001
	//	 1000
	// 11000
	//	11001
	//	11011			<- write pointer looped (distance is 16)
	//	11010

	//the pointers are actually identical, they just flag their respective "end of party" signals differently. Getting distance data from them should not be different on write or read side.
	//Also, there is no positive or negative here, we just compare relative positions and do something if that relative position turns out to be a certain value
	  
    // Register the binary and Gray code pointers in the read clock domain
    always @ (posedge r_clk or posedge r_rst) begin
        if (r_rst == 1'b1) begin
            r_bin <= 0;
            r_gray <= 0;
        end else begin
            r_bin <= r_bin_next;
            r_gray <= r_gray_next;
        end
    end
    
    // Register the empty flag
    always @ (posedge r_clk or posedge r_rst) begin
        if (r_rst == 1'b1) begin
            r_empty <= 1'b1;
				r_almost_empty <= 1'b1;			
        end else begin
            r_empty <= r_empty_val;			
				r_almost_empty <= r_almost_empty_val;
        end
    end
    
endmodule