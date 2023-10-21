//modified FIFO
//there are two "almost full" and "almost empty" flags that are generated flexibly
//these flags can be used for control a level above without the risk of losing data or timing - as is the problem with the original full and empty flags
//almost flag distance is defined by a decimal number between 0 and 63


//known BUGS

//1)The almost flag can not be the same size as the burst load/remove value
		//if the flag overlaps with what we load it with, the flag becomes ambiguous
		
//2)Since the  "almost flags" are mere indicators - unlike the w_full and r_empty flags, which shut off the FIFO. As such, they go immediately LOW if burst loading "oversteps" the validity of the flag.		

// Asynchronous FIFO module
module working_FIFO_mod #(

    // Parameters
    parameter   DATA_SIZE = 16,              // Number of data bits
    parameter   ADDR_SIZE = 4,              	// Number of bits for address
																														

	// We have one "almost" full/empty flag generated for each clock domain
	// The position of these flags can be flexibly defined
	// Default state, they are generated at position 4
	// Of note, the flags should always be further afar than the burst size we are using to avoid falling into some weird resonance state
	// Example, for a burst of 4, the almost flags should be at least 5 elements away from the empty/full
	
	 parameter	 ALMOST_FULL_FLAG_POS = 4, 	// position of the almost full flag. Takes a decimal number from 0 to 63
    parameter	 ALMOST_EMPTY_FLAG_POS = 4		// position of the almost empty flag. Takes a decimal number from 0 to 63
	 
) (

    // Inputs
    input       [DATA_SIZE-1:0] w_data,     // Data to be written to FIFO
    input                       w_en,       // Write data and increment addr.
    input                       w_clk,      // Write domain clock
    input   	                 w_rst,      // Write domain reset
    input                       r_en,       // Read data and increment addr.
    input                       r_clk,      // Read domain clock
    input   	                 r_rst,      // Read domain reset
    
    // Outputs
    output  	                 w_almost_full,		   // partly full
    output  	                 w_full,     				// Flag: 1 if FIFO is full
    output  reg [DATA_SIZE-1:0] r_data,     				// Data to be read from FIFO
    output  	                 r_almost_empty,       // Flag: 1 if FIFO is partly empty
    output  	                 r_empty     				// Flag: 1 if FIFO is empty
);

    // Constants
    localparam  FIFO_DEPTH  = (1 << ADDR_SIZE);
    
    // Internal signals
    wire    [ADDR_SIZE-1:0] w_addr;
    wire    [ADDR_SIZE:0]   w_gray;
    wire    [ADDR_SIZE-1:0] r_addr;
    wire    [ADDR_SIZE:0]   r_gray;
    
    // Internal storage elements
    reg     [ADDR_SIZE:0]   w_syn_r_gray;
    reg     [ADDR_SIZE:0]   w_syn_r_gray_pipe;
    reg     [ADDR_SIZE:0]   r_syn_w_gray;
    reg     [ADDR_SIZE:0]   r_syn_w_gray_pipe;
    
    // Declare memory
    reg     [DATA_SIZE-1:0] mem [0:FIFO_DEPTH-1];
    
    //--------------------------------------------------------------------------
    // Dual-port memory (should be inferred as block RAM)
    
    // Write data logic for dual-port memory (separate write clock)
    // Do not write if FIFO is full!
    always @ (posedge w_clk) begin
        if (w_en & !w_full) begin
            mem[w_addr] <= w_data;
        end
    end
    
    // Read data logic for dual-port memory (separate read clock)
    // Do not read if FIFO is empty!
    always @ (posedge r_clk) begin
        if (r_en & !r_empty) begin
            r_data <= mem[r_addr];
        end
    end
    
    //--------------------------------------------------------------------------
    // Synchronizer logic
    
    // Pass read-domain Gray code pointer to write domain
    always @ (posedge w_clk or posedge w_rst) begin
        if (w_rst == 1'b1) begin
            w_syn_r_gray_pipe <= 0;
            w_syn_r_gray <= 0;
        end else begin
            w_syn_r_gray_pipe <= r_gray;
            w_syn_r_gray <= w_syn_r_gray_pipe;
        end
    end
    
    // Pass write-domain Gray code pointer to read domain
    always @ (posedge r_clk or posedge r_rst) begin
        if (r_rst == 1'b1) begin
            r_syn_w_gray_pipe <= 0;
            r_syn_w_gray <= 0;
        end else begin
            r_syn_w_gray_pipe <= w_gray;
            r_syn_w_gray <= r_syn_w_gray_pipe;
        end
    end
    
    //--------------------------------------------------------------------------
    // Instantiate incrementer and full/empty checker modules
    
    // Write address increment and full check module
    w_ptr_full_mod #
	 (
			.ADDR_SIZE(ADDR_SIZE),
			.ALMOST_FULL_FLAG_POS(ALMOST_FULL_FLAG_POS)

	 )
	 w_ptr_full
	 (
        .w_syn_r_gray(w_syn_r_gray),
        .w_inc(w_en),
        .w_clk(w_clk),
        .w_rst(w_rst),
        .w_addr(w_addr),
        .w_gray(w_gray),
		  .w_almost_full(w_almost_full),
        .w_full(w_full)
    );
    
    // Read address increment and empty check module
    r_ptr_empty_mod #
	 (
			.ADDR_SIZE(ADDR_SIZE),
			.ALMOST_EMPTY_FLAG_POS(ALMOST_EMPTY_FLAG_POS)

	 )
	 r_ptr_empty
	 (
        .r_syn_w_gray(r_syn_w_gray),
        .r_inc(r_en),
        .r_clk(r_clk),
        .r_rst(r_rst),
        .r_addr(r_addr),
        .r_gray(r_gray),		  
		  .r_almost_empty(r_almost_empty),		  
        .r_empty(r_empty)
    );
    
endmodule