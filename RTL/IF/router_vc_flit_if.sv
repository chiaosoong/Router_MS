/**********************************
* Router VC Flit Interface
**********************************/
interface router_vc_flit_if;
  import noc_params::*;

  logic [DATA_WIDTH-1:0] flit_data;
  logic                  is_head;
  logic                  is_tail;
  logic [VC_PRT_SIZE-1:0] vc_id;
  logic                  valid;
  logic                  ready;
  logic [VC_PER_PORT-1:0] credit_return;

  modport tx(
    input  ready,
    input  credit_return,
    output valid,
    output flit_data,
    output is_head,
    output is_tail,
    output vc_id
  );

  modport rx(
    input  flit_data,
    input  is_head,
    input  is_tail,
    input  vc_id,
    input  valid,
    output ready,
    output credit_return
  );
endinterface
