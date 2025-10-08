// MSB first
module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);

  localparam IDLE = 0;
  localparam RECV = 1;
  localparam SEND = 2;
  
  reg  [2:0] recv_cnt;
  wire [2:0] recv_cnt_max;
  wire recv_valid;
  wire recv_done;
  
  reg  [2:0] send_cnt;
  wire [2:0] send_cnt_max;
  wire send_valid;
  wire send_done;
  
  reg [7:0] rdata_r;
  
  reg [1:0] state, next;
  
  // State transition logic (combinational)
  always @(*) begin
    case (state)
      IDLE : next = ~ss ? RECV : IDLE;
      RECV : next = recv_done ? SEND : RECV;
      SEND : next = send_done ? IDLE : SEND;
      default : next = state;
    endcase
  end
  
  assign recv_cnt_max = 3'd7;
  assign recv_valid = state == RECV;
  assign recv_done = recv_cnt == recv_cnt_max;
  assign send_cnt_max = 3'd7;
  assign send_valid = state == SEND;
  assign send_done = send_cnt == send_cnt_max;
  
  // State flip-flops (sequential)
  always @(posedge ss, posedge sck) begin
    if (ss) begin
      state <= IDLE;
    end
    state <= next;
  end

  always @(posedge ss, posedge sck) begin
    if (ss) begin
      recv_cnt <= 'd0;
    end
    else if (recv_done) begin
      recv_cnt <= 'd0;
    end
    else if (next == RECV) begin
      recv_cnt <= recv_cnt + 'd1;
    end
  end

  always @(posedge ss, posedge sck) begin
    if (ss) begin
      rdata_r <= 'd0;
    end
    if (recv_valid) begin
      rdata_r[recv_cnt] <= mosi;
    end
  end

  always @(posedge ss, posedge sck) begin
    if (ss) begin
      send_cnt <= 'd0;
    end
    if (send_done) begin
      send_cnt <= 'd0;
    end
    else if (send_valid) begin
      send_cnt <= send_cnt + 'd1;
    end
  end

  reg miso_r;

  always @(posedge ss, negedge sck) begin
    if (ss) begin
      miso_r <= 1'b1;
    end
    else if (state == IDLE) begin
      miso_r <= 1'b1;
    end
    else begin
      miso_r <= rdata_r[send_cnt_max - send_cnt];
    end
  end
  
  assign miso = miso_r;
endmodule
