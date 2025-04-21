module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);

  parameter getd_t = 1'b0;
  parameter outd_t = 1'b1;
  reg state;
  reg [5:0] counter;

  wire reset = ss;

  always @(posedge sck or posedge reset) begin
    if (reset) begin
      state <= getd_t;
    end else begin
      case (state)
        getd_t: state <= (counter == 6'd7 ) ? outd_t : state;
        outd_t: state <= state;
        default: begin
          state <= state;
          $fatal;
        end
      endcase
    end
  end

  always @(posedge sck or posedge reset) begin
    if (reset) begin
      counter <= 6'd0;
    end else begin
      case (state)
        getd_t: counter <= (counter < 6'd7 ) ? counter + 6'd1 : 6'd0;
        outd_t: counter <= (counter < 6'd15) ? counter + 6'd1 : 6'd0;
        default: counter <= counter + 6'd1;
      endcase
    end
  end

  reg [7:0] data;

  always @(posedge sck or posedge reset) begin
    if (reset) begin
      data <= 8'd0;
    end else begin
      case (state)
        getd_t: begin
          data <= { data[6:0], mosi };
        end
        outd_t: data <= {1'b0, data[7:1]};
        default: data <= data;
      endcase
    end
  end

  assign miso = (state == outd_t) ? data[0] : 1'b1;

endmodule
