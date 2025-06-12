module axi4_delayer(
  input         clock,
  input         reset,

  output        in_arready,
  input         in_arvalid,
  input  [3:0]  in_arid,
  input  [31:0] in_araddr,
  input  [7:0]  in_arlen,
  input  [2:0]  in_arsize,
  input  [1:0]  in_arburst,
  input         in_rready,
  output        in_rvalid,
  output [3:0]  in_rid,
  output [31:0] in_rdata,
  output [1:0]  in_rresp,
  output        in_rlast,
  output        in_awready,
  input         in_awvalid,
  input  [3:0]  in_awid,
  input  [31:0] in_awaddr,
  input  [7:0]  in_awlen,
  input  [2:0]  in_awsize,
  input  [1:0]  in_awburst,
  output        in_wready,
  input         in_wvalid,
  input  [31:0] in_wdata,
  input  [3:0]  in_wstrb,
  input         in_wlast,
                in_bready,
  output        in_bvalid,
  output [3:0]  in_bid,
  output [1:0]  in_bresp,

  input         out_arready,
  output        out_arvalid,
  output [3:0]  out_arid,
  output [31:0] out_araddr,
  output [7:0]  out_arlen,
  output [2:0]  out_arsize,
  output [1:0]  out_arburst,
  output        out_rready,
  input         out_rvalid,
  input  [3:0]  out_rid,
  input  [31:0] out_rdata,
  input  [1:0]  out_rresp,
  input         out_rlast,
  input         out_awready,
  output        out_awvalid,
  output [3:0]  out_awid,
  output [31:0] out_awaddr,
  output [7:0]  out_awlen,
  output [2:0]  out_awsize,
  output [1:0]  out_awburst,
  input         out_wready,
  output        out_wvalid,
  output [31:0] out_wdata,
  output [3:0]  out_wstrb,
  output        out_wlast,
                out_bready,
  input         out_bvalid,
  input  [3:0]  out_bid,
  input  [1:0]  out_bresp
);


  parameter log2s = 2; //s=4, log2(4) = 2
  parameter rxs = 19; // 4*4.71=18.84->19

/*----------------------read channel------------------------*/
  parameter READ_IDLE = 2'b00; //wait for arvalid
  parameter READ_WAIT_RESP = 2'b01;  //out_rvalid
  parameter READ_DELAY = 2'b11;  //delay
  
  reg [1:0] read_state, read_next_state;
  always @(posedge clock or posedge reset) begin
    if(reset) begin
      read_state <= READ_IDLE;
    end else begin
      read_state <= read_next_state;
    end
  end

  always @(*) begin
    case(read_state)
      READ_IDLE: begin
        if(in_arvalid) begin
          read_next_state = READ_WAIT_RESP;
        end else begin
          read_next_state = READ_IDLE;
        end
      end
      READ_WAIT_RESP: begin
        if(out_rvalid) begin
          read_next_state = READ_DELAY;
        end else begin
          read_next_state = READ_WAIT_RESP;
        end
      end
      READ_DELAY: begin
        if(in_rvalid & in_rlast) begin
          read_next_state = READ_IDLE; //go back to IDLE after last read
        end else begin
          read_next_state = READ_DELAY;
        end
      end
      default: read_next_state = READ_IDLE;
    endcase
  end


  reg [31:0] read_counter_after_arvalid_rxs;
  reg [31:0] read_counter_after_arvalid;

  reg [3:0] burst_num; //burst number, max 8 burst
  reg [3:0] burst_num_delay;  // record the burst rvalid number for in_rvalid

  reg [31:0] read_delay_counter[0:7]; //max 8 burst
  reg [31:0] read_delay_counter_passed[0:7];
  reg [31:0] rdata[0:7]; //max 8 burst rdata
  reg [3:0] rid[0:7]; //max 8 burst rid
  reg [1:0] rresp[0:7]; //max 8 burst rresp
  reg [7:0] rlast;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      read_counter_after_arvalid_rxs <= 0;
      read_counter_after_arvalid <= 0;
      
      burst_num <= 0; //reset burst number
      burst_num_delay <= 0; //reset burst number delay

    end else begin
      case(read_state)
        READ_IDLE: begin
          read_counter_after_arvalid_rxs <= rxs;
          read_counter_after_arvalid <= 1;
          burst_num <= 0; //reset burst number
          burst_num_delay <= 0; //reset burst number delay
          rlast <= 0; //reset rlast
        end
        READ_WAIT_RESP: begin
          read_counter_after_arvalid_rxs <= read_counter_after_arvalid_rxs + rxs;
          read_counter_after_arvalid <= read_counter_after_arvalid + 1;
          
          burst_num_delay <= 0; 
          if(out_rvalid) begin
            read_delay_counter[burst_num[2:0]] <= (read_counter_after_arvalid_rxs>>log2s) - read_counter_after_arvalid;
            read_delay_counter_passed[burst_num[2:0]] <= 0; //reset read delay counter passed
            burst_num <= burst_num + 1; //increment burst number
            rdata[burst_num[2:0]] <= out_rdata; //save rdata
            rid[burst_num[2:0]] <= out_rid; //save rid
            rresp[burst_num[2:0]] <= out_rresp; //save rresp
            rlast[burst_num[2:0]] <= out_rlast; //save rlast
          end else begin
            burst_num <= 0; //reset burst number
          end
        end
        READ_DELAY: begin
          read_counter_after_arvalid_rxs <= read_counter_after_arvalid_rxs + rxs;
          read_counter_after_arvalid <= read_counter_after_arvalid + 1;
          if(out_rvalid) begin
            burst_num <= burst_num + 1;
            rdata[burst_num[2:0]] <= out_rdata; //save rdata
            rid[burst_num[2:0]] <= out_rid; //save rid
            rresp[burst_num[2:0]] <= out_rresp; //save rresp
            rlast[burst_num[2:0]] <= out_rlast; //save rlast
            read_delay_counter[burst_num[2:0]] <= (read_counter_after_arvalid_rxs>>log2s) - read_counter_after_arvalid;
            read_delay_counter_passed[burst_num[2:0]] <= 0; //reset read delay counter passed
          end else begin
            burst_num <= burst_num;
          end
          
          if(read_delay_counter_passed[burst_num_delay[2:0]] == read_delay_counter[burst_num_delay[2:0]]) begin
            burst_num_delay <= burst_num_delay + 1; //increment burst number delay
          end else begin
            burst_num_delay <= burst_num_delay; //keep burst number delay
          end
          read_delay_counter_passed[0] <= (burst_num_delay == 0) ? read_delay_counter_passed[0]+1 : 32'b0;
          read_delay_counter_passed[1] <= (burst_num_delay <= 1)&&(burst_num > 1) ? read_delay_counter_passed[1]+1 : 32'b0;
          read_delay_counter_passed[2] <= (burst_num_delay <= 2)&&(burst_num > 2) ? read_delay_counter_passed[2]+1 : 32'b0;
          read_delay_counter_passed[3] <= (burst_num_delay <= 3)&&(burst_num > 3) ? read_delay_counter_passed[3]+1 : 32'b0;
          read_delay_counter_passed[4] <= (burst_num_delay <= 4)&&(burst_num > 4) ? read_delay_counter_passed[4]+1 : 32'b0;
          read_delay_counter_passed[5] <= (burst_num_delay <= 5)&&(burst_num > 5) ? read_delay_counter_passed[5]+1 : 32'b0;
          read_delay_counter_passed[6] <= (burst_num_delay <= 6)&&(burst_num > 6) ? read_delay_counter_passed[6]+1 : 32'b0;
          read_delay_counter_passed[7] <= (burst_num_delay <= 7)&&(burst_num > 7) ? read_delay_counter_passed[7]+1 : 32'b0;
        end
        default: begin
          read_counter_after_arvalid_rxs <= 0;
          read_counter_after_arvalid <= 0;

          burst_num <= 0; //reset burst number
          burst_num_delay <= 0; //reset burst number delay

          rlast <= 0; //reset rlast
        end
      endcase
    end
  end

  assign in_arready = out_arready;
  assign out_arvalid = in_arvalid;
  assign out_arid = in_arid;
  assign out_araddr = in_araddr;
  assign out_arlen = in_arlen;
  assign out_arsize = in_arsize;
  assign out_arburst = in_arburst;
  assign out_rready = in_rready;
  assign in_rvalid = (read_state==READ_DELAY) & (read_delay_counter_passed[burst_num_delay[2:0]] == read_delay_counter[burst_num_delay[2:0]]);
  assign in_rid = rid[burst_num_delay[2:0]];
  assign in_rdata = rdata[burst_num_delay[2:0]];
  assign in_rresp = rresp[burst_num_delay[2:0]];
  assign in_rlast = rlast[burst_num_delay[2:0]];

/*---------------------------write channel---------------------------*/

  parameter WRITE_IDLE = 2'b00; //wait for awvalid/wvalid
  parameter WRITE_WAIT_RESP = 2'b01;  //out_bvalid
  parameter WRITE_DELAY = 2'b11;  //delay
  
  reg [1:0] write_state, write_next_state;
  always @(posedge clock or posedge reset) begin
    if(reset) begin
      write_state <= WRITE_IDLE;
    end else begin
      write_state <= write_next_state;
    end
  end

  always @(*) begin
    case(write_state)
      WRITE_IDLE: begin
        if(in_awvalid | in_wvalid) begin
          write_next_state = WRITE_WAIT_RESP;
        end else begin
          write_next_state = WRITE_IDLE;
        end
      end
      WRITE_WAIT_RESP: begin
        if(out_bvalid) begin
          write_next_state = WRITE_DELAY;
        end else begin
          write_next_state = WRITE_WAIT_RESP;
        end
      end
      WRITE_DELAY: begin
        if(in_bvalid) begin
          write_next_state = WRITE_IDLE; //go back to IDLE after bvalid
        end else begin
          write_next_state = WRITE_DELAY;
        end
      end
      default: write_next_state = WRITE_IDLE;
    endcase
  end


  reg [31:0] write_counter_after_awvalid_rxs;
  reg [31:0] write_counter_after_awvalid;

  reg [31:0] write_delay_counter; 
  reg [3:0] bid;
  reg [1:0] bresp;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      write_counter_after_awvalid_rxs <= 0;
      write_counter_after_awvalid <= 0;
      write_delay_counter <= 0; //reset write delay counter
      bid <= 0; //reset bid
      bresp <= 0; //reset bresp
    end else begin
      case(write_state)
        WRITE_IDLE: begin
          write_counter_after_awvalid_rxs <= rxs;
          write_counter_after_awvalid <= 1;
          write_delay_counter <= 0;
          bid <= 0;
          bresp <= 0;
        end
        WRITE_WAIT_RESP: begin
          write_counter_after_awvalid_rxs <= write_counter_after_awvalid_rxs + rxs;
          write_counter_after_awvalid <= write_counter_after_awvalid + 1;
          if(out_bvalid) begin
            write_delay_counter <= (write_counter_after_awvalid_rxs>>log2s) - write_counter_after_awvalid;
            bid <= out_bid; //save bid
            bresp <= out_bresp; //save bresp
          end else begin
            write_delay_counter <= 0; 
            bid <= 0;
            bresp <= 0;
          end
        end
        WRITE_DELAY: begin
          write_counter_after_awvalid_rxs <= 0;
          write_counter_after_awvalid <= 0;
          write_delay_counter <= write_delay_counter - 1;
          bid <= bid;
          bresp <= bresp;
        end
        default: begin
          write_counter_after_awvalid_rxs <= 0;
          write_counter_after_awvalid <= 0;
          write_delay_counter <= 0;
          bid <= 0;
          bresp <= 0;
        end
      endcase
    end
  end

  assign in_awready = out_awready;
  assign out_awvalid = in_awvalid;
  assign out_awid = in_awid;
  assign out_awaddr = in_awaddr;
  assign out_awlen = in_awlen;
  assign out_awsize = in_awsize;
  assign out_awburst = in_awburst;
  assign in_wready = out_wready;
  assign out_wvalid = in_wvalid;
  assign out_wdata = in_wdata;
  assign out_wstrb = in_wstrb;
  assign out_wlast = in_wlast;
  assign out_bready = in_bready;
  assign in_bvalid = (write_state==WRITE_DELAY) & (write_delay_counter==0);
  assign in_bid = bid;
  assign in_bresp = bresp;

endmodule
