// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Copyright 2022 Peking University

module ibex_bcp #(
  parameter XLEN = 32,
  // Number of implemented regions, must be 2*N and larger than 4
  parameter int unsigned BCPNumRegions  = 4
  ) (
  // Interface to CSRs
//input  ibex_pkg::bcp_cfg_t     csr_bcp_cfg_i     [BCPNumRegions],
  input  logic [31:0]            csr_bcp_addr_i    [BCPNumRegions],
//input  ibex_pkg::bcp_mseccfg_t csr_bcp_mseccfg_i,

  input  ibex_pkg::alu_op_e      operator_i,
  input  logic [31:0]            operand_a_i,
  input  logic [31:0]            operand_b_i,

  // signals to/from ID/EX stage
  input  logic [1:0]             data_type_i,      // data type: word, half word, byte -> from ID/EX
  input  logic                   data_req_i,       // data request, LOAD/STORE/AMO
  input  logic                   data_we_i,        // write enable

  input  logic [31:0]            adder_result_ex_i,// address computed in ALU 

  // Bound checking signals
  output logic                    bcp_load_addr_err_o,
  output logic                    bcp_arith_addr_err_o,
  output logic                    bcp_store_addr_err_o
  );

  import ibex_pkg::*;

  localparam   ALEN              = (XLEN / 4) *3;
  localparam   TagWidth          = XLEN - ALEN;
  localparam   BCPNumRegions_BIT = $clog2(BCPNumRegions);

  typedef logic [XLEN-1 :0]              xlen_t;
  typedef logic [TagWidth-1 : 0]         tag_t;
  typedef logic [ALEN-1 : 0]             addr_t;
  typedef logic [BCPNumRegions_BIT-1 :0] index_t;

  tag_t ain_tag;
  tag_t new_tag;
  tag_t result_tag;

  addr_t ain_addr;
  addr_t result_addr;

  logic ain_tag_region;
  logic new_tag_region;
  
  xlen_t ain_region_start_entry;
  xlen_t ain_region_end_entry;
  xlen_t new_region_start_entry;
  xlen_t new_region_end_entry;

  index_t ain_region_start_index;
  index_t ain_region_end_index;
  index_t new_region_start_index;
  index_t new_region_end_index;
    
  tag_t ain_region_start_tag;
  tag_t ain_region_end_tag;
  tag_t new_region_start_tag;
  tag_t new_region_end_tag;
  
  addr_t ain_region_start_addr;
  addr_t ain_region_end_addr;
  addr_t new_region_start_addr;
  addr_t new_region_end_addr;

  logic ain_tag_err;
  logic new_tag_err;
  
  addr_t ain_elh_alloc_start;
  addr_t ain_elh_alloc_end;
  addr_t ain_elh_tolerant_start;
  addr_t ain_elh_tolerant_end;
 
  logic ain_elh_tag_err;
  
  addr_t new_elh_alloc_start;
  addr_t new_elh_alloc_end;
  addr_t new_elh_tolerant_start;
  addr_t new_elh_tolerant_end;
  
  logic new_elh_tag_err;
  
  logic bound_sel_arith;
  logic bound_sel_access;
  logic bound_sel_setag;
  
  addr_t result_addr_lastbyte;
  
  addr_t cmp_lb_in;
  addr_t cmp_ub_in;
  addr_t cmp_lowerbound;
  addr_t cmp_upperbound;
  
  logic cmp_underflow;
  logic cmp_overflow;

  logic result_tag_err;
  logic cmp_err;

  assign ain_tag     = operand_a_i      [XLEN -1 : XLEN - TagWidth];
  assign result_tag  = adder_result_ex_i[XLEN -1 : XLEN - TagWidth];

  assign new_tag     = operand_b_i      [TagWidth-1 : 0];
  
  assign ain_addr    = operand_a_i      [ALEN -1 : 0];  
  assign result_addr = adder_result_ex_i[ALEN -1 : 0];  
  
  assign ain_tag_region = ain_tag[7:6] == 2'b11;
  assign new_tag_region = new_tag[7:6] == 2'b11;

  //
  // Region Bound Checking Reparement
  // 

  assign ain_region_start_index = {ain_tag[BCPNumRegions_BIT - 1 : 1], 1'b0};
  assign ain_region_end_index   = {ain_tag[BCPNumRegions_BIT - 1 : 1], 1'b1};
  assign ain_region_start_entry = BCPNumRegions[ain_region_start_index];
  assign ain_region_end_entry   = BCPNumRegions[ain_region_end_index];
  assign ain_region_start_tag   = ain_region_start_entry[XLEN -1 : XLEN - TagWidth];
  assign ain_region_end_tag     = ain_region_end_entry  [XLEN -1 : XLEN - TagWidth];
  assign ain_region_start_addr  = ain_region_start_entry[ALEN -1 : 0];
  assign ain_region_end_addr    = ain_region_end_entry  [ALEN -1 : 0];
    
  assign ain_region_err = ain_tag_region &&
                       ( (ain_region_start_addr > ain_region_end_addr)
                       | (ain_region_start_tag != ain_region_end_tag)
                       | (ain_tag == 8'hff)
                       );

  assign new_region_start_index = {new_tag[BCPNumRegions_BIT - 1 : 1], 1'b0};
  assign new_region_end_index   = {new_tag[BCPNumRegions_BIT - 1 : 1], 1'b1};
  assign new_region_start_entry = BCPNumRegions[new_region_start_index];
  assign new_region_end_entry   = BCPNumRegions[new_region_end_index];
  assign new_region_start_tag   = new_region_start_entry[XLEN -1 : XLEN - TagWidth];
  assign new_region_end_tag     = new_region_end_entry  [XLEN -1 : XLEN - TagWidth];
  assign new_region_start_addr  = new_region_start_entry[ALEN -1 : 0];
  assign new_region_end_addr    = new_region_end_entry  [ALEN -1 : 0];
    
  assign new_region_err = new_tag_region &&
                       ( (new_region_start_addr > new_region_end_addr)
                       | (new_region_start_tag != new_region_end_tag)
                       | (new_tag == 8'hff)
                       );

  // All RV32T extension exclude SUBP and SLTUP
  elh_tag_bound u_oprand_a_bound(
    .tag(ain_tag),
    .address(ain_address),
    .elh_alloc_start_addr(ain_elh_alloc_start),
    .elh_alloc_end_addr(ain_elh_alloc_end),
    .elh_tolerant_start_addr(ain_elh_tolerant_start),
    .elh_tolerant_end_addr(ain_elh_tolerant_end),
    .elh_tag_err(ain_elh_tag_err)
  );

  // SETAG and SETAGI
  elh_tag_bound u_oprand_b_bound(
    .tag(new_tag),
    .address(ain_address),
    .elh_alloc_start_addr(new_elh_alloc_start),
    .elh_alloc_end_addr(new_elh_alloc_end),
    .elh_tolerant_start_addr(new_elh_tolerant_start),
    .elh_tolerant_end_addr(new_elh_tolerant_end),
    .elh_tag_err(new_elh_tag_err)
  );
  
  assign ain_tag_err = ain_tag_region ? ain_region_err : ain_elh_tag_err;
  assign new_tag_err = new_tag_region ? new_region_err : new_elh_tag_err;
  
  always_comb begin
    bound_sel_arith  = 1'b0;
    bound_sel_access = data_req_i;
    bound_sel_setag  = 1;b0;
    
    unique case (operator_i)
      // Adder OPs
      ALU_INCP, 
      ALU_DECP,
      ALU_CVTIP : bound_sel_arith  = 1'b1;

      ALU_SETAG : bound_sel_setag  = 1'b1;
      // load/store/amo
      default   : ;
    endcase
  end

  // prepare lowerbound
  always_comb begin
    unique case (1'b1)
      bound_sel_access :  cmp_lowerbound = ain_tag_region ? ain_region_start_addr : ain_elh_alloc_start;
      bound_sel_setag,  
      bound_sel_arith  :  cmp_lowerbound = ain_tag_region ? ain_region_start_addr : ain_elh_tolerant_start;
      default: cmp_upperbound = 24'b0;
    endcase
  end

  // prepare upperbound
  always_comb begin
    unique case (1'b1)
      bound_sel_access:  cmp_upperbound = ain_tag_region ? ain_region_end_addr : ain_elh_alloc_end;
      bound_sel_arith,
      bound_sel_setag:   cmp_upperbound = ain_tag_region ? ain_region_end_addr : ain_elh_tolerant_end;
      default: cmp_upperbound = 24'd0
    endcase
  end
  
  always_comb begin
    unique case (data_type_i)
      2'b00:   result_addr_lastbyte = result_addr;
      2'b01:   result_addr_lastbyte = {result_addr[23:1], 1'b1};
      2'b10:   result_addr_lastbyte = {result_addr[23:2], 2'b11};
      default: result_addr_lastbyte = result_addr;
    endcase
  end
  
  assign cmp_lb_in = ( operator_i == ALU_SETAG ) ? new_region_start_addr : 
                                  ( data_req_i ) ? result_addr_lastbyte : result_addr;
  assign cmp_ub_in = ( operator_i == ALU_SETAG ) ? new_region_end_addr   : 
                                  ( data_req_i ) ? result_addr_lastbyte : result_addr;
  
  // 1. a_tag is 8'h00 or 8'hff
  // 2. a_tag != result tag
  //
  // INCP DECP INCPI CVT.I.P
  // 3.1 result_addr < a_start_tolerant
  // 3.2 result_addr > a_end_tolerant
  //
  // LOAD STORE AMO
  // 4.1 result_addr < a_start_alloc
  // 5.2 result_addr + size -1 > a_end_alloc
  //
  // SETAG SETAGI fault
  // 5.1 new_start_tolerant < a_start_tolerant
  // 5.2 new_end_tolerant   > a_end_tolerant

  // comparors
  assign cmp_underflow  = cmp_lb_in < cmp_lowerbound;
  assign cmp_overflow   = cmp_ub_in > cmp_upperbound;

  // output signals
  assign result_tag_err = ain_tag != result_tag;

  assign cmp_err      = cmp_underflow | cmp_overflow | ain_tag_err;

  // store
  assign bcp_store_addr_err_o = bound_sel_access & data_we_i 
                            &  (cmp_err | result_tag_err);
  // load
  assign bcp_load_addr_err_o  = bound_sel_access & ~data_we_i 
                            &  (cmp_err | result_tag_err);
  
  // incp, decp, incpi, cvt.i.p, setag, setagi
  assign bcp_arith_addr_err_o = (bound_sel_arith & (cmp_err | result_tag_err))
                              | (bound_sel_setag & (cmp_err | new_tag_err));

endmodule