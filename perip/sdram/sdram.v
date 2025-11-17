module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);

  localparam IDLE              = 4'd0;
  localparam LMR               = 4'd1;
  localparam ACTIVE            = 4'd2;
  localparam READ              = 4'd3;
  localparam READ_WAIT         = 4'd4;
  localparam READ_BURST        = 4'd5;
  localparam WRITE             = 4'd6;
  localparam WRITE_WAIT        = 4'd7;
  localparam WRITE_BURST       = 4'd8;

  localparam CMD_NOP           = 4'b0111;
  localparam CMD_ACTIVE        = 4'b0011;
  localparam CMD_READ          = 4'b0101;
  localparam CMD_WRITE         = 4'b0100;
  localparam CMD_TERMINATE     = 4'b0110;
  localparam CMD_PRECHARGE     = 4'b0010;
  localparam CMD_REFRESH       = 4'b0001;
  localparam CMD_LMR           = 4'b0000;

  wire [3:0] cmd;

  assign cmd = { cs, ras, cas, we };

  reg  [ 2:0] cas_cnt       ;
  reg  [ 3:0] bl_cnt        ;
  
  wire [ 2:0] cas_latency   ;
  wire [ 3:0] burst_lenth   ;
  
  reg  [14:0] mode_register ;
  wire [ 1:0] bank_addr     ;
  reg  [12:0] row_addr_r    ;
  wire [ 8:0] col_addr      ;

  wire        nop           ;
  wire        mode_reg_we   ;
  wire        active_we     ;
  wire        col_addr_valid;
  wire        read          ;
  wire        write         ;
  wire        cas_cnt_valid ;
  wire        cas_cnt_done  ;
  wire        bl_cnt_valid  ;
  wire        bl_cnt_done   ;
  
  assign nop            = cmd == CMD_NOP || cmd[3];
  assign bank_addr      = ba;
  assign col_addr       = a[8:0];
  assign mode_reg_we    = next == LMR;
  assign active_we      = next == ACTIVE;
  assign col_addr_valid = next == READ || next == WRITE;
  assign read           = next == READ_BURST;
  assign write          = next == WRITE_BURST;

  assign cas_latency    = mode_register[6:4];
  assign cas_cnt_valid  = next == READ_WAIT  || next == WRITE_WAIT;
  assign cas_cnt_done   = cas_cnt == cas_latency - 1'd1;

  assign burst_lenth    = 1'd1 << mode_register[2:0];
  assign bl_cnt_valid   = read || write;
  assign bl_cnt_done    = bl_cnt  == burst_lenth;

  reg [3:0] state, next;

  always @(*) begin
    case (state)
      IDLE : begin
        if (nop || cmd == CMD_PRECHARGE || cmd == CMD_REFRESH) next = IDLE;
        else if (cmd == CMD_LMR)    next = LMR ;
        else if (cmd == CMD_ACTIVE) next = ACTIVE;
        else if (cmd == CMD_READ)   next = READ;
        else if (cmd == CMD_WRITE)  next = WRITE;
        else next = state;
      end
      LMR : begin
        if (nop || cmd == CMD_PRECHARGE || cmd == CMD_REFRESH) next = IDLE;
        else if (cmd == CMD_LMR)    next = LMR ;
        else if (cmd == CMD_ACTIVE) next = ACTIVE;
        else if (cmd == CMD_READ)   next = READ;
        else if (cmd == CMD_WRITE)  next = WRITE;
        else next = state;
      end
      ACTIVE : begin
        if (nop || cmd == CMD_PRECHARGE || cmd == CMD_REFRESH) next = IDLE;
        else if (cmd == CMD_LMR)    next = LMR ;
        else if (cmd == CMD_ACTIVE) next = ACTIVE;
        else if (cmd == CMD_READ)   next = READ;
        else if (cmd == CMD_WRITE)  next = WRITE;
        else next = state;
      end
      READ : begin
        if (cmd == CMD_TERMINATE) next = IDLE;
        else if (cmd == CMD_READ) next = READ;
        else next = READ_WAIT;
      end
      READ_WAIT : begin
        if (cmd == CMD_TERMINATE) next = IDLE;
        else if (cas_cnt_done) next = READ_BURST;
        else next = state;
      end
      READ_BURST : begin
        if (cmd == CMD_TERMINATE) next = IDLE;
        else if (bl_cnt_done) next = IDLE;
        else next = state;
      end
      WRITE : begin
        if (cmd == CMD_TERMINATE) next = IDLE;
        else if (cmd == CMD_WRITE) next = WRITE;
        else next = WRITE_WAIT;
      end
      WRITE_WAIT : begin
        if (cmd == CMD_TERMINATE) next = IDLE;
        else if (cas_cnt_done) next = WRITE_BURST;
        else next = state;
      end
      WRITE_BURST : begin
        if (cmd == CMD_TERMINATE) next = IDLE;
        else if (bl_cnt_done) next = IDLE;
        else next = state;
      end
      default : next = IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (mode_reg_we) begin
      mode_register <= { ba, a };
    end
  end

  reg [12:0] active_row [3:0];
  always @(posedge clk) begin
    if (active_we) begin
      row_addr_r  <= a;
      active_row[bank_addr] <= a;
    end
  end

  always @(posedge clk) begin
    if (cas_cnt_valid) begin
      if (cas_cnt_done) begin
        cas_cnt <= 3'd0;
      end
      else begin
        cas_cnt <= cas_cnt + 1'd1;
      end
    end
    else begin
      cas_cnt <= 3'd0;
    end
  end

  always @(posedge clk) begin
    if (bl_cnt_valid) begin
      if (bl_cnt_done) begin
        bl_cnt <= 4'd0;
      end
      else begin
        bl_cnt <= bl_cnt + 1'd1;
      end
    end
    else begin
      bl_cnt <= 4'd0;
    end
  end

// Address shift registers
  reg [2 + 13 + 9 - 1:0] addr_shift_reg [2:0];
  reg [1:0] dqm_r [2:0];
  always @(posedge clk) begin
    dqm_r[0] <= dqm;
    dqm_r[1] <= dqm_r[0];
    dqm_r[2] <= dqm_r[1];
  end
  always @(posedge clk) begin
    if (col_addr_valid) begin
      addr_shift_reg[0] <= { active_row[bank_addr], bank_addr, col_addr };
    end
    else begin
      addr_shift_reg[0] <= addr_shift_reg[0] + 1'd1;
    end
  end
  always @(posedge clk) begin
    addr_shift_reg[1] <= addr_shift_reg[0];
  end
  always @(posedge clk) begin
    addr_shift_reg[2] <= addr_shift_reg[1];
  end

// wdata shift registers
  reg [15:0] wdata_shift_reg [2:0];
  always @(posedge clk) begin
    wdata_shift_reg[0] <= dq;
  end
  always @(posedge clk) begin
    wdata_shift_reg[1] <= wdata_shift_reg[0];
  end
  always @(posedge clk) begin
    wdata_shift_reg[2] <= wdata_shift_reg[1];
  end

  always @(posedge clk) begin
    state <= next;
  end

  wire [ 1:0] dqm_valid ;
  wire [31:0] addr      ;
  wire [31:0] wdata     ;
  assign dqm_valid = dqm_r[cas_latency[1:0] - 1'd1];
  assign addr  = { 4'ha, 3'h0,  addr_shift_reg[cas_latency[1:0] - 1'd1], 1'b0 };
  assign wdata = { 16'h0000  , wdata_shift_reg[cas_latency[1:0] - 1'd1]       };

  wire dq_ctrl;

  assign dq_ctrl = read;
  assign dq = dq_ctrl ? rdata_r[15:0] : 16'bz;

  reg [31:0] sdram_rdata_r;
  reg [15:0] rdata_r;

// `ifdef ysyx_25050158_SIMULATION

import "DPI-C" function void sdram_read(input int addr, output int data);
import "DPI-C" function void sdram_write(input int addr, input byte data);
  always @(posedge clk) begin
    if (write) begin
      if (dqm_valid == 2'b00) begin
        sdram_write(addr    , wdata[ 7:0]);
        sdram_write(addr + 1, wdata[15:8]);
      end
      else if (dqm_valid == 2'b01) begin
        sdram_write(addr + 1, wdata[15:8]);
      end
      else if (dqm_valid == 2'b10) begin
        sdram_write(addr    , wdata[ 7:0]);
      end
    end
  end

  always @(read) begin
    if (read) begin
      sdram_read(addr, sdram_rdata_r);
    end
  end

  always @(posedge clk, posedge read, addr) begin
    if (read) begin
      if (~addr[1] && dqm_valid == 2'b10) begin
        rdata_r <= { 8'h00, sdram_rdata_r[ 7:0] };
      end
      else if (~addr[1] && dqm_valid == 2'b01) begin
        rdata_r <= { 8'h00, sdram_rdata_r[15:8] };
      end
      else if (~addr[1] && dqm_valid == 2'b00) begin
        rdata_r <= sdram_rdata_r[15:0];
      end
      else if (addr[1] && dqm_valid == 2'b10) begin
        rdata_r <= { 8'h00, sdram_rdata_r[23:16] };
      end
      else if (addr[1] && dqm_valid == 2'b01) begin
        rdata_r <= { 8'h00, sdram_rdata_r[31:24] };
      end
      else if (addr[1] && dqm_valid == 2'b00) begin
        rdata_r <= sdram_rdata_r[31:16];
      end
    end
  end

// `endif

endmodule
