module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  wire [3:0] din, dout, douten;

  localparam IDLE  = 3'd0;
  localparam INST  = 3'd1;
  localparam ADDR  = 3'd2;
  localparam WRITE = 3'd3;
  localparam WAIT  = 3'd4;
  localparam READ  = 3'd5;

  localparam QSPI  = 1'd0;
  localparam QPI   = 1'd1;

  reg [2:0] PSRAM_state, PSRAM_next;
  reg BUS_state, BUS_next;

  reg  [5:0] data_cnt;
  wire [5:0] data_max;
  wire [2:0] data_step;
  wire data_cnt_valid;
  wire data_cnt_done;
  
  // State transition logic (combinational)
  wire is_write;

  always @(*) begin
    case (PSRAM_state)
      IDLE  : PSRAM_next = ~ce_n         ? INST : IDLE;
      INST  : PSRAM_next = data_cnt_done ? ADDR : INST;
      ADDR  : PSRAM_next = data_cnt_done ? (is_write ? WRITE : WAIT) : ADDR;
      WRITE : PSRAM_next = data_cnt_done ? IDLE : WRITE;
      WAIT  : PSRAM_next = data_cnt_done ? READ : WAIT;
      READ  : PSRAM_next = data_cnt_done ? READ : READ;
      default : PSRAM_next = PSRAM_state;
    endcase
  end

  always @(*) begin
    case (BUS_state)
      QSPI : BUS_next = cmd == 8'h35 ? QPI  : QSPI;
      QPI  : BUS_next = cmd == 8'hf5 ? QSPI : QPI ;
      default : BUS_next = BUS_state;
    endcase
  end

  assign is_write = cmd == 8'h38;

  MuxKey #(6, 3, 4) douten_ctrl (
    douten,
    PSRAM_state,
  {
    IDLE , 4'b0000,
    INST , 4'b0000,
    ADDR , 4'b0000,
    WRITE, 4'b0000,
    WAIT , 4'b0000,
    READ , 4'b1111
  });

  wire is_qpi;

  MuxKey #(6, 3, 3 + 6) data_sig_ctrl (
    { data_step, data_max },
    PSRAM_state,
  {
    IDLE , { 3'd0, 6'd0  },
    INST , is_qpi ? { 3'd4, 6'd8 } : { 3'd1, 6'd8 },
    ADDR , { 3'd4, 6'd24 },
    WRITE, { 3'd4, 6'd32 },
    WAIT , { 3'd1, 6'd6  },
    READ , { 3'd4, 6'd32 }
  });
  
  // State flip-flops (sequential)
  
  // 下降沿更新cnt
  always @(negedge sck, posedge ce_n) begin
    if (ce_n) begin
      data_cnt <= 'd0;
    end
    else if (data_cnt_done) begin
      data_cnt <= 'd0;
    end
    else if (data_cnt_valid) begin
      data_cnt <= data_cnt + { 3'd0, data_step };
    end
  end

  assign data_cnt_done = data_cnt >= data_max - { 3'd0, data_step };
  assign data_cnt_valid = PSRAM_state != IDLE;

  always @(negedge sck, ce_n) begin
    if (ce_n) begin
      PSRAM_state <= IDLE;
    end
    else begin
      PSRAM_state <= PSRAM_next;
    end
  end

  always @(posedge sck, ce_n) begin
    if (ce_n) begin
      BUS_state <= QSPI;
    end
    else begin
      BUS_state <= BUS_next;
    end
  end

  assign is_qpi = BUS_state == QPI;

  reg [31:0] m_data;

  // 上升沿采样din
  always @(posedge sck, posedge ce_n) begin
    if (ce_n) begin
      m_data <= 'd0;
    end
    else if (data_cnt_valid) begin
      if (PSRAM_state == INST) begin
        m_data[data_max - data_cnt[4:0] - 1] <= din[0];
      end
      else begin
        m_data[data_max - data_cnt[4:0] - { 3'd0, data_step } + 0] <= din[0];
        m_data[data_max - data_cnt[4:0] - { 3'd0, data_step } + 1] <= din[1];
        m_data[data_max - data_cnt[4:0] - { 3'd0, data_step } + 2] <= din[2];
        m_data[data_max - data_cnt[4:0] - { 3'd0, data_step } + 3] <= din[3];
      end
    end
  end

  // 上升沿更新dout
  reg [3:0] dout_r;
  
  always @(posedge sck, posedge ce_n) begin
    if (ce_n) begin
      dout_r <= 'd0;
    end
    else if (PSRAM_state == READ) begin
      dout_r[0] <= rdata[data_max - data_cnt[4:0] - { 3'd0, data_step } + 0];
      dout_r[1] <= rdata[data_max - data_cnt[4:0] - { 3'd0, data_step } + 1];
      dout_r[2] <= rdata[data_max - data_cnt[4:0] - { 3'd0, data_step } + 2];
      dout_r[3] <= rdata[data_max - data_cnt[4:0] - { 3'd0, data_step } + 3];
    end
  end

  assign dout = dout_r;
  
  reg [7:0] cmd;

  always @(negedge sck, posedge ce_n) begin
    if (ce_n) begin
      cmd <= 'd0;
    end
    else if (PSRAM_state == INST && data_cnt_done) begin
      cmd <= m_data[7:0];
    end
  end

  reg [31:0] addr;

  always @(negedge sck, posedge ce_n) begin
    if (ce_n) begin
      addr <= 'd0;
    end
    else if (PSRAM_state == ADDR && data_cnt_done) begin
      addr <= m_data;
    end
  end
  
  wire [31:0] wdata;
  assign wdata = PSRAM_state == WRITE ? m_data : 'd0;
  
  // Output logic
  assign dio[0] = douten[0] ? dout[0] : 1'bz;
  assign dio[1] = douten[1] ? dout[1] : 1'bz;
  assign dio[2] = douten[2] ? dout[2] : 1'bz;
  assign dio[3] = douten[3] ? dout[3] : 1'bz;
  assign din = dio;

import "DPI-C" function void test_data(input int data);
import "DPI-C" function void psram_read(input int raddr, output int rdata);
import "DPI-C" function void psram_write(input int waddr, input byte wdata);

  wire [31:0] rdata;
  reg  [31:0] rdata_r;

  always @(posedge sck) begin
    if (PSRAM_state == WAIT && data_cnt_done && ~is_write) begin // 有读请求时
      psram_read({8'h80, addr[23:0]}, rdata_r);
    end
  end

  assign rdata = { rdata_r[7:0], rdata_r[15:8], rdata_r[23:16], rdata_r[31:24] };

  always @(negedge sck) begin
    if (PSRAM_state == WRITE && is_write) begin // 有写请求时
      if (data_cnt == 6'd4) begin
        psram_write({8'h80, addr[23:0] + 24'd0}, wdata[31:24]);
      end
      else if (data_cnt == 6'd12) begin
        psram_write({8'h80, addr[23:0] + 24'd1}, wdata[23:16]);
      end
      else if (data_cnt == 6'd20) begin
        psram_write({8'h80, addr[23:0] + 24'd2}, wdata[15:8]);
      end
      else if (data_cnt == 6'd28) begin
        psram_write({8'h80, addr[23:0] + 24'd3}, wdata[7:0]);
      end
    end
  end

  always @(posedge sck) begin
    if (BUS_state == QPI) begin
      test_data(32'h66666666);
    end
  end

endmodule
