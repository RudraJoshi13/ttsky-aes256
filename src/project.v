/*
 * Copyright (c) 2026 Rudra Joshi
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper around the secworks AES core
 * (https://github.com/secworks/aes, BSD-2-Clause, Joachim Strombergson),
 * used unmodified. AES-128 and AES-256, encrypt and decrypt.
 *
 * Byte-wide register interface:
 *   ui_in[4:0]  word index (see table below)
 *   ui_in[6:5]  byte within the word (0 = bits 7:0, 3 = bits 31:24)
 *   ui_in[7]    write strobe (active high, synchronised inside)
 *   uio_in[7:0] write data byte
 *   uo_out[7:0] read data byte of the selected word and byte
 *
 * A word is written to the core when byte 3 is written; bytes 0-2 are
 * held in a staging register until then, so write bytes 0, 1, 2, then 3.
 *
 * Word index -> secworks register
 *   0 NAME0   1 NAME1   2 VERSION
 *   3 CTRL    (bit0 init, bit1 next)
 *   4 STATUS  (bit0 ready, bit1 valid)
 *   5 CONFIG  (bit0 encdec: 1 = encrypt, bit1 keylen: 1 = 256-bit)
 *   8..15  KEY0..KEY7    (KEY0 = most significant word)
 *   16..19 BLOCK0..BLOCK3 (BLOCK0 = most significant word)
 *   20..23 RESULT0..RESULT3 (RESULT0 = most significant word)
 *   others unused (read 0, writes ignored)
 */

`default_nettype none

module tt_um_rj_aes (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire [4:0] word_sel = ui_in[4:0];
  wire [1:0] byte_sel = ui_in[6:5];

  // ------------------------------------------------------------
  // Write strobe: two-flop synchroniser plus rising-edge detect.
  // Address and data must be stable before the strobe rises and
  // held until it falls.
  // ------------------------------------------------------------
  reg [2:0] strobe_sync;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      strobe_sync <= 3'b000;
    else
      strobe_sync <= {strobe_sync[1:0], ui_in[7]};
  end
  wire wr_pulse = strobe_sync[1] & ~strobe_sync[2];

  // ------------------------------------------------------------
  // Word index to secworks register address.
  // ------------------------------------------------------------
  reg [7:0] core_addr;
  always @(*) begin
    case (word_sel)
      5'd0:  core_addr = 8'h00;  // NAME0
      5'd1:  core_addr = 8'h01;  // NAME1
      5'd2:  core_addr = 8'h02;  // VERSION
      5'd3:  core_addr = 8'h08;  // CTRL
      5'd4:  core_addr = 8'h09;  // STATUS
      5'd5:  core_addr = 8'h0a;  // CONFIG
      5'd8,  5'd9,  5'd10, 5'd11,
      5'd12, 5'd13, 5'd14, 5'd15:
             core_addr = {5'b00010, word_sel[2:0]};  // KEY0..KEY7
      5'd16, 5'd17, 5'd18, 5'd19:
             core_addr = {6'b001000, word_sel[1:0]}; // BLOCK0..BLOCK3
      5'd20, 5'd21, 5'd22, 5'd23:
             core_addr = {6'b001100, word_sel[1:0]}; // RESULT0..RESULT3
      default: core_addr = 8'hff;                    // unused
    endcase
  end

  // ------------------------------------------------------------
  // Staging register for bytes 0-2; byte 3 commits the word.
  // ------------------------------------------------------------
  reg [23:0] hold;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      hold <= 24'h0;
    else if (wr_pulse) begin
      case (byte_sel)
        2'd0: hold[7:0]   <= uio_in;
        2'd1: hold[15:8]  <= uio_in;
        2'd2: hold[23:16] <= uio_in;
        default: ;
      endcase
    end
  end

  wire        core_we    = wr_pulse & (byte_sel == 2'd3);
  wire [31:0] core_wdata = {uio_in, hold};
  wire [31:0] core_rdata;

  aes core (
      .clk       (clk),
      .reset_n   (rst_n),
      .cs        (1'b1),
      .we        (core_we),
      .address   (core_addr),
      .write_data(core_wdata),
      .read_data (core_rdata)
  );

  // ------------------------------------------------------------
  // Registered read byte.
  // ------------------------------------------------------------
  reg [7:0] rdata_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rdata_q <= 8'h00;
    else if (!core_we) begin
      case (byte_sel)
        2'd0: rdata_q <= core_rdata[7:0];
        2'd1: rdata_q <= core_rdata[15:8];
        2'd2: rdata_q <= core_rdata[23:16];
        2'd3: rdata_q <= core_rdata[31:24];
      endcase
    end
  end

  assign uo_out  = rdata_q;
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h00;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

endmodule
