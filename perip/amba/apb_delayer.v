/**
 * 521MHz
 * r = 5.21
 */

module apb_delayer(
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

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  parameter CORE_CLK = 521.425;
  parameter SOC_CLK  = 100    ;
  parameter AMP_C    = 8      ;
  
  // 5.21425 * 256 = 1334.848
  localparam R = CORE_CLK / SOC_CLK ;
  localparam S = 1 << AMP_C         ;
  localparam C = $rtoi(R * S)       ;

  localparam APB_IDLE     = 2'd0;
  localparam APB_SETUP    = 2'd1;
  localparam APB_ACCESS   = 2'd2;
  localparam APB_DONE     = 2'd3;

  localparam DELAY_IDLE   = 2'd0;
  localparam DELAY_SETUP  = 2'd1;
  localparam DELAY_START  = 2'd2;
  localparam DELAY_DONE   = 2'd3;

  reg [1:0] apb_state, apb_next;
  reg [1:0] delay_state, delay_next;

  reg  [31:0]  out_prdata_r ;
  reg          out_pready_r ;

  reg  [31:0]  delay_cnt      ;
  wire         delay_add      ;
  wire         delay_sub      ;
  wire         delay_done     ;

  reg  [31:0]  apb_cnt        ;
  wire         apb_cnt_valid  ;
  wire         apb_cnt_done   ;

  assign delay_add   = apb_cnt_valid;
  assign delay_sub   = delay_next == DELAY_START;
  assign delay_done  = delay_cnt  == (apb_cnt + 2);

  assign apb_cnt_valid = apb_next != APB_IDLE && apb_next != APB_DONE;
  assign apb_cnt_done = delay_done;

  always @(*) begin
    case (apb_state)
      APB_IDLE    : apb_next = in_psel    ? APB_SETUP  : APB_IDLE   ;
      APB_SETUP   : apb_next = APB_ACCESS ;
      APB_ACCESS  : apb_next = out_pready ? APB_DONE   : APB_ACCESS ;
      APB_DONE    : apb_next = delay_state == DELAY_DONE ? APB_IDLE : APB_DONE;
      default     : apb_next = APB_IDLE   ; 
    endcase
  end

  always @(*) begin
    case (delay_state)
      DELAY_IDLE  : delay_next = apb_next == APB_SETUP ? DELAY_SETUP : DELAY_IDLE ;
      DELAY_SETUP : delay_next = apb_next == APB_DONE  ? DELAY_START : DELAY_SETUP;
      DELAY_START : delay_next = delay_done            ? DELAY_DONE  : DELAY_START;
      DELAY_DONE  : delay_next = DELAY_IDLE;
      default     : delay_next = DELAY_IDLE; 
    endcase
  end

  always @(posedge clock) begin
    if (reset) begin
      delay_cnt <= 32'd0;
    end
    else if (delay_done) begin
      delay_cnt <= 32'd0;
    end
    else if (delay_add) begin
      delay_cnt <= delay_cnt + C;
    end
    else if (delay_state == DELAY_SETUP && delay_sub) begin
      delay_cnt <= (delay_cnt + C) >> AMP_C;
    end
    else if (delay_sub) begin
      delay_cnt <= delay_cnt - 1'd1;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      apb_cnt <= 32'd0;
    end
    else if (apb_cnt_done) begin
      apb_cnt <= 32'd0;
    end
    else if (apb_cnt_valid) begin
      apb_cnt <= apb_cnt + 1'd1;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      apb_state <= APB_IDLE;
    end
    else begin
      apb_state <= apb_next;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      delay_state <= DELAY_IDLE;
    end
    else begin
      delay_state <= delay_next;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      out_prdata_r <= 32'd0;
      out_pready_r <=  1'd0;
    end
    else if (delay_state == DELAY_DONE) begin
      out_prdata_r <= 32'd0;
      out_pready_r <=  1'd0;
    end
    else if (out_pready) begin
      out_prdata_r <= out_prdata;
      out_pready_r <= out_pready;
    end
  end

  assign out_psel    = apb_state != APB_DONE ? in_psel    :  1'd0;
  assign out_penable = apb_state != APB_DONE ? in_penable :  1'd0;
  assign out_pwrite  = apb_state != APB_DONE ? in_pwrite  :  1'd0;
  assign out_pprot   = apb_state != APB_DONE ? in_pprot   :  3'd0;

  assign out_paddr   = in_paddr;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;

  assign in_prdata   = delay_state == DELAY_DONE ? out_prdata_r  : 32'd0;
  assign in_pready   = delay_state == DELAY_DONE ? out_pready_r  :  1'd0;

  assign in_pslverr  = out_pslverr;

  `ifdef __VERILATOR__

  reg [103:0] dbg_delay_state;
  reg [103:0] dbg_apb_state;

  always @(*) begin
    case (delay_state)
      DELAY_IDLE    : dbg_delay_state = "DELAY_IDLE"  ;
      DELAY_START   : dbg_delay_state = "DELAY_START" ;
      DELAY_SETUP   : dbg_delay_state = "DELAY_SETUP" ;
      DELAY_DONE    : dbg_delay_state = "DELAY_DONE"  ;
      default       : dbg_delay_state = "UNKNOWN"     ;
    endcase
  end

  always @(*) begin
    case (apb_state)
      APB_IDLE    : dbg_apb_state = "APB_IDLE"  ;
      APB_SETUP   : dbg_apb_state = "APB_SETUP" ;
      APB_ACCESS  : dbg_apb_state = "APB_ACCESS";
      APB_DONE    : dbg_apb_state = "APB_DONE"  ;
      default     : dbg_apb_state = "UNKNOWN"   ;
    endcase
  end

`endif

endmodule
