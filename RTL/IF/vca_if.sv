import noc_params::*;

interface vca_if;

  // Requested output port per IVC.
  port_t REQRPT [VC_NUM-1:0];
  // Allowable local OVC mask at the requested output port.
  logic [VC_PER_PORT-1:0] REQVC [VC_NUM-1:0];

  // Final selected local OVC (one-hot) and grant bit per IVC.
  logic [VC_PER_PORT-1:0] SEL_OVC [VC_NUM-1:0];
  logic [VC_NUM-1:0]       GRT_OVC;

  // Current global occupancy state from SU and update bitmap from VAU.
  logic [VC_NUM-1:0] OVC_STATE;
  logic [VC_NUM-1:0] UPDATE;

  modport vca (
    input  REQRPT,
    input  REQVC,
    input  OVC_STATE,
    output SEL_OVC,
    output GRT_OVC,
    output UPDATE
  );

  modport rcu (
    output REQRPT,
    output REQVC
  );

  modport su (
    output OVC_STATE,
    input  UPDATE
  );


endinterface
