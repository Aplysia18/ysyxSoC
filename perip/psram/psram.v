module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);
  wire reset;
  assign reset = ce_n;

  reg [7:0] cmd;
  wire ren, wen;
  reg [23:0] addr;
  reg [7:0] rdata, wdata;
  reg [3:0] in_data;
  wire [31:0] dwaddr,draddr;
  wire [23:0] addr_next;
  reg qspi_en;
  wire [7:0] cmd_length = (qspi_en==1) ? 8'd2: 8'd8;

  assign addr_next = addr+1;
  assign draddr = (state==wait_t) ? {8'd0, addr} : {8'd0, addr_next};
  assign dwaddr = {8'd0, addr};
  assign ren = ((state == wait_t) && (counter == 8'd6))||((state == read_t) && (counter[0]==1));
  assign wen = (state == write_t) && (counter[0] == 1);
  assign wdata = {in_data, dio};
  assign dio = (state == read_t) ? (counter[0]==0) ? rdata[7:4] : rdata[3:0] : 4'bz;

  psram_cmd psram_cmd_i(
    .clk(sck),
    .cmd(cmd),
    .raddr(draddr),
    .waddr(dwaddr),
    .ren(ren),
    .wen(wen),
    .wdata(wdata),
    .rdata(rdata)
  );

  typedef enum [2:0] { cmd_t, addr_t, wait_t, read_t, write_t, err_t } state_t;
  reg [2:0] state;
  reg [7:0] counter;

  always @(posedge sck or  posedge reset) begin
    if(reset) state <= cmd_t;
    else begin
      case(state)
        cmd_t: begin
          if(qspi_en==1) begin
            state <= (counter == cmd_length-1) ? addr_t : state;
          end else begin
            if(counter == cmd_length-1) begin
              if({cmd[6:0], dio[0]} == 8'h35) begin
                state <= cmd_t;
                qspi_en <= 1;
              end else state <= addr_t;
            end else state <= cmd_t;
          end
        end
        addr_t: state <= (counter == 8'd5) ? (cmd == 8'hEB) ? wait_t : 
                         (cmd == 8'h38) ? write_t : err_t : state;
        wait_t: state <= (counter == 8'd6) ? read_t : state;
        read_t: state <= state;
        write_t: state <= state;
        default: begin
          state <= state;
          $display("psram: Unsupported command `%h`", cmd);
          $fatal;
        end
      endcase
    end
  end

  always @(posedge sck or posedge reset) begin
    if(reset) counter <= 0;
    else begin
      case(state)
        cmd_t: counter <= (counter < cmd_length - 1) ? counter + 8'd1 : 8'd0;
        addr_t: counter <= (counter < 8'd5) ? counter + 8'd1 : 8'd0;
        wait_t: counter <= (counter < 8'd6) ? counter + 8'd1 : 8'd0;
        default: counter <= counter + 8'd1;
      endcase
    end
  end

  always @(posedge sck or posedge reset) begin
    if(reset) cmd <= 8'd0;
    else if(state == cmd_t) begin 
      if(qspi_en) begin
        cmd <= {cmd[3:0], dio};
      end else begin
        cmd <= {cmd[6:0], dio[0]};
      end
    end
  end

  always @(posedge sck or posedge reset) begin
    if(reset) addr <= 24'd0;
    else if(state == addr_t && counter <= 8'd5) begin
      addr <= {addr[19:0], dio};
    end else if(state == write_t || state == read_t) begin
      if(counter[0]==1) addr <= addr + 24'd1; 
    end
  end

  always @(posedge sck or posedge reset) begin
    if(reset) in_data <= 4'd0;
    else if(state == write_t)
      in_data <= dio;
    else in_data <= 4'd0;
  end

endmodule

import "DPI-C" function void psram_read(input int addr, output byte data);
import "DPI-C" function void psram_write(input int addr, input byte data);

module psram_cmd(
  input clk,
  input [7:0] cmd,
  input [31:0] raddr,
  input [31:0] waddr,
  input ren,
  input wen,
  input [7:0] wdata,
  output reg [7:0] rdata
);
  always @(posedge clk) begin
    if (ren | wen) begin
      case (cmd)
        8'hEB: begin // Read command
          if(ren) psram_read(raddr, rdata);
          else begin
            $display("psram_cmd: psram_read wrong");
            $fatal;
          end
        end
        8'h38: begin // Write command
          if(wen) psram_write(waddr, wdata);
          else begin
            $display("psram_cmd: psram_write wrong");
            $fatal;
          end
        end
        default: begin
          $display("psram_cmd: Unsupported command: %h", cmd);
          $fatal;
        end
      endcase
    end
  end 


endmodule