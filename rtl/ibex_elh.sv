// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Copyright Peking University

/////////////////////////
// ELH Bounds Generation
/////////////////////////
// 
// ELH Tag Format
//
//    7    6    5    4    3    2    1    0
// +----+----+----+----+----+----+----+----+
// | e4 | e3 | l1 | l0 | h  | e2 | e1 | e0 |
// +----+----+----+----+----+----+----+----+
// 
// ELH Encoding
//
// each block size : 2 ^ e_amend
// 
// 1. L = 0, H = 1
// +---+
// | * | 
// +---+
// ^   ^ alloc_end / tolerant_end
// | alloc_start / tolerant_start
// 2. L = 1, H = 0
// +---+---+---+---+
// | * | * | * |   | 
// +---+---+---+---+
// ^           ^   ^ torlerant_end
// |           | alloc_end
// | alloc_start / tolerant_start
// 3. L = 1, H = 1
// +---+---+---+---+
// |   | * | * | * | 
// +---+---+---+---+
// ^   ^           ^ alloc_end / torlerant_end
// |   | alloc_start
// | tolerant_start 
//
// e = 22, L != 2
// 1. L = 0, e_amend = 22, length = 1, H != 0
// 2. L = 1, e_amend = 23, length = 1, H != 0
// 4. L = 3, e_amend = 24, length = 1, H != 0
//
// e = 22 and L = 2
//                   alloc_start alloc_end tolerant_start tolerant_end
// 2. L = 2, H = 0        0             3           0          4
// 3. L = 2, H = 1        1             4           0          4
//
// e < 22
//                   alloc_start alloc_end tolerant_start tolerant_end
// 1. L = 0, H = 1        0             1           0          1
// 2. L = 1, H = 0        0             3           0          4
// 3. L = 1, H = 1        1             4           0          4
// 4. L = 2, H = 0        0             5           0          8
// 5. L = 2, H = 1        3             8           0          8
// 6. L = 3, H = 0        0             7           0          8
// 7. L = 3, H = 1        1             8           0          8
//

module elh_tag_bound(
  input  logic [7:0]  tag,
  input  logic [23:0] address,
  output logic [23:0] elh_alloc_start_addr,
  output logic [23:0] elh_alloc_end_addr,
  output logic [23:0] elh_tolerant_start_addr,
  output logic [23:0] elh_tolerant_end_addr,
  output logic        elh_tag_err
  );

  logic [4:0]  tag_e;
  logic [1:0]  tag_l;
  logic        tag_h;

  logic        e_ge24, e_eq23, e_eq22, e_lt22;
  logic [4:0]  e_amend;
  logic [2:0]  length;
  logic [3:0]  lb, ub, e_base;
  logic [24:0] e_mask, lowerbound, upperbound;

  assign tag_e = {tag[7:6], tag[2:0]};
  assign tag_h = tag[3];
  assign tag_l = tag[5:4];

  assign e_ge24 = (tag_e[4:3] == 2'b11);
  assign e_eq23 = (tag_e == 5'd23);
  assign e_eq22 = (tag_e == 5'd22);
  assign e_lt22 = !e_ge24 & !e_eq23 & !e_eq22;
    
  assign elh_tag_err =  (tag == 8'h00)
                  |  e_ge24 | e_eq23 
                  | (e_eq22 & tag_l == 0 & tag_h == 0 ) 
                  | (e_eq22 & tag_l == 1 & tag_h == 0 )
                  | (e_eq22 & tag_l == 3 & tag_h == 0 )
                  | (e_lt22 & tag_l == 0 & tag_h == 0 );

  always_comb
    begin
      case ({e_eq22, e_lt22, tag_l, tag_h})
        // E == 22
      8'b1_0_00_1: {e_amend, length, lb, ub, e_base} = {5'd22, 3'd1, 4'd0, 4'd1, 4'd1}; // 2^22 * 1; base:limit 0:1
      8'b1_0_01_1: {e_amend, length, lb, ub, e_base} = {5'd23, 3'd1, 4'd0, 4'd1, 4'd1}; // 2^22 * 2; base limit 0:1
      8'b1_0_10_0: {e_amend, length, lb, ub, e_base} = {5'd22, 3'd3, 4'd1, 4'd4, 4'd4}; // 2^22 * 3; base limit 1:4
      8'b1_0_10_1: {e_amend, length, lb, ub, e_base} = {5'd22, 3'd3, 4'd0, 4'd3, 4'd4}; // 2^22 * 3; base limit 0:3
      8'b1_0_11_1: {e_amend, length, lb, ub, e_base} = {5'd24, 3'd1, 4'd0, 4'd1, 4'd1}; // 2^22 * 4; base:limit 0:1
      // E < 22
      8'b0_1_00_1: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd1, 4'd0, 4'd1, 4'd1}; // 2^E  * 1; base:limit 0:1
      8'b0_1_01_0: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd3, 4'd1, 4'd4, 4'd4}; // 2^E  * 1; base:limit 1:4
      8'b0_1_01_1: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd3, 4'd0, 4'd3, 4'd4}; // 2^E  * 1; base:limit 0:3
      8'b0_1_10_0: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd5, 4'd3, 4'd8, 4'd8}; // 2^E  * 1; base:limit 3:8
      8'b0_1_10_1: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd5, 4'd0, 4'd5, 4'd8}; // 2^E  * 1; base:limit 0:5
      8'b0_1_11_0: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd7, 4'd1, 4'd8, 4'd8}; // 2^E  * 1; base:limit 1:8
      8'b0_1_11_1: {e_amend, length, lb, ub, e_base} = {tag_e, 3'd7, 4'd0, 4'd7, 4'd8}; // 2^E  * 1; base:limit 0:7
      default:;
      endcase
    end

  assign e_mask   = ({{21'd0}, e_base} << e_amend) -1;

  assign lowerbound =  {{21'd0}, lb} << e_amend;
  assign upperbound = ({{21'd0}, ub} << e_amend) -1;

  assign elh_tolerant_start_addr = address & ~e_mask[23:0];
  assign elh_tolerant_end_addr = elh_tolerant_start_addr | e_mask[23:0];

  assign elh_alloc_start_addr = elh_tolerant_start_addr | lowerbound[23:0];
  assign elh_alloc_end_addr   = elh_tolerant_start_addr | upperbound[23:0];

endmodule
