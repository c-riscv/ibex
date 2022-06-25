// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Copyright@2022 Peking University

module ibex_bcp #(
  parameter XLEN = 32,
  // Number of implemented regions, must be 2*N and larger than 2
  parameter int unsigned BCPNumRegions  = 4
) (
  // Interface to CSRs
  input  ibex_pkg::bcp_cfg_t      csr_bcp_cfg_i     [BCPNumRegions],
  input  logic [31:0]             csr_bcp_addr_i    [BCPNumRegions],
  input  ibex_pkg::bcp_mseccfg_t  csr_bcp_mseccfg_i,

  input  ibex_pkg::alu_op_e operator_i,
  input  logic [31:0]       operand_a_i,
  input  logic [31:0]       operand_b_i,

  // signals to/from ID/EX stage
  input  logic [1:0]   lsu_type_i,           // data type: word, half word, byte -> from ID/EX
  input  logic         lsu_req_i,            // data request

  input  logic [31:0]  adder_result_ex_i,    // address computed in ALU 

  // Bound checking Signals
  output logic                    bcp_load_addr_err_o,
  output logic                    bcp_arith_addr_err_o,
  output logic                    bcp_store_addr_err_o
);

  import ibex_pkg::*;

  localparam   ALEN              = (XLEN / 4) *3;
  localparam   TagWidth          = XLEN - ALEN;
  localparam   BCPNumRegions_BIT = $clog2(BCPNumRegions);

  typedef logic [XLEN-1 :0]      xlen_t;
  typedef logic [TagWidth-1 : 0] tag_t;
  typedef logic [ALEN-1 : 0]     addr_t;

  tag_t oprand_a_tag;
  tag_t adder_result_tag;

  logic oprand_a_tag_err;
  logic result_underflow;
  logic result_overflow;

  assign oprand_a_tag      =        oprand_a_i[XLEN-1  : XLEN - TagWidth];
  assign adder_result_tag  = adder_result_ex_i[XLEN-1  : XLEN - TagWidth];
  assign adder_result_addr = adder_result_ex_i[ALEN -1 :               0];  
  
  //
  // Region Bound Checking
  // 
  xlen_t region_start_entry;
  xlen_t region_end_entry;

  addr_t region_start_addr;
  addr_t region_end_addr;

  logic [BCPNumRegions_BIT -1 : 0] region_index;  

  assign region_start_index = {oprand_a_tag[BCPNumRegions_BIT - 1 : 1], 1'b0};
  assign region_end_index   = {oprand_a_tag[BCPNumRegions_BIT - 1 : 1], 1'b1}
  assign region_start = BCPNumRegions[region_start_index];
  assign region_end   = BCPNumRegions[region_end_index];

  // 1. oprand_a_i.tag == 8'h00 or 8'hff
  // 2. oprand_a.i.tag != adder_result_ex_i.tag

  // INCP DECP INCPI LOAD STORE AMO
  // 3.1 oprand_a_i.base  >  adder_result_ex_i.address
  // 3.2 oprand_a_i.bound <= adder_result_ex_i.address + size

  // CVT.I.P
  // 4.1 oprand_a_i.base  >  oprand_b_i.address
  // 4.2 oprand_a_i.bound <= oprand_b_i.address

  // CVT.P.I SUBP SLTUP
  // don't checking

  // SETAG SETAGI
  // 5.1 oprand_a.i.base  > oprand_b_i.new_tag.base
  // 5.2 oprand_a.i.bound < oprand_b_i.new_tag.bound

endmodule

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
  output logic        tag_err
  );

  logic [4:0]  tag_e;
  logic [1:0]  tag_l;
  logic        tag_h;

  logic        e_ge24, e_ge23, e_ge22, e_lt22;
  logic [4:0]  e_amend;
  logic [2:0]  length;
  logic [3:0]  lb, ub, e_base;
  logic [24:0] e_mask, e_mask_n, lowerbound, upperbound;

  assign tag_e = {tag[7:6], tag[2:0]};
  assign tag_h = tag[3];
  assign tag_l = tag[5:4];

  assign e_ge24 = (tag_e[4:3] == 2'b11);
  assign e_eq23 = (tag_e == 5'd23);
  assign e_eq22 = (tag_e == 5'd22);
  assign e_lt22 = !e_ge24 & !e_eq23 & !e_eq22;
    
  assign tag_err =  tag == 8'd0 
                  |  e_ge24 | e_eq23 
                  | (e_eq22 & L == 0 & !H ) 
                  | (e_eq22 & L == 1 & H == 0 )
                  | (e_eq22 & L == 3 & H == 0 )
                  | (e_lt22 & L == 0 & H == 0 );

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
  assign upperbound = ({{21'd0}, up} << e_amend) -1;

  assign elh_tolerant_start_addr = address & ~e_mask_n[23:0];
  assign elh_tolerant_end_addr = elh_tolerant_start_addr | e_mask[23:0];

  assign elh_alloc_start_addr = elh_tolerant_start_addr | lowerbound[23:0];
  assign elh_alloc_end_addr   = elh_tolerant_start_addr | upperbound[23:0];

endmodule
