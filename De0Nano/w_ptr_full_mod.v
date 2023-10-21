// Increment write address and check if FIFO is full
module w_ptr_full_mod #(

    // Parameters
    parameter   															ADDR_SIZE = 4,   // Number of bits for address
	 parameter																ALMOST_FULL_FLAG_POS = 4		//decimal value, maximum 64

) (
    
    // Inputs
    input       					[ADDR_SIZE:0]   					w_syn_r_gray,   // Write-synced read Gray address. This is 1 bit bigger than the steps we can take for looping reasons.
    input                       										w_inc,          // 1 to increment address. This is the w_en signal.
    input                       										w_clk,          // Write domain clock.
    input                       										w_rst,          // Write domain reset
	 
    
    // Outputs 
    output      					[ADDR_SIZE-1:0] 					w_addr,         // Mem address to write to, that is, the number of steps the pointer will actually take
    output  			reg 		[ADDR_SIZE:0]   					w_gray,         // Gray write address output with +1 MSb for looping reasons.
    output  			reg                 							w_almost_full,//flag to show that we have the write pointer only 4 steps away from catching up with the read pointer
    output  			reg                 							w_full          // 1 if FIFO is full 	 
);

    // Internal signals
    wire    						[ADDR_SIZE:0]   					w_gray_next;    // Gray code version of the incremented address. This is 1 bit bigger than the steps we can take for looping reasons.
    wire    						[ADDR_SIZE:0]   					w_bin_next;     // Binary version of incremented address. This is 1 bit bigger than the steps we can take for looping reasons.
	 
    wire																		w_almost_full_val;
	 wire                    											w_full_val;     // FIFO is full
    
    // Internal storage elements
    reg     						[ADDR_SIZE:0]   					w_bin;          // Registered binary address
	 
    assign w_addr = w_bin[ADDR_SIZE-1:0];												 // Define w_addr to match the mem size (with MSB dropped)
    
    assign w_bin_next = w_bin + (w_inc & ~w_full);									 // Generate the next (incremented) address (if enable is set and FIFO is not full)
    
    assign w_gray_next = (w_bin_next >> 1) ^ w_bin_next;							 // Convert of the next binary write address to Gray write address
	 
//    assign w_bin_4th_next = w_bin + (w_inc & ~w_full) + (w_inc & ~w_full) + (w_inc & ~w_full) + (w_inc & ~w_full);
	 
	 //changed to 512 max
    wire								[8:0]									w_increment;	 // distance check is maximum 32 elements
	 
	 assign w_increment = (w_inc)? ALMOST_FULL_FLAG_POS : 0;

    wire    						[ADDR_SIZE:0]   					w_gray_almost_next;    // Gray code version of the incremented address. This is 1 bit bigger than the steps we can take for looping reasons.
    wire    						[ADDR_SIZE:0]   					w_bin_almost_next; 

	 assign w_bin_almost_next = w_bin + w_increment;

	 assign w_gray_almost_next = (w_bin_almost_next >> 1) ^ w_bin_almost_next;
	
//Is the FIFO full? 

    assign w_full_val = ((w_gray_next[ADDR_SIZE] != w_syn_r_gray[ADDR_SIZE]) && (w_gray_next[ADDR_SIZE-1] != w_syn_r_gray[ADDR_SIZE-1]) && (w_gray_next[ADDR_SIZE-2:0] == w_syn_r_gray[ADDR_SIZE-2:0]));
																									// we compare MSBs of the next Gray write address and the write-synched read Gray address			- != if w_full
																													//Why? Because we are looping around if w_full. After 1111 we have 10000. We looped if write is at 10000 and read is at 0000. Thus MSB !=.
																													//They Gray MSB will be this parity bit, indicating if we have looped or not. Since we look for looping, it must be different bitwise for the two Gray values
																									// we compare MSB-1s of the next Gray write address and the write-synched read Gray address		- != if w_full
																													//Why? Gray is symmetric on the MSB-1.
																									// we compare the rest																									- == if w_full
																													//the rest will be the same on the two sides of the mirror (they are mirrored themselves)
									
//Example: 	16 step pointer
	 
	// 00000
	//	00001
	//	00011			<-read pointer
	//	00010
	//	00110
	//	00111
	//	00101			
	//	00100
	//	01100
	//	01101
	//	01111
	//	01110
	//	01010
	//	01011
	//	01001
	//	01000


	// 11000
	//	11001
	//	11011			<- write pointer looped (distance is 16)
	//	11010
	//	10110
	//	10111
	//	10101			
	//	10100
	//	11100
	//	11101
	//	11111
	//	11110
	//	11010
	//	11011
	//	11001
	//	11000


			assign w_almost_full_val = ((w_gray_almost_next[ADDR_SIZE] != w_syn_r_gray[ADDR_SIZE]) && (w_gray_almost_next[ADDR_SIZE-1] != w_syn_r_gray[ADDR_SIZE-1]) && (w_gray_almost_next[ADDR_SIZE-2:0] == w_syn_r_gray[ADDR_SIZE-2:0]));
				 
    // Register the binary and Gray code pointers in the write clock domain
    always @ (posedge w_clk or posedge w_rst) begin
        if (w_rst == 1'b1) begin
            w_bin <= 0;
            w_gray <= 0;
        end else begin
            w_bin <= w_bin_next;
            w_gray <= w_gray_next;
        end
    end
    
    // Register the full flag
    always @ (posedge w_clk or posedge w_rst) begin
        if (w_rst == 1'b1) begin
            w_full <= 1'b0;				
				w_almost_full <= 1'b0;			
        end else begin
            w_full <= w_full_val;
				w_almost_full <= w_almost_full_val;
        end
    end
    
endmodule