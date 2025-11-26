module ps2_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  input         ps2_clk,
  input         ps2_data
);

`ifndef TAPE_OUT_SIM

`define KEY_ADDR        32'h10011000
`define KEY_QUEUE_WIDTH 3

  wire [7:0] data     ;
  reg  [7:0] key_code [2**`KEY_QUEUE_WIDTH - 1:0] ;

  reg  [`KEY_QUEUE_WIDTH-1:0] read_ptr, write_ptr ;

  wire ready      ;
  wire nextdata_n ;
  wire overflow   ;

  wire read, write;
  wire key_enqueue;

  reg [31:0] in_prdata_r;

  reg [1:0] state, next ;

  localparam IDLE   = 2'd0;
  localparam SETUP  = 2'd1;
  localparam ACCESS = 2'd2;

  always @(*) begin
    case (state)
      IDLE    : next = in_psel   ? SETUP  : IDLE  ;
      SETUP   : next = 1'd1      ? ACCESS : SETUP ;
      ACCESS  : next = in_pready ? IDLE   : ACCESS;
      default : next = state;
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      in_prdata_r <= 32'd0;
    end
    else if (write) begin
      
    end
    else if (read) begin
      if ({ in_paddr[31:2], 2'b00 } == `KEY_ADDR) begin
        if (read_ptr == write_ptr) begin
          // FIFO 为空，返回 0，告诉软件现在没数据
          in_prdata_r <= 32'd0; 
        end
        else begin
          // FIFO 有数据，正常返回
          in_prdata_r <= { 24'h0, key_code[read_ptr] };
        end
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      state <= 2'd0;
    end
    else begin
      state <= next;
    end
  end

  assign in_pready  = state == ACCESS;
  assign in_prdata  = in_prdata_r;
  assign in_pslverr = 1'b0;

  assign read  = next == ACCESS && !in_pwrite;
  assign write = next == ACCESS &&  in_pwrite;

  assign nextdata_n = ~ready;
  assign key_enqueue = ready;

  ps2_keyboard ps2_keyboard(clock, ~reset, ps2_clk, ps2_data, data, ready, nextdata_n, overflow);

  integer i;
  always @(posedge clock) begin
    if (reset) begin
      for (i = 0; i < 2**`KEY_QUEUE_WIDTH; i = i + 1) begin
        key_code[i] = 8'd0;
      end
    end
    else if (key_enqueue) begin
      key_code[write_ptr] <= data;
    end
  end

// Queue pointer
  always @(posedge clock) begin
    if (reset) begin
      read_ptr <= `KEY_QUEUE_WIDTH'd0;
    end
    else if (read && read_ptr != write_ptr) begin
      read_ptr <= read_ptr + 1'd1;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      write_ptr <= `KEY_QUEUE_WIDTH'd0;
    end
    else if (key_enqueue) begin
      write_ptr <= write_ptr + 1'd1;
    end
  end

`endif

endmodule

module ps2_keyboard(clk,clrn,ps2_clk,ps2_data,data,
                    ready,nextdata_n,overflow);
  input clk,clrn,ps2_clk,ps2_data;
  input nextdata_n;
  output [7:0] data;
  output reg ready;
  output reg overflow;     // fifo overflow
  // internal signal, for test
  reg [9:0] buffer;        // ps2_data bits
  reg [7:0] fifo[7:0];     // data fifo
  reg [2:0] w_ptr,r_ptr;   // fifo write and read pointers
  reg [3:0] count;  // count ps2_data bits
  // detect falling edge of ps2_clk
  reg [2:0] ps2_clk_sync;

  always @(posedge clk) begin
    ps2_clk_sync <=  {ps2_clk_sync[1:0],ps2_clk};
  end

  wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

  always @(posedge clk) begin
    if (clrn == 0) begin // reset
      count <= 0; w_ptr <= 0; r_ptr <= 0; overflow <= 0; ready<= 0;
    end
    else begin
      if ( ready ) begin // read to output next data
        if(nextdata_n == 1'b0) //read next data
        begin
          r_ptr <= r_ptr + 3'b1;
          if(w_ptr==(r_ptr+1'b1)) //empty
            ready <= 1'b0;
        end
      end
      if (sampling) begin
        if (count == 4'd10) begin
          if ((buffer[0] == 0) &&  // start bit
              (ps2_data)       &&  // stop bit
              (^buffer[9:1])) begin      // odd  parity
            fifo[w_ptr] <= buffer[8:1];  // kbd scan code
            w_ptr <= w_ptr+3'b1;
            ready <= 1'b1;
            overflow <= overflow | (r_ptr == (w_ptr + 3'b1));
          end
          count <= 0;     // for next
        end else begin
          buffer[count] <= ps2_data;  // store ps2_data
          count <= count + 3'b1;
        end
      end
    end
  end
  assign data = fifo[r_ptr]; //always set output data

endmodule
