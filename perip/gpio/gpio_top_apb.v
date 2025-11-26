module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

`ifndef TAPE_OUT_SIM

`define LED_ADDR    32'h10002000
`define SWITCH_ADDR 32'h10002004
`define SEG_ADDR    32'h10002008

  reg [31:0] led        ;
  reg [31:0] seg_data   ;
  reg [31:0] in_prdata_r;

  reg [1:0] state, next;

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
      led         <= 32'd0;
      seg_data    <= 32'd0;
      in_prdata_r <= 32'd0;
    end
    else if (next == ACCESS && in_pwrite) begin
      if ({ in_paddr[31:2], 2'b00 } == `LED_ADDR) begin
        led <= {
          in_pwdata[31:24] & {8{in_pstrb[3]}},
          in_pwdata[23:16] & {8{in_pstrb[2]}},
          in_pwdata[15: 8] & {8{in_pstrb[1]}},
          in_pwdata[ 7: 0] & {8{in_pstrb[0]}}
        };
      end
      else if ({ in_paddr[31:2], 2'b00 } == `SEG_ADDR) begin
        seg_data <= {
          in_pwdata[31:24] & {8{in_pstrb[3]}},
          in_pwdata[23:16] & {8{in_pstrb[2]}},
          in_pwdata[15: 8] & {8{in_pstrb[1]}},
          in_pwdata[ 7: 0] & {8{in_pstrb[0]}}
        };
      end
    end
    else if (next == ACCESS && !in_pwrite) begin
      if ({ in_paddr[31:2], 2'b00 } == `SWITCH_ADDR) begin
        in_prdata_r <= { 16'h0, gpio_in };
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

  assign gpio_out   = led[15:0];
  assign in_pready  = in_penable & in_psel;
  assign in_prdata  = in_prdata_r;
  assign in_pslverr = 1'b0;

  Segment segment_inst0(1'b0, 1'b1, 1'b1, {3'h0, seg_data[ 3: 0]}, gpio_seg_0);
  Segment segment_inst1(1'b0, 1'b1, 1'b1, {3'h0, seg_data[ 7: 4]}, gpio_seg_1);
  Segment segment_inst2(1'b0, 1'b1, 1'b1, {3'h0, seg_data[11: 8]}, gpio_seg_2);
  Segment segment_inst3(1'b0, 1'b1, 1'b1, {3'h0, seg_data[15:12]}, gpio_seg_3);
  Segment segment_inst4(1'b0, 1'b1, 1'b1, {3'h0, seg_data[19:16]}, gpio_seg_4);
  Segment segment_inst5(1'b0, 1'b1, 1'b1, {3'h0, seg_data[23:20]}, gpio_seg_5);
  Segment segment_inst6(1'b0, 1'b1, 1'b1, {3'h0, seg_data[27:24]}, gpio_seg_6);
  Segment segment_inst7(1'b0, 1'b1, 1'b1, {3'h0, seg_data[31:28]}, gpio_seg_7);
`endif

endmodule
