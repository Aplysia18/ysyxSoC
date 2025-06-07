module apb_delayer(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  parameter log2s = 2; //s=4, log2(4) = 2
  parameter rxs = 19; // 4*4.71=18.84->19

  parameter IDLE = 2'b00; //wait for psel
  parameter SETUP = 2'b01;  //wait for in_penable & out_pready
  parameter DELAY = 2'b11;  //delay
  reg [1:0] state, next_state;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always @(*) begin
    case(state)
      IDLE: begin
        if(in_psel && !in_penable) begin
          next_state = SETUP;
        end else begin
          next_state = IDLE;
        end
      end
      SETUP: begin
        if(in_penable && out_pready) begin
          next_state = DELAY;
        end else begin
          next_state = SETUP;
        end
      end
      DELAY: begin
        if(in_pready == 1) begin
          next_state = IDLE; //go back to IDLE after delay
        end else begin
          next_state = DELAY; //stay in DELAY state
        end
      end
      default: begin
        next_state = IDLE; //default to IDLE state
      end
    endcase
  end

  reg [31:0] delay_counter;
  reg [31:0] delay_counter_setup;
  reg [31:0] delay_counter_xs;  //delay multiply magnification factor
  
  reg [31:0] save_prdata;
  reg save_pslverr;
  reg reg_pready;

  always @(posedge clock or posedge reset) begin
    if(reset) begin
      delay_counter <= 0;
      delay_counter_xs <= 0;
      save_prdata <= 0;
      save_pslverr <= 0;    
      reg_pready <= 0;
    end else begin
      case(state)
        IDLE: begin
          if(in_psel && !in_penable) begin
            delay_counter <= 0;
            delay_counter_xs <= rxs;
            delay_counter_setup <= 1;
            save_prdata <= 0;
            save_pslverr <= 0; 
            reg_pready <= 0;   
          end else begin
            delay_counter <= 0;
            delay_counter_xs <= 0;
            delay_counter_setup <= 0;
            save_prdata <= 0;
            save_pslverr <= 0;
            reg_pready <= 0;  
          end
        end
        SETUP: begin
          if(in_penable && out_pready) begin
            delay_counter <= (delay_counter_xs >> log2s) - delay_counter_setup;
            delay_counter_xs <= 0;
            save_prdata <= out_prdata;
            save_pslverr <= out_pslverr;
            reg_pready <= 0;
          end else begin
            delay_counter <= 0;
            delay_counter_xs <= delay_counter_xs + rxs;
            delay_counter_setup <= delay_counter_setup + 1;
            save_prdata <= 0;
            save_pslverr <= 0;
            reg_pready <= 0;
          end
        end
        DELAY: begin
          if(delay_counter == 0) begin
            delay_counter <= 0;
            delay_counter_xs <= 0;
            save_prdata <= save_prdata;
            save_pslverr <= save_pslverr;
            reg_pready <= 1; //set ready signal
          end else begin
            delay_counter <= delay_counter - 1;
            delay_counter_xs <= 0;
            save_prdata <= save_prdata;
            save_pslverr <= save_pslverr;
            reg_pready <= 0; //not ready
          end
        end
        default: begin
          delay_counter <= 0;
          delay_counter_xs <= 0;
          save_prdata <= 0;
          save_pslverr <= 0;
          reg_pready <= 0; //default to not ready
        end
      endcase
    end
  end


  assign out_paddr   = in_paddr;
  assign out_psel    = (state==DELAY) ? 0 : in_psel;
  assign out_penable = (state==DELAY) ? 0 : in_penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;

  assign in_pready   = reg_pready;
  assign in_prdata   = save_prdata;
  assign in_pslverr  = save_pslverr;

endmodule
