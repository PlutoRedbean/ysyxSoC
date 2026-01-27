module sdram32 (
  input         clk,
  input         cke,
  input         cs,
  input         ras,
  input         cas,
  input         we,
  input  [12:0] a,
  input  [1:0]  ba,
  input  [3:0]  dqm,
  inout  [31:0] dq
);

  localparam CMD_READ  = 4'b0101;
  localparam CMD_WRITE = 4'b0100;

  wire [3:0] cmd;

  assign cmd = { cs, ras, cas, we };

  sdram sdram_low (
    .clk(clk),
    .cke(cke),
    .cs(cs),
    .ras(ras),
    .cas(cas),
    .we(we),
    .a(a),
    .ba(ba),
    .dqm(dqm[1:0]),
    .dq(dq[15:0])
  );

  sdram sdram_high (
    .clk(clk),
    .cke(cke),
    .cs(cs),
    .ras(ras),
    .cas(cas),
    .we(we),
    .a(cmd == CMD_READ || cmd == CMD_WRITE ? a + 1 : a),
    .ba(ba),
    .dqm(dqm[3:2]),
    .dq(dq[31:16])
  );

endmodule
