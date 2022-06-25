// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Copyright@2022 Peking University
include 'ibex_pkg.sv';

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

  tag_t operand_a_tag;
  tag_t adder_result_tag;

  logic oprand_a_tag_err;
  logic result_underflow;
  logic result_overflow;

  assign operand_a_tag      =      operand_a_i[XLEN-1  : XLEN - TagWidth];
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

  assign region_start_index = {operand_a_tag[BCPNumRegions_BIT - 1 : 1], 1'b0};
  assign region_end_index   = {operand_a_tag[BCPNumRegions_BIT - 1 : 1], 1'b1};
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