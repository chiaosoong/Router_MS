/**********************************
* Router Flit Interface
**********************************/
interface router_flit_if;
  import noc_params::*;
  logic [DATA_WIDTH-1:0] flit_data;
  logic                  is_head, is_tail;
  logic                  valid, ready;
  logic                  credit_update;

  modport tx(
    input  credit_update,
    input  ready,
    output valid,
    output flit_data,
    output is_head,
    output is_tail
  );

  modport rx(
    input  flit_data,
    input  is_head,
    input  is_tail,
    input  valid,
    output ready,
    output credit_update
  );
endinterface
