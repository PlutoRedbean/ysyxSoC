`include "autoconf.vh"

module axi4_delayer(
  input         clock,
  input         reset,

  output        in_arready,
  input         in_arvalid,
  input  [3:0]  in_arid,
  input  [31:0] in_araddr,
  input  [7:0]  in_arlen,
  input  [2:0]  in_arsize,
  input  [1:0]  in_arburst,
  input         in_rready,
  output        in_rvalid,
  output [3:0]  in_rid,
  output [31:0] in_rdata,
  output [1:0]  in_rresp,
  output        in_rlast,
  output        in_awready,
  input         in_awvalid,
  input  [3:0]  in_awid,
  input  [31:0] in_awaddr,
  input  [7:0]  in_awlen,
  input  [2:0]  in_awsize,
  input  [1:0]  in_awburst,
  output        in_wready,
  input         in_wvalid,
  input  [31:0] in_wdata,
  input  [3:0]  in_wstrb,
  input         in_wlast,
  input         in_bready,
  output        in_bvalid,
  output [3:0]  in_bid,
  output [1:0]  in_bresp,

  input         out_arready,
  output        out_arvalid,
  output [3:0]  out_arid,
  output [31:0] out_araddr,
  output [7:0]  out_arlen,
  output [2:0]  out_arsize,
  output [1:0]  out_arburst,
  output        out_rready,
  input         out_rvalid,
  input  [3:0]  out_rid,
  input  [31:0] out_rdata,
  input  [1:0]  out_rresp,
  input         out_rlast,
  input         out_awready,
  output        out_awvalid,
  output [3:0]  out_awid,
  output [31:0] out_awaddr,
  output [7:0]  out_awlen,
  output [2:0]  out_awsize,
  output [1:0]  out_awburst,
  input         out_wready,
  output        out_wvalid,
  output [31:0] out_wdata,
  output [3:0]  out_wstrb,
  output        out_wlast,
  output        out_bready,
  input         out_bvalid,
  input  [3:0]  out_bid,
  input  [1:0]  out_bresp
);

  parameter CORE_CLK = `CORE_FREQ;
  parameter SOC_CLK  = 100;
  parameter AMP_C    = 8;

  localparam S = 1 << AMP_C;
  localparam C = $rtoi((CORE_CLK * S) / SOC_CLK);

`ifdef CONFIG_SOC_DELAY
  reg         rd_active;
  reg         rd_req_done;
  reg  [31:0] rd_real_cnt;
  reg  [31:0] rd_delay_cnt;
  reg  [3:0]  rd_buf_cnt;
  reg  [2:0]  rd_wptr;
  reg  [2:0]  rd_rptr;
  reg  [3:0]  rd_buf_id     [0:7];
  reg  [31:0] rd_buf_data   [0:7];
  reg  [1:0]  rd_buf_resp   [0:7];
  reg         rd_buf_last   [0:7];
  reg  [31:0] rd_buf_target [0:7];

  reg         wr_active;
  reg         wr_aw_done;
  reg         wr_w_done;
  reg  [31:0] wr_real_cnt;
  reg  [31:0] wr_delay_cnt;
  reg         wr_b_hold_valid;
  reg  [3:0]  wr_bid_r;
  reg  [1:0]  wr_bresp_r;
  reg  [31:0] wr_b_target;

  wire rd_start;
  wire rd_ar_fire;
  wire rd_capture;
  wire rd_release;
  wire rd_release_valid;

  wire wr_start;
  wire wr_aw_fire;
  wire wr_w_fire;
  wire wr_capture_b;
  wire wr_release_b;
  wire wr_release_valid;

  function [31:0] scale_cycles;
    input [31:0] cycles;
    reg   [63:0] scaled;
    reg   [63:0] shifted;
    begin
      scaled = (cycles * C) + (S - 1);
      shifted = scaled >> AMP_C;
      scale_cycles = shifted[31:0];
    end
  endfunction

  assign rd_start = !rd_active && in_arvalid;
  assign rd_ar_fire = out_arvalid && out_arready;
  assign rd_capture = out_rvalid && out_rready;

  assign wr_start = !wr_active && (in_awvalid || in_wvalid);
  assign wr_aw_fire = out_awvalid && out_awready;
  assign wr_w_fire = out_wvalid && out_wready;
  assign wr_capture_b = out_bvalid && out_bready;

  // 读事务从 ARVALID 开始计时；在同一笔事务完成前阻止新的 AR 进入。
  assign in_arready = (!rd_active || !rd_req_done) ? out_arready : 1'b0;
  assign out_arvalid = !rd_req_done ? in_arvalid : 1'b0;
  assign out_arid = in_arid;
  assign out_araddr = in_araddr;
  assign out_arlen = in_arlen;
  assign out_arsize = in_arsize;
  assign out_arburst = in_arburst;

  // 读返回面先缓存，再按每个 beat 的目标周期逐个放行。
  assign out_rready = rd_active && rd_req_done && (rd_buf_cnt != 4'd8);
  assign rd_release_valid = (rd_buf_cnt != 4'd0) && (rd_delay_cnt >= rd_buf_target[rd_rptr]);
  assign rd_release = rd_release_valid && in_rready;

  assign in_rvalid = rd_release_valid;
  assign in_rid = rd_release_valid ? rd_buf_id[rd_rptr] : 4'd0;
  assign in_rdata = rd_release_valid ? rd_buf_data[rd_rptr] : 32'd0;
  assign in_rresp = rd_release_valid ? rd_buf_resp[rd_rptr] : 2'd0;
  assign in_rlast = rd_release_valid ? rd_buf_last[rd_rptr] : 1'b0;

  // 写事务从 AWVALID/WVALID 更早出现的 valid 开始计时；AW/W 在同一笔事务结束前不接收下一笔。
  assign in_awready = (!wr_active || !wr_aw_done) ? out_awready : 1'b0;
  assign out_awvalid = !wr_aw_done ? in_awvalid : 1'b0;
  assign out_awid = in_awid;
  assign out_awaddr = in_awaddr;
  assign out_awlen = in_awlen;
  assign out_awsize = in_awsize;
  assign out_awburst = in_awburst;

  assign in_wready = (!wr_active || !wr_w_done) ? out_wready : 1'b0;
  assign out_wvalid = !wr_w_done ? in_wvalid : 1'b0;
  assign out_wdata = in_wdata;
  assign out_wstrb = in_wstrb;
  assign out_wlast = in_wlast;

  // 写返回面只缓存最终 B 响应，等写路径计数达到目标周期后再向上游放行。
  assign out_bready = wr_active && !wr_b_hold_valid;
  assign wr_release_valid = wr_b_hold_valid && (wr_delay_cnt >= wr_b_target);
  assign wr_release_b = wr_release_valid && in_bready;

  assign in_bvalid = wr_release_valid;
  assign in_bid = wr_release_valid ? wr_bid_r : 4'd0;
  assign in_bresp = wr_release_valid ? wr_bresp_r : 2'd0;

  always @(posedge clock) begin
    if (reset) begin
      rd_active <= 1'b0;
      rd_req_done <= 1'b0;
      rd_real_cnt <= 32'd0;
      rd_delay_cnt <= 32'd0;
      rd_buf_cnt <= 4'd0;
      rd_wptr <= 3'd0;
      rd_rptr <= 3'd0;

      wr_active <= 1'b0;
      wr_aw_done <= 1'b0;
      wr_w_done <= 1'b0;
      wr_real_cnt <= 32'd0;
      wr_delay_cnt <= 32'd0;
      wr_b_hold_valid <= 1'b0;
      wr_bid_r <= 4'd0;
      wr_bresp_r <= 2'd0;
      wr_b_target <= 32'd0;
    end
    else begin
      if (!rd_active) begin
        if (rd_start) begin
          rd_active <= 1'b1;
          rd_req_done <= 1'b0;
          rd_real_cnt <= 32'd1;
          rd_delay_cnt <= 32'd1;
          rd_buf_cnt <= 4'd0;
          rd_wptr <= 3'd0;
          rd_rptr <= 3'd0;
        end
      end
      else begin
        if (!rd_req_done && rd_ar_fire) begin
          rd_req_done <= 1'b1;
        end

        if (!rd_capture || !out_rlast) begin
          rd_real_cnt <= rd_real_cnt + 1'd1;
        end
        rd_delay_cnt <= rd_delay_cnt + 1'd1;

        if (rd_capture) begin
          rd_buf_id[rd_wptr] <= out_rid;
          rd_buf_data[rd_wptr] <= out_rdata;
          rd_buf_resp[rd_wptr] <= out_rresp;
          rd_buf_last[rd_wptr] <= out_rlast;
          rd_buf_target[rd_wptr] <= scale_cycles(rd_real_cnt);
          rd_wptr <= rd_wptr + 1'd1;
        end

        if (rd_release) begin
          if (rd_buf_last[rd_rptr]) begin
            rd_active <= 1'b0;
            rd_req_done <= 1'b0;
            rd_real_cnt <= 32'd0;
            rd_delay_cnt <= 32'd0;
            rd_buf_cnt <= 4'd0;
            rd_wptr <= 3'd0;
            rd_rptr <= 3'd0;
          end
          else begin
            rd_rptr <= rd_rptr + 1'd1;
          end
        end

        case ({rd_capture, rd_release})
          2'b10: rd_buf_cnt <= rd_buf_cnt + 1'd1;
          2'b01: rd_buf_cnt <= rd_buf_cnt - 1'd1;
          default: rd_buf_cnt <= rd_buf_cnt;
        endcase
      end

      if (!wr_active) begin
        if (wr_start) begin
          wr_active <= 1'b1;
          wr_aw_done <= 1'b0;
          wr_w_done <= 1'b0;
          wr_real_cnt <= 32'd1;
          wr_delay_cnt <= 32'd1;
          wr_b_hold_valid <= 1'b0;
          wr_bid_r <= 4'd0;
          wr_bresp_r <= 2'd0;
          wr_b_target <= 32'd0;
        end
      end
      else begin
        if (wr_aw_fire) begin
          wr_aw_done <= 1'b1;
        end
        if (wr_w_fire && in_wlast) begin
          wr_w_done <= 1'b1;
        end

        if (!wr_capture_b) begin
          wr_real_cnt <= wr_real_cnt + 1'd1;
        end
        wr_delay_cnt <= wr_delay_cnt + 1'd1;

        if (wr_capture_b) begin
          wr_b_hold_valid <= 1'b1;
          wr_bid_r <= out_bid;
          wr_bresp_r <= out_bresp;
          wr_b_target <= scale_cycles(wr_real_cnt);
        end

        if (wr_release_b) begin
          wr_active <= 1'b0;
          wr_aw_done <= 1'b0;
          wr_w_done <= 1'b0;
          wr_real_cnt <= 32'd0;
          wr_delay_cnt <= 32'd0;
          wr_b_hold_valid <= 1'b0;
          wr_bid_r <= 4'd0;
          wr_bresp_r <= 2'd0;
          wr_b_target <= 32'd0;
        end
      end
    end
  end

`else

  assign in_arready = out_arready;
  assign out_arvalid = in_arvalid;
  assign out_arid = in_arid;
  assign out_araddr = in_araddr;
  assign out_arlen = in_arlen;
  assign out_arsize = in_arsize;
  assign out_arburst = in_arburst;
  assign out_rready = in_rready;
  assign in_rvalid = out_rvalid;
  assign in_rid = out_rid;
  assign in_rdata = out_rdata;
  assign in_rresp = out_rresp;
  assign in_rlast = out_rlast;
  assign in_awready = out_awready;
  assign out_awvalid = in_awvalid;
  assign out_awid = in_awid;
  assign out_awaddr = in_awaddr;
  assign out_awlen = in_awlen;
  assign out_awsize = in_awsize;
  assign out_awburst = in_awburst;
  assign in_wready = out_wready;
  assign out_wvalid = in_wvalid;
  assign out_wdata = in_wdata;
  assign out_wstrb = in_wstrb;
  assign out_wlast = in_wlast;
  assign out_bready = in_bready;
  assign in_bvalid = out_bvalid;
  assign in_bid = out_bid;
  assign in_bresp = out_bresp;

`endif

endmodule
