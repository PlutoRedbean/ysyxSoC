`timescale 1ns / 10ps

// Refer to the data sheet for the flash instructions at
// https://www.winbond.com/hq/product/code-storage-flash-memory/serial-nor-flash/?__locale=zh

module flash (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
  wire reset = ss;

  localparam cmd_t  = 3'd0;
  localparam addr_t = 3'd1;
  localparam data_t = 3'd2;
  localparam err_t  = 3'd3;
  // typedef enum [2:0] { cmd_t, addr_t, data_t, err_t } state_t;
  reg [2:0]  state;
  reg [7:0]  counter;
  reg [7:0]  cmd;
  reg [23:0] addr;
  reg [31:0] data;

  wire ren = (state == addr_t) && (counter == 8'd23);
  wire [31:0] rdata;
  wire [31:0] raddr = {8'h30, addr[22:0], mosi};
  flash_cmd flash_cmd_i(
    .clock(sck),
    .valid(ren),
    .cmd(cmd),
    .addr(raddr),
    .data(rdata)
  );

  always@(posedge sck or posedge reset) begin
    if (reset) state <= cmd_t;
    else begin
      case (state)
        cmd_t:  state <= (counter == 8'd7 ) ? addr_t : state;
        addr_t: state <= (cmd     != 8'h3 ) ? err_t  :
                         (counter == 8'd23) ? data_t : state;
        data_t: state <= state;

        default: begin
          state <= state;
          $fwrite(32'h80000002, "Assertion failed: Unsupported command `%xh`, only support `03h` read command\n", cmd);
          $fatal;
        end
      endcase
    end
  end

  always@(posedge sck or posedge reset) begin
    if (reset) counter <= 8'd0;
    else begin
      case (state)
        cmd_t:   counter <= (counter < 8'd7 ) ? counter + 8'd1 : 8'd0;
        addr_t:  counter <= (counter < 8'd23) ? counter + 8'd1 : 8'd0;
        default: counter <= counter + 8'd1;
      endcase
    end
  end

  always@(posedge sck or posedge reset) begin
    if (reset)               cmd <= 8'd0;
    else if (state == cmd_t) cmd <= { cmd[6:0], mosi };
  end

  always@(posedge sck or posedge reset) begin
    if (reset) addr <= 24'd0;
    else if (state == addr_t && counter < 8'd23)
      addr <= { addr[22:0], mosi };
  end

  wire [31:0] data_bswap = {rdata[7:0], rdata[15:8], rdata[23:16], rdata[31:24]};
  wire [31:0] tmp0;
  assign tmp0 = {counter == 8'd0 ? data_bswap : data};
  always@(posedge sck or posedge reset) begin
    if (reset) data <= 32'd0;
    else if (state == data_t) begin
      data <= { tmp0[30:0], 1'b0 };
    end
  end

  wire [31:0] tmp1;
  assign tmp1 = {counter == 8'd0 ? data_bswap : data};
  assign miso = ss ? 1'b1 : tmp1[31];

endmodule

`ifdef ysyx_25050158_SIMULATION

import "DPI-C" function void flash_read(input int addr, output int data);

module flash_cmd(
  input             clock,
  input             valid,
  input       [7:0] cmd,
  input      [31:0] addr,
  output reg [31:0] data
);
  always@(posedge clock) begin
    if (valid)
      if (cmd == 8'h03) flash_read(addr, data);
      else begin
        $fwrite(32'h80000002, "Assertion failed: Unsupport command `%xh`, only support `03h` read command\n", cmd);
        $fatal;
      end
  end
endmodule

`else

module flash_cmd(
  input             clock,
  input             valid,
  input       [7:0] cmd,
  input      [31:0] addr,
  output reg [31:0] data
);

  reg [7:0] flash [0 : (16 * 1024 * 1024) - 1];

  initial begin
    $readmemh("~/ysyx-workbench/rt-thread-am/bsp/abstract-machine/build/iverilog.hex", flash);
  end

  always@(posedge clock) begin
    if (valid)
      if (cmd == 8'h03) data <= {flash[{8'h00, addr[29:0]}        ],
                                 flash[{8'h00, addr[29:0]} + 32'd1],
                                 flash[{8'h00, addr[29:0]} + 32'd2],
                                 flash[{8'h00, addr[29:0]} + 32'd3]};
      else begin
        $fwrite(32'h80000002, "Assertion failed: Unsupport command `%xh`, only support `03h` read command\n", cmd);
        $fatal;
      end
  end
endmodule

`endif
