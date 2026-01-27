module sdram_top_apb (
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

  output        sdram_clk,
  output        sdram_cke,
  output        sdram_cs,
  output        sdram_ras,
  output        sdram_cas,
  output        sdram_we,
  output [12:0] sdram_a,
  output [ 1:0] sdram_ba,
  output [ 3:0] sdram_dqm,
  inout  [31:0] sdram_dq
);

  wire [31:0] sdram_dout;
  reg [1:0] state;
  wire req_accept;
  assign sdram_dq[15: 0] = sdram_dout_en_low  ? sdram_dout[15: 0] : 16'bz;
  assign sdram_dq[31:16] = sdram_dout_en_high ? sdram_dout[31:16] : 16'bz;

  localparam ST_IDLE        = 2'd0;
  localparam ST_WAIT_ACCEPT = 2'd1;
  localparam ST_WAIT_ACK    = 2'd2;
  // typedef enum [1:0] { ST_IDLE, ST_WAIT_ACCEPT, ST_WAIT_ACK } state_t;

  assign req_accept = req_accept_high | req_accept_low  ;
  assign in_pready  = in_pready_high  | in_pready_low   ;
  assign in_pslverr = in_pslverr_high | in_pslverr_low  ;
  assign in_prdata  = { in_prdata_high[15:0], in_prdata_low[15: 0] };
  assign sdram_clk  = sdram_clk_high  ;
  assign sdram_cke  = sdram_cke_high  ;
  assign sdram_cs   = sdram_cs_high   ;
  assign sdram_ras  = sdram_ras_high  ;
  assign sdram_cas  = sdram_cas_high  ;
  assign sdram_we   = sdram_we_high   ;
  assign sdram_a    = sdram_a_high;
  assign sdram_ba   = sdram_ba_high;
  assign sdram_dqm  = {sdram_dqm_high, sdram_dqm_low} ;
  assign sdram_dout = {sdram_dout_high, sdram_dout_low};

  always @(posedge clock) begin
    if (reset) state <= ST_IDLE;
    else
      case (state)
        ST_IDLE: state <= (is_read || is_write ? (req_accept ? ST_WAIT_ACK : ST_WAIT_ACCEPT) : ST_IDLE);
        ST_WAIT_ACCEPT: state <= req_accept ? ST_WAIT_ACK : ST_WAIT_ACCEPT;
        ST_WAIT_ACK: if (in_pready) state <= ST_IDLE;
        default: state <= state;
      endcase
  end

  wire is_read  = ((in_psel && !in_penable) || (state == ST_WAIT_ACCEPT)) && !in_pwrite;
  wire is_write = ((in_psel && !in_penable) || (state == ST_WAIT_ACCEPT)) &&  in_pwrite;

  wire        req_accept_low      ;
  wire        in_pready_low       ;
  wire        in_pslverr_low      ;
  wire [31:0] in_prdata_low       ;
  wire        sdram_clk_low       ;
  wire        sdram_cke_low       ;
  wire        sdram_cs_low        ;
  wire        sdram_ras_low       ;
  wire        sdram_cas_low       ;
  wire        sdram_we_low        ;
  wire [ 1:0] sdram_dqm_low       ;
  wire [12:0] sdram_a_low         ;
  wire [ 1:0] sdram_ba_low        ;
  wire [15:0] sdram_dout_low      ;
  wire        sdram_dout_en_low   ;
  
  sdram_axi_core #(
    .SDRAM_MHZ(100),
    .SDRAM_ADDR_W(24),
    .SDRAM_COL_W(9),
    .SDRAM_READ_LATENCY(2)
  ) u_sdram_low_ctrl(
    .clk_i(clock),
    .rst_i(reset),
    .inport_wr_i(is_write ? { 2'b00, in_pstrb[1:0] } : 4'b0),
    .inport_rd_i(is_read),
    .inport_len_i(0),
    .inport_addr_i(in_paddr),
    .inport_write_data_i({ 16'h00, in_pwdata[15:0] }),
    .inport_accept_o(req_accept_low),
    .inport_ack_o(in_pready_low),
    .inport_error_o(in_pslverr_low),
    .inport_read_data_o(in_prdata_low),

    .sdram_clk_o(sdram_clk_low),
    .sdram_cke_o(sdram_cke_low),
    .sdram_cs_o(sdram_cs_low),
    .sdram_ras_o(sdram_ras_low),
    .sdram_cas_o(sdram_cas_low),
    .sdram_we_o(sdram_we_low),
    .sdram_dqm_o(sdram_dqm_low),
    .sdram_addr_o(sdram_a_low),
    .sdram_ba_o(sdram_ba_low),
    .sdram_data_input_i(sdram_dq[15:0]),
    .sdram_data_output_o(sdram_dout_low),
    .sdram_data_out_en_o(sdram_dout_en_low)
  );

  wire        req_accept_high     ;
  wire        in_pready_high      ;
  wire        in_pslverr_high     ;
  wire [31:0] in_prdata_high      ;
  wire        sdram_clk_high      ;
  wire        sdram_cke_high      ;
  wire        sdram_cs_high       ;
  wire        sdram_ras_high      ;
  wire        sdram_cas_high      ;
  wire        sdram_we_high       ;
  wire [ 1:0] sdram_dqm_high      ;
  wire [12:0] sdram_a_high        ;
  wire [ 1:0] sdram_ba_high       ;
  wire [15:0] sdram_dout_high     ;
  wire        sdram_dout_en_high  ;
  sdram_axi_core #(
    .SDRAM_MHZ(100),
    .SDRAM_ADDR_W(24),
    .SDRAM_COL_W(9),
    .SDRAM_READ_LATENCY(2)
  ) u_sdram_high_ctrl(
    .clk_i(clock),
    .rst_i(reset),
    .inport_wr_i(is_write ? { 2'b00, in_pstrb[3:2] } : 4'b0),
    .inport_rd_i(is_read),
    .inport_len_i(0),
    .inport_addr_i(in_paddr),
    .inport_write_data_i({ 16'h00, in_pwdata[31:16] }),
    .inport_accept_o(req_accept_high),
    .inport_ack_o(in_pready_high),
    .inport_error_o(in_pslverr_high),
    .inport_read_data_o(in_prdata_high),

    .sdram_clk_o(sdram_clk_high),
    .sdram_cke_o(sdram_cke_high),
    .sdram_cs_o(sdram_cs_high),
    .sdram_ras_o(sdram_ras_high),
    .sdram_cas_o(sdram_cas_high),
    .sdram_we_o(sdram_we_high),
    .sdram_dqm_o(sdram_dqm_high),
    .sdram_addr_o(sdram_a_high),
    .sdram_ba_o(sdram_ba_high),
    .sdram_data_input_i(sdram_dq[31:16]),
    .sdram_data_output_o(sdram_dout_high),
    .sdram_data_out_en_o(sdram_dout_en_high)
  );

endmodule
