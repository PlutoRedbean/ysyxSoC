// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

//
// Flash settings
//
`define FLASH_ADDR_START 32'h30000000
`define FLASH_ADDR_END   32'h3fffffff

localparam NORMAL        = 3'd0;
localparam XIP_INIT_SS   = 3'd1;
localparam XIP_INIT_CTRL = 3'd2;
localparam XIP_INIT_DIVI = 3'd3;
localparam XIP_SEND      = 3'd4;
localparam XIP_BOOT      = 3'd5;
localparam XIP_WAIT      = 3'd6;
localparam XIP_READ      = 3'd7;

localparam IDLE   = 2'd0;
localparam SETUP  = 2'd1;
localparam ACCESS = 2'd2;

wire is_flash;

wire [2:0] XIP_state, XIP_next;
wire [1:0] APB_state, APB_next;

wire transfer;

wire [ 4:0] wb_adr_i;
wire [31:0] wb_dat_i;
wire [31:0] wb_dat_o;
wire [ 3:0] wb_sel_i;
wire        wb_we_i ;
wire        wb_stb_i;
wire        wb_cyc_i;
wire        wb_ack_o;

wire [31:0] XIP_in_paddr  ;
wire [31:0] XIP_in_pwdata ;
wire [ 3:0] XIP_in_pstrb  ;
wire        XIP_in_pwrite ;
wire        XIP_in_psel   ;
wire        XIP_in_penable;

`ifdef TAPE_OUT_SIM
ysyx_25050158_Reg #(3, NORMAL) XIP_state_r(clock, reset, XIP_next, XIP_state, 1'b1);
ysyx_25050158_Reg #(2, IDLE  ) APB_state_r(clock, reset, APB_next, APB_state, 1'b1);
`else
Reg #(3, NORMAL) XIP_state_r(clock, reset, XIP_next, XIP_state, 1'b1);
Reg #(2, IDLE  ) APB_state_r(clock, reset, APB_next, APB_state, 1'b1);
`endif

`ifdef TAPE_OUT_SIM
ysyx_25050158_MuxKeyWithDefault #(8, 3, 3) XIP_FSM (XIP_next, XIP_state, NORMAL, {
`else
MuxKeyWithDefault #(8, 3, 3) XIP_FSM (XIP_next, XIP_state, NORMAL, {
`endif
  NORMAL       , is_flash && in_psel ? XIP_INIT_SS   : NORMAL       ,
  XIP_INIT_SS  , wb_ack_o ? XIP_INIT_CTRL : XIP_INIT_SS  ,
  XIP_INIT_CTRL, wb_ack_o ? XIP_INIT_DIVI : XIP_INIT_CTRL,
  XIP_INIT_DIVI, wb_ack_o ? XIP_SEND      : XIP_INIT_DIVI,
  XIP_SEND     , wb_ack_o ? XIP_BOOT      : XIP_SEND     ,
  XIP_BOOT     , wb_ack_o ? XIP_WAIT      : XIP_BOOT     ,
  XIP_WAIT     , wb_ack_o && ~in_prdata[8] ? XIP_READ      : XIP_WAIT     ,
  XIP_READ     , wb_ack_o ? NORMAL        : XIP_READ
});

`ifdef TAPE_OUT_SIM
ysyx_25050158_MuxKeyWithDefault #(3, 2, 2) APB_FSM (APB_next, APB_state, IDLE, {
`else
MuxKeyWithDefault #(3, 2, 2) APB_FSM (APB_next, APB_state, IDLE, {
`endif
  IDLE  , transfer ? SETUP : IDLE,
  SETUP , ACCESS,
  ACCESS, ~wb_ack_o ? ACCESS :
          transfer  ? SETUP  : IDLE
});

`ifdef TAPE_OUT_SIM
ysyx_25050158_MuxKey #(8, 3, 32 + 32 + 4 + 1) data_mux (
`else
MuxKey #(8, 3, 32 + 32 + 4 + 1) data_mux (
`endif
  { XIP_in_paddr, XIP_in_pwdata, XIP_in_pstrb, XIP_in_pwrite },
  XIP_state,
{
  NORMAL       , { 32'h00000000, 32'h00000000                  , 4'b0000, 1'b0 },
  XIP_INIT_SS  , { 32'h10001018, 32'h00000001                  , 4'b0001, 1'b1 },
  XIP_INIT_CTRL, { 32'h10001010, 32'h00002440                  , 4'b0011, 1'b1 },
  XIP_INIT_DIVI, { 32'h10001014, 32'h00000000                  , 4'b1111, 1'b1 },
  XIP_SEND     , { 32'h10001004, {8'h03, in_paddr[23:2], 2'b00}, 4'b1111, 1'b1 },
  XIP_BOOT     , { 32'h10001010, 32'h00002540                  , 4'b0011, 1'b1 },
  XIP_WAIT     , { 32'h10001010, 32'h00000000                  , 4'b0000, 1'b0 },
  XIP_READ     , { 32'h10001000, 32'h00000000                  , 4'b0000, 1'b0 }
});

`ifdef TAPE_OUT_SIM
ysyx_25050158_MuxKey #(3, 2, 1 + 1) APB_signal_mux (
`else
MuxKey #(3, 2, 1 + 1) APB_signal_mux (
`endif
  { XIP_in_psel, XIP_in_penable },
  APB_state,
{
  IDLE  , { 1'b0, 1'b0 },
  SETUP , { 1'b1, 1'b0 },
  ACCESS, { 1'b1, 1'b1 }
});

assign transfer = XIP_state != NORMAL;

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(wb_adr_i),
  .wb_dat_i(wb_dat_i),
  .wb_dat_o(wb_dat_o),
  .wb_sel_i(wb_sel_i),
  .wb_we_i (wb_we_i),
  .wb_stb_i(wb_stb_i),
  .wb_cyc_i(wb_cyc_i),
  .wb_ack_o(wb_ack_o),
  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

assign wb_adr_i = is_flash ? XIP_in_paddr[4:0] : in_paddr[4:0];
assign wb_dat_i = is_flash ? XIP_in_pwdata     : in_pwdata    ;
assign wb_sel_i = is_flash ? XIP_in_pstrb      : in_pstrb     ;
assign wb_we_i  = is_flash ? XIP_in_pwrite     : in_pwrite    ;
assign wb_stb_i = is_flash ? XIP_in_psel       : in_psel      ;
assign wb_cyc_i = is_flash ? XIP_in_penable    : in_penable   ;

assign in_pready = is_flash ? XIP_state == XIP_READ && wb_ack_o : wb_ack_o;
assign in_prdata = wb_dat_o;

assign is_flash = `FLASH_ADDR_START <= in_paddr && in_paddr <= `FLASH_ADDR_END;

`ifdef SIMULATION
// always @(posedge clock) begin
//   if (is_flash && in_pwrite) begin
//     $fwrite("Assertion failed: trying to write flash\n");
//     $fatal;
//   end
// end
`endif

`endif // FAST_FLASH

endmodule
