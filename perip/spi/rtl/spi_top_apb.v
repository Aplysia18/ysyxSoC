// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

  /*-----XIP for FLASH-----*/
  typedef enum [3:0] { idle_t, xip_write_cmdaddr_t, xip_write_cmdaddr_enable_t, xip_write_divider_t, xip_write_divider_enable_t, 
                      xip_write_ss_t, xip_write_ss_enable_t, xip_write_ctrl_t, xip_write_ctrl_enable_t, xip_write_go_t, xip_write_go_enable_t, 
                      xip_wait_t, xip_wait_enable_t, xip_rdata_t, xip_rdata_enable_t, xip_ret_t} state_t;
  reg [3:0] state;
  reg [3:0] next_state;
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      state <= idle_t;
    end else begin
      state <= next_state;
    end
  end

  wire addr_in_flash;
  assign addr_in_flash = (in_paddr >= flash_addr_start) && (in_paddr <= flash_addr_end);

  reg [4:0] xip_paddr;
  reg [31:0] xip_pwdata;
  reg xip_pwrite, xip_psel, xip_penable;
  reg xip_pready;
  reg [31:0] xip_prdata;

  always @(*) begin
    case (state)
      idle_t: begin
        if (in_psel && in_penable && !in_pwrite && addr_in_flash) begin
          next_state = xip_write_cmdaddr_t;
        end else begin
          next_state = idle_t;
        end
      end
      xip_write_cmdaddr_t: begin
          next_state = xip_write_cmdaddr_enable_t;
      end
      xip_write_cmdaddr_enable_t: begin
        if (spi_pready) begin
          next_state = xip_write_divider_t;
        end else begin
          next_state = xip_write_cmdaddr_enable_t;
        end
      end
      xip_write_divider_t: begin
          next_state = xip_write_divider_enable_t;
      end
      xip_write_divider_enable_t: begin
        if (spi_pready) begin
          next_state = xip_write_ss_t;
        end else begin
          next_state = xip_write_divider_enable_t;
        end
      end
      xip_write_ss_t: begin
          next_state = xip_write_ss_enable_t;
      end
      xip_write_ss_enable_t: begin
        if (spi_pready) begin
          next_state = xip_write_ctrl_t;
        end else begin
          next_state = xip_write_ss_enable_t;
        end
      end
      xip_write_ctrl_t: begin
          next_state = xip_write_ctrl_enable_t;
      end
      xip_write_ctrl_enable_t: begin
        if (spi_pready) begin
          next_state = xip_write_go_t;
        end else begin
          next_state = xip_write_ctrl_enable_t;
        end
      end
      xip_write_go_t: begin
          next_state = xip_write_go_enable_t;
      end
      xip_write_go_enable_t: begin
        if (spi_pready) begin
          next_state = xip_wait_t;
        end else begin
          next_state = xip_write_go_enable_t;
        end
      end
      xip_wait_t: begin
          next_state = xip_wait_enable_t;
      end
      xip_wait_enable_t: begin
        if(spi_pready) begin
          if(|(spi_prdata & 32'h100)) begin //wait for go=0
            next_state = xip_wait_t;
          end else begin
            next_state = xip_rdata_t;
          end
        end else begin
          next_state = xip_wait_enable_t;
        end
      end
      xip_rdata_t: begin
          next_state = xip_rdata_enable_t;
      end
      xip_rdata_enable_t: begin
        if (spi_pready) begin
          next_state = xip_ret_t;
        end else begin
          next_state = xip_rdata_enable_t;
        end
      end
      xip_ret_t: begin
        next_state = idle_t;
      end
    endcase
  end

  // XIP signal for flash
  always @(posedge clock or posedge reset) begin
    if(reset) begin
      xip_paddr <= 5'b0;
      xip_pwdata <= 32'b0;
      xip_pwrite <= 1'b0;
      xip_psel <= 1'b0;
      xip_penable <= 1'b0;
      xip_pready <= 1'b0;
      xip_prdata <= 32'b0;
    end else begin
      case(next_state)
        idle_t: begin
          xip_paddr <= 5'b0;
          xip_pwdata <= 32'b0;
          xip_pwrite <= 1'b0;
          xip_psel <= 1'b0;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_cmdaddr_t: begin
          xip_paddr <= 5'h04; // TX1 address
          xip_pwdata <= 32'h03000000|(in_paddr & 32'h00ffffff); // Command 0x03 and address
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_cmdaddr_enable_t: begin
          xip_paddr <= 5'h04; // TX1 address
          xip_pwdata <= 32'h03000000|(in_paddr & 32'h00ffffff); // Command 0x03 and address
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_divider_t: begin
          // Set the divider for the SPI clock
          xip_paddr <= 5'h14; // divider address
          xip_pwdata <= 32'b1; // divider value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_divider_enable_t: begin
          // Set the divider for the SPI clock
          xip_paddr <= 5'h14; // divider address
          xip_pwdata <= 32'b1; // divider value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_ss_t: begin
          // Set the slave select line
          xip_paddr <= 5'h18; // ss address
          xip_pwdata <= 32'b1; // ss value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_ss_enable_t: begin
          // Set the slave select line
          xip_paddr <= 5'h18; // ss address
          xip_pwdata <= 32'b1; // ss value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_ctrl_t: begin
          // Set the control signals for the SPI transfer
          xip_paddr <= 5'h10; // ctrl address
          xip_pwdata <= 32'h2040; // ctrl value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_ctrl_enable_t: begin
          // Set the control signals for the SPI transfer
          xip_paddr <= 5'h10; // ctrl address
          xip_pwdata <= 32'h2040; // ctrl value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_go_t: begin
          // Start the transfer
          xip_paddr <= 5'h10; // ctrl address
          xip_pwdata <= 32'h2140; // ctrl value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_write_go_enable_t: begin
          // Start the transfer
          xip_paddr <= 5'h10; // ctrl address
          xip_pwdata <= 32'h2140; // ctrl value
          xip_pwrite <= 1'b1;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_wait_t: begin
          // Wait for the transfer to complete
          xip_paddr <= 5'h10; // ctrl address
          xip_pwdata <= 32'h2140; // ctrl value
          xip_pwrite <= 1'b0;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_wait_enable_t: begin
          // Wait for the transfer to complete
          xip_paddr <= 5'h10; // ctrl address
          xip_pwdata <= 32'h2140; // ctrl value
          xip_pwrite <= 1'b0;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_rdata_t: begin
          // Read the data from the SPI
          xip_paddr <= 5'h0; // RX address
          xip_pwdata <= 32'b0;
          xip_pwrite <= 1'b0;
          xip_psel <= 1'b1;
          xip_penable <= 1'b0;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_rdata_enable_t: begin
          // Read the data from the SPI
          xip_paddr <= 5'h0; // RX address
          xip_pwdata <= 32'b0;
          xip_pwrite <= 1'b0;
          xip_psel <= 1'b1;
          xip_penable <= 1'b1;
          xip_pready <= 1'b0;
          xip_prdata <= 32'b0;
        end
        xip_ret_t: begin
          // return APB signal
          xip_paddr <= 5'b0;
          xip_pwdata <= 32'b0;
          xip_pwrite <= 1'b0;
          xip_psel <= 1'b0;
          xip_penable <= 1'b0;
          xip_pready <= 1'b1; //pready output
          xip_prdata <= {spi_prdata[7:0], spi_prdata[15:8], spi_prdata[23:16], spi_prdata[31:24]}; // byte swap
        end
      endcase
    end
  end

  /*----SPI-master signal selection----*/ 
  wire [4:0] spi_paddr;
  wire [31:0] spi_pwdata;
  wire [3:0] spi_pstrb;
  wire spi_pwrite, spi_psel, spi_penable;
  wire spi_pready;
  wire [31:0] spi_prdata;
  // SPI control signals select: addr_in_flash ? XIP : APB
  assign spi_paddr = (addr_in_flash) ? xip_paddr : in_paddr[4:0];
  assign spi_pwdata = (addr_in_flash) ? xip_pwdata : in_pwdata;
  assign spi_pstrb = (addr_in_flash) ? 4'b1111 : in_pstrb;
  assign spi_pwrite = (addr_in_flash) ? xip_pwrite : in_pwrite;
  assign spi_psel = (addr_in_flash) ? xip_psel : in_psel;
  assign spi_penable = (addr_in_flash) ? xip_penable : in_penable;
  assign in_pready = (addr_in_flash) ? xip_pready : spi_pready;
  assign in_prdata = (addr_in_flash) ? xip_prdata : spi_prdata;


spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(spi_paddr),
  .wb_dat_i(spi_pwdata),
  .wb_dat_o(spi_prdata),
  .wb_sel_i(spi_pstrb),
  .wb_we_i (spi_pwrite),
  .wb_stb_i(spi_psel),
  .wb_cyc_i(spi_penable),
  .wb_ack_o(spi_pready),
  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

`endif // FAST_FLASH

endmodule
