/**********************************
* 3x3 Mesh Top
* - Instantiates 9 routers (TOP)
* - Connects directional links: EAST/WEST and NORTH/SOUTH
* - Exposes each router LOCAL port to external PE interfaces
*
* Router index mapping (flat):
*   rid = y * 3 + x
*   y=0: rid 0,1,2
*   y=1: rid 3,4,5
*   y=2: rid 6,7,8
**********************************/
module MESH_3x3_TOP
import noc_params::*;
(
  input  logic CLK,
  input  logic RSTn,

  // PE -> Mesh injection (connect to each router LOCAL input side)
  router_vc_flit_if.rx PE_IFLIT [8:0],
  // Mesh -> PE ejection (connect to each router LOCAL output side)
  router_vc_flit_if.tx PE_OFLIT [8:0]
);

  localparam int MESH_X = 3;
  localparam int MESH_Y = 3;
  localparam int ROUTER_NUM = MESH_X * MESH_Y;

  // Per-router interfaces toward internal links and LOCAL bridge.
  router_vc_flit_if R_IFLIT [ROUTER_NUM][PORT_NUM]();
  router_vc_flit_if R_OFLIT [ROUTER_NUM][PORT_NUM]();

  function automatic POS pos_from_int(input int v);
    case (v)
      0:       pos_from_int = P0;
      1:       pos_from_int = P1;
      default: pos_from_int = P2;
    endcase
  endfunction

  // --------------------------------------------------------------------------
  // Router instantiation
  // --------------------------------------------------------------------------
  genvar gy, gx;
  generate
    for (gy = 0; gy < MESH_Y; gy++) begin : GEN_Y
      for (gx = 0; gx < MESH_X; gx++) begin : GEN_X
        localparam int RID = (gy * MESH_X) + gx;
        localparam POS THISX_P = pos_from_int(gx);
        localparam POS THISY_P = pos_from_int(gy);

        TOP #(
          .THISX(THISX_P),
          .THISY(THISY_P)
        ) u_router (
          .CLK  (CLK),
          .RSTn (RSTn),
          .OFLIT(R_OFLIT[RID]),
          .IFLIT(R_IFLIT[RID])
        );
      end
    end
  endgenerate

  // --------------------------------------------------------------------------
  // LOCAL port bridge: connect each router LOCAL to external PE interface
  // --------------------------------------------------------------------------
  genvar r;
  generate
    for (r = 0; r < ROUTER_NUM; r++) begin : GEN_LOCAL_BRIDGE
      // PE -> Router(LOCAL input)
      assign R_IFLIT[r][LOCAL].valid     = PE_IFLIT[r].valid;
      assign R_IFLIT[r][LOCAL].flit_data = PE_IFLIT[r].flit_data;
      assign R_IFLIT[r][LOCAL].is_head   = PE_IFLIT[r].is_head;
      assign R_IFLIT[r][LOCAL].is_tail   = PE_IFLIT[r].is_tail;
      assign R_IFLIT[r][LOCAL].vc_id     = PE_IFLIT[r].vc_id;
      assign PE_IFLIT[r].ready           = R_IFLIT[r][LOCAL].ready;
      assign PE_IFLIT[r].credit_return   = R_IFLIT[r][LOCAL].credit_return;

      // Router(LOCAL output) -> PE
      assign PE_OFLIT[r].valid           = R_OFLIT[r][LOCAL].valid;
      assign PE_OFLIT[r].flit_data       = R_OFLIT[r][LOCAL].flit_data;
      assign PE_OFLIT[r].is_head         = R_OFLIT[r][LOCAL].is_head;
      assign PE_OFLIT[r].is_tail         = R_OFLIT[r][LOCAL].is_tail;
      assign PE_OFLIT[r].vc_id           = R_OFLIT[r][LOCAL].vc_id;
      assign R_OFLIT[r][LOCAL].ready     = PE_OFLIT[r].ready;
      assign R_OFLIT[r][LOCAL].credit_return = PE_OFLIT[r].credit_return;
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Horizontal links (EAST/WEST), bidirectional
  // --------------------------------------------------------------------------
  generate
    for (gy = 0; gy < MESH_Y; gy++) begin : GEN_HLINK_Y
      for (gx = 0; gx < MESH_X-1; gx++) begin : GEN_HLINK_X
        localparam int RA = (gy * MESH_X) + gx;       // left router
        localparam int RB = (gy * MESH_X) + (gx + 1); // right router

        // RA.EAST -> RB.WEST
        assign R_IFLIT[RB][WEST].valid     = R_OFLIT[RA][EAST].valid;
        assign R_IFLIT[RB][WEST].flit_data = R_OFLIT[RA][EAST].flit_data;
        assign R_IFLIT[RB][WEST].is_head   = R_OFLIT[RA][EAST].is_head;
        assign R_IFLIT[RB][WEST].is_tail   = R_OFLIT[RA][EAST].is_tail;
        assign R_IFLIT[RB][WEST].vc_id     = R_OFLIT[RA][EAST].vc_id;
        assign R_OFLIT[RA][EAST].ready     = R_IFLIT[RB][WEST].ready;
        assign R_OFLIT[RA][EAST].credit_return = R_IFLIT[RB][WEST].credit_return;

        // RB.WEST -> RA.EAST
        assign R_IFLIT[RA][EAST].valid     = R_OFLIT[RB][WEST].valid;
        assign R_IFLIT[RA][EAST].flit_data = R_OFLIT[RB][WEST].flit_data;
        assign R_IFLIT[RA][EAST].is_head   = R_OFLIT[RB][WEST].is_head;
        assign R_IFLIT[RA][EAST].is_tail   = R_OFLIT[RB][WEST].is_tail;
        assign R_IFLIT[RA][EAST].vc_id     = R_OFLIT[RB][WEST].vc_id;
        assign R_OFLIT[RB][WEST].ready     = R_IFLIT[RA][EAST].ready;
        assign R_OFLIT[RB][WEST].credit_return = R_IFLIT[RA][EAST].credit_return;
      end
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Vertical links (NORTH/SOUTH), bidirectional
  // --------------------------------------------------------------------------
  generate
    for (gy = 0; gy < MESH_Y-1; gy++) begin : GEN_VLINK_Y
      for (gx = 0; gx < MESH_X; gx++) begin : GEN_VLINK_X
        localparam int RA = (gy * MESH_X) + gx;             // south router
        localparam int RB = ((gy + 1) * MESH_X) + gx;       // north router

        // RA.NORTH -> RB.SOUTH
        assign R_IFLIT[RB][SOUTH].valid     = R_OFLIT[RA][NORTH].valid;
        assign R_IFLIT[RB][SOUTH].flit_data = R_OFLIT[RA][NORTH].flit_data;
        assign R_IFLIT[RB][SOUTH].is_head   = R_OFLIT[RA][NORTH].is_head;
        assign R_IFLIT[RB][SOUTH].is_tail   = R_OFLIT[RA][NORTH].is_tail;
        assign R_IFLIT[RB][SOUTH].vc_id     = R_OFLIT[RA][NORTH].vc_id;
        assign R_OFLIT[RA][NORTH].ready     = R_IFLIT[RB][SOUTH].ready;
        assign R_OFLIT[RA][NORTH].credit_return = R_IFLIT[RB][SOUTH].credit_return;

        // RB.SOUTH -> RA.NORTH
        assign R_IFLIT[RA][NORTH].valid     = R_OFLIT[RB][SOUTH].valid;
        assign R_IFLIT[RA][NORTH].flit_data = R_OFLIT[RB][SOUTH].flit_data;
        assign R_IFLIT[RA][NORTH].is_head   = R_OFLIT[RB][SOUTH].is_head;
        assign R_IFLIT[RA][NORTH].is_tail   = R_OFLIT[RB][SOUTH].is_tail;
        assign R_IFLIT[RA][NORTH].vc_id     = R_OFLIT[RB][SOUTH].vc_id;
        assign R_OFLIT[RB][SOUTH].ready     = R_IFLIT[RA][NORTH].ready;
        assign R_OFLIT[RB][SOUTH].credit_return = R_IFLIT[RA][NORTH].credit_return;
      end
    end
  endgenerate

  // --------------------------------------------------------------------------
  // Boundary tie-offs for non-existent neighbors
  // --------------------------------------------------------------------------
  generate
    for (gy = 0; gy < MESH_Y; gy++) begin : GEN_BOUNDARY_Y
      for (gx = 0; gx < MESH_X; gx++) begin : GEN_BOUNDARY_X
        localparam int RID = (gy * MESH_X) + gx;

        if (gx == 0) begin : GEN_WEST_EDGE
          assign R_IFLIT[RID][WEST].valid     = 1'b0;
          assign R_IFLIT[RID][WEST].flit_data = '0;
          assign R_IFLIT[RID][WEST].is_head   = 1'b0;
          assign R_IFLIT[RID][WEST].is_tail   = 1'b0;
          assign R_IFLIT[RID][WEST].vc_id     = '0;
          assign R_OFLIT[RID][WEST].ready     = 1'b0;
          assign R_OFLIT[RID][WEST].credit_return = '0;
        end

        if (gx == MESH_X-1) begin : GEN_EAST_EDGE
          assign R_IFLIT[RID][EAST].valid     = 1'b0;
          assign R_IFLIT[RID][EAST].flit_data = '0;
          assign R_IFLIT[RID][EAST].is_head   = 1'b0;
          assign R_IFLIT[RID][EAST].is_tail   = 1'b0;
          assign R_IFLIT[RID][EAST].vc_id     = '0;
          assign R_OFLIT[RID][EAST].ready     = 1'b0;
          assign R_OFLIT[RID][EAST].credit_return = '0;
        end

        if (gy == 0) begin : GEN_SOUTH_EDGE
          assign R_IFLIT[RID][SOUTH].valid     = 1'b0;
          assign R_IFLIT[RID][SOUTH].flit_data = '0;
          assign R_IFLIT[RID][SOUTH].is_head   = 1'b0;
          assign R_IFLIT[RID][SOUTH].is_tail   = 1'b0;
          assign R_IFLIT[RID][SOUTH].vc_id     = '0;
          assign R_OFLIT[RID][SOUTH].ready     = 1'b0;
          assign R_OFLIT[RID][SOUTH].credit_return = '0;
        end

        if (gy == MESH_Y-1) begin : GEN_NORTH_EDGE
          assign R_IFLIT[RID][NORTH].valid     = 1'b0;
          assign R_IFLIT[RID][NORTH].flit_data = '0;
          assign R_IFLIT[RID][NORTH].is_head   = 1'b0;
          assign R_IFLIT[RID][NORTH].is_tail   = 1'b0;
          assign R_IFLIT[RID][NORTH].vc_id     = '0;
          assign R_OFLIT[RID][NORTH].ready     = 1'b0;
          assign R_OFLIT[RID][NORTH].credit_return = '0;
        end
      end
    end
  endgenerate

endmodule

