module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;

  wire write;
  assign write = in_psel & in_penable & in_pwrite & (in_paddr >= 32'h21000000) & (in_paddr < 32'h21200000); // 0x2100_0000~0x211f_ffff
  wire [18:0] addr;
  assign addr = in_paddr[20:2];

  reg [23:0] mem[0:307199]; // 640*480=307200

  always @(posedge reset or posedge clock) begin
    if(!reset) begin
        if (write) begin
          // 写入数据到VGA内存
          if (addr < 307200) begin
            mem[addr] <= in_pwdata[23:0]; // 只取低24位作为颜色数据
          end else $fatal("VGA memory write out of bounds: %h", in_paddr);
        end
      end
  end

  wire [9:0] h_addr;
  wire [9:0] v_addr;
  wire [23:0] vga_data;
  assign vga_data = mem[(v_addr*640) + h_addr]; // 640*480, 每个像素点24位颜色数据

  // wire clk_25mhz;
  // clkgen #(.clk_freq(25000000)) clkgen_inst (
  //   .clkin(clock),
  //   .rst(reset),
  //   .clken(in_psel & in_penable),
  //   .clkout(clk_25mhz)
  // );
  vga_ctrl vga_ctrl_inst (
    .pclk(clock),
    .reset(reset),
    .vga_data(vga_data),
    .h_addr(h_addr),
    .v_addr(v_addr),
    .hsync(vga_hsync),
    .vsync(vga_vsync),
    .valid(vga_valid),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b)
  );

endmodule


// module clkgen(
//     input clkin,
//     input rst,
//     input clken,
//     output reg clkout
//     );
//     parameter clk_freq=1000;
//     parameter countlimit=50000000/2/clk_freq; //自动计算计数次数

//   reg[31:0] clkcount;
//   always @ (posedge clkin)
//     if(rst)
//     begin
//         clkcount=0;
//         clkout=1'b0;
//     end
//     else
//     begin
//     if(clken)
//         begin
//             clkcount=clkcount+1;
//             if(clkcount>=countlimit)
//             begin
//                 clkcount=32'd0;
//                 clkout=~clkout;
//             end
//             else
//                 clkout=clkout;
//         end
//       else
//         begin
//             clkcount=clkcount;
//             clkout=clkout;
//         end
//     end
// endmodule

module vga_ctrl(
    input           pclk,     //25MHz时钟
    input           reset,    //置位
    input  [23:0]   vga_data, //上层模块提供的VGA颜色数据
    output [9:0]    h_addr,   //提供给上层模块的当前扫描像素点坐标
    output [9:0]    v_addr,
    output          hsync,    //行同步和列同步信号
    output          vsync,
    output          valid,    //消隐信号
    output [7:0]    vga_r,    //红绿蓝颜色信号
    output [7:0]    vga_g,
    output [7:0]    vga_b
    );

  //640x480分辨率下的VGA参数设置
  parameter    h_frontporch = 96;
  parameter    h_active = 144;
  parameter    h_backporch = 784;
  parameter    h_total = 800;

  parameter    v_frontporch = 2;
  parameter    v_active = 35;
  parameter    v_backporch = 515;
  parameter    v_total = 525;

  //像素计数值
  reg [9:0]    x_cnt;
  reg [9:0]    y_cnt;
  wire         h_valid;
  wire         v_valid;

  always @(posedge reset or posedge pclk) //行像素计数
      if (reset == 1'b1)
        x_cnt <= 1;
      else
      begin
        if (x_cnt == h_total)
            x_cnt <= 1;
        else
            x_cnt <= x_cnt + 10'd1;
      end

  always @(posedge pclk)  //列像素计数
      if (reset == 1'b1)
        y_cnt <= 1;
      else
      begin
        if (y_cnt == v_total & x_cnt == h_total)
            y_cnt <= 1;
        else if (x_cnt == h_total)
            y_cnt <= y_cnt + 10'd1;
      end
  //生成同步信号
  assign hsync = (x_cnt > h_frontporch);
  assign vsync = (y_cnt > v_frontporch);
  //生成消隐信号
  assign h_valid = (x_cnt > h_active) & (x_cnt <= h_backporch);
  assign v_valid = (y_cnt > v_active) & (y_cnt <= v_backporch);
  assign valid = h_valid & v_valid;
  //计算当前有效像素坐标
  assign h_addr = h_valid ? (x_cnt - 10'd145) : {10{1'b0}};
  assign v_addr = v_valid ? (y_cnt - 10'd36) : {10{1'b0}};
  //设置输出的颜色值
  assign vga_r = vga_data[23:16];
  assign vga_g = vga_data[15:8];
  assign vga_b = vga_data[7:0];
endmodule