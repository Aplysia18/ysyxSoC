module gpio_top_apb(
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

  output [15:0] gpio_out, //output 16 led
  input  [15:0] gpio_in,  //input 16 switch
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);
  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;

  wire apb_write, apb_read;
  assign apb_write = in_psel & in_penable & in_pwrite;
  assign apb_read  = in_psel & in_penable & !in_pwrite;
  assign in_prdata = apb_read & (in_paddr==32'h10002004) ? {16'b0, gpio_in} : 32'b0;

  reg [15:0] led_reg;
  reg [31:0] seg_reg;
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      led_reg <= 0;
      seg_reg <= 0;
    end else begin
      if (apb_write & (in_paddr==32'h10002000)) begin
        led_reg <= in_pwdata[15:0];
      end
      if (apb_write & (in_paddr==32'h10002008)) begin
        seg_reg <= in_pwdata[31:0];
      end
    end
  end

  assign gpio_out = led_reg[15:0];

  wire [3:0] seg7, seg6, seg5, seg4, seg3, seg2, seg1, seg0;
  assign {seg7, seg6, seg5, seg4, seg3, seg2, seg1, seg0} = seg_reg;
  bcd7seg seg0_inst (.b(seg0), .h(gpio_seg_0));
  bcd7seg seg1_inst (.b(seg1), .h(gpio_seg_1)); 
  bcd7seg seg2_inst (.b(seg2), .h(gpio_seg_2));
  bcd7seg seg3_inst (.b(seg3), .h(gpio_seg_3));
  bcd7seg seg4_inst (.b(seg4), .h(gpio_seg_4));
  bcd7seg seg5_inst (.b(seg5), .h(gpio_seg_5));
  bcd7seg seg6_inst (.b(seg6), .h(gpio_seg_6));
  bcd7seg seg7_inst (.b(seg7), .h(gpio_seg_7));

endmodule

module bcd7seg (
  input [3:0] b,
  output reg [7:0] h
);

  always @(*) begin
    case(b)
      4'b0000: h = 8'b00000011;
      4'b0001: h = 8'b10011111;
      4'b0010: h = 8'b00100101;
      4'b0011: h = 8'b00001101;
      4'b0100: h = 8'b10011001;
      4'b0101: h = 8'b01001001;
      4'b0110: h = 8'b01000001;
      4'b0111: h = 8'b00011111;
      4'b1000: h = 8'b00000001;
      4'b1001: h = 8'b00001001;
      4'b1010: h = 8'b00010001;
      4'b1011: h = 8'b11000001;
      4'b1100: h = 8'b01100011;
      4'b1101: h = 8'b10000101;
      4'b1110: h = 8'b01100001;
      4'b1111: h = 8'b01110001;
      default: h = 8'b11111111;
    endcase
  end
  
endmodule