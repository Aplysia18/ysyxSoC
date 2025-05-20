module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);

  wire mtrace = 1'b0;

  //clock generation
  /* verilator lint_off MULTIDRIVEN */
  reg sys_clk;
  /* verilator lint_on MULTIDRIVEN */
  reg ckez;

  always @(posedge clk) begin
    sys_clk <= ckez;
    ckez <= cke;
  end
  always @(negedge clk) begin
    sys_clk <= 1'b0;
  end

  //bank models
  reg [15:0] bank0 [0:2**(13+9)-1];
  reg [15:0] bank1 [0:2**(13+9)-1];
  reg [15:0] bank2 [0:2**(13+9)-1];
  reg [15:0] bank3 [0:2**(13+9)-1];

  // SDRAM command signals
  `define ACTIVE 3'b001
  `define READ   3'b010
  `define WRITE  3'b011
  `define BURST_TERMINATE 3'b100
  `define LOAD_MODE_REG 3'b101
  `define NOP 3'b000
  wire cmd_active, cmd_read, cmd_write, cmd_burst_terminate, cmd_load_modereg;
  assign cmd_active = ~cs & ~ras & cas & we;
  assign cmd_read = ~cs & ras & ~cas & we;
  assign cmd_write = ~cs & ras & ~cas & ~we;
  assign cmd_burst_terminate = ~cs & ras & cas & ~we;
  assign cmd_load_modereg = ~cs & ~ras & ~cas & ~we;

  //control signals
  wire [2:0] CAS, BURST_LENGTH;
  assign CAS = mode_reg[6:4];
  assign BURST_LENGTH = mode_reg[2:0];
  wire burst_length_1 = (BURST_LENGTH == 3'b000);
  wire burst_length_2 = (BURST_LENGTH == 3'b001);
  wire burst_length_4 = (BURST_LENGTH == 3'b010);
  wire burst_length_8 = (BURST_LENGTH == 3'b011);

  // pipeline
  reg [2:0] cmd [0:3];
  reg [1:0] bank_addr [0:3];
  reg [8:0] col_addr [0:3]; //512 cols
  reg [12:0] b0_row_addr, b1_row_addr, b2_row_addr, b4_row_addr;  //8196 rows
  reg b0_active, b1_active, b2_active, b4_active;
  reg [1:0] dqm_read [0:1];  // 2 clk latency
  reg [1:0] dqm_write;
  reg [15:0] dq_write;
  initial begin
    b0_active = 1'b0;
    b1_active = 1'b0;
    b2_active = 1'b0;
    b4_active = 1'b0;
  end

  //MODE REGISTER
  reg [11:0] mode_reg;
  always @(posedge sys_clk) begin
    if (cmd_load_modereg) begin
      mode_reg <= a[11:0];
    end
  end

  //ACTIVE COMMAND
  always @(posedge sys_clk) begin
    if(cmd_active) begin
      if(ba == 2'b00) begin
        b0_row_addr <= a[12:0];
        b0_active <= 1'b1;
      end else if(ba == 2'b01) begin
        b1_row_addr <= a[12:0];
        b1_active <= 1'b1;
      end else if(ba == 2'b10) begin
        b2_row_addr <= a[12:0];
        b2_active <= 1'b1;
      end else if(ba == 2'b11) begin
        b4_row_addr <= a[12:0];
        b4_active <= 1'b1;
      end
    end
  end

  //READ/WRITE/BURST_TERMINATE COMMAND
  reg data_in_enable;  //write signal
  reg data_out_enable; //read signal
  /* verilator lint_off UNOPTFLAT */
  reg [15:0] dq_reg;
  /* verilator lint_on UNOPTFLAT */
  reg [15:0] dq_dqm;
  reg [1:0] bank;
  reg [12:0] row;
  reg [8:0] col;
  reg [8:0] burst_counter;
  initial begin
    data_in_enable = 1'b0;
    data_out_enable = 1'b0;
  end
  always @(posedge sys_clk) begin
    if(cmd_write) cmd[0] <= `WRITE;
    else cmd[0] <= cmd[1];
    if(CAS==3'd2) begin
      if(cmd_burst_terminate) begin
        cmd[1] <= `BURST_TERMINATE;
      end else if(cmd_read) begin
        cmd[1] <= `READ;
      end else begin
        cmd[1] <= cmd[2];
      end
      cmd[2] <= cmd[3];
    end else begin
      cmd[1] <= cmd[2];
      if(cmd_burst_terminate) begin
        cmd[2] <= `BURST_TERMINATE;
      end else if(cmd_read) begin
        cmd[2] <= `READ;
      end else begin
        cmd[2] <= cmd[3];
      end
    end
    cmd[3] <= `NOP;

    if(cmd_write) bank_addr[0] <= ba;
    else bank_addr[0] <= bank_addr[1];
    if(CAS==3'd2) begin
      if(cmd_read) bank_addr[1] <= ba;
      else bank_addr[1] <= bank_addr[2];
      bank_addr[2] <= bank_addr[3];
    end else begin
      bank_addr[1] <= bank_addr[2];
      if(cmd_read) bank_addr[2] <= ba;
      else bank_addr[2] <= bank_addr[3];
    end
    bank_addr[3] <= 2'b0;

    if(cmd_write) col_addr[0] <= a[8:0];
    else col_addr[0] <= col_addr[1];
    if(CAS==3'd2) begin
      if(cmd_read) col_addr[1] <= a[8:0];
      else col_addr[1] <= col_addr[2];
      col_addr[2] <= col_addr[3];
    end else begin
      if(cmd_read) col_addr[1] <= a[8:0];
      else col_addr[1] <= col_addr[2];
    end
    col_addr[3] <= 9'b0;

    dqm_read[0] <= dqm_read[1];
    dqm_read[1] <= dqm;

    dqm_write <= dqm;
    dq_write <= dq;

    // active bank check
    if(cmd_read) begin
      // check if active
      if((ba==2'b00 && b0_active==0)||(ba==2'b01 && b1_active==0)||
         (ba==2'b10 && b2_active==0)||(ba==2'b11 && b4_active==0)) begin
        $display("%m: Error! Read command on inactive bank.");
      end
    end
    if(cmd_write) begin
      if((ba==2'b00 && b0_active==0)||(ba==2'b01 && b1_active==0)||
         (ba==2'b10 && b2_active==0)||(ba==2'b11 && b4_active==0)) begin
        $display("%m: Error! Write command on inactive bank.");
      end
    end

    // data_in_enable signal for WRITE command
    if(cmd_write) begin
      data_in_enable <= 1'b1;
      burst_counter <= 0;
      bank <= ba;
      col <= a[8:0];
      case(ba)
        2'b00: row <= b0_row_addr;
        2'b01: row <= b1_row_addr;
        2'b10: row <= b2_row_addr;
        2'b11: row <= b4_row_addr;
      endcase
    end else if(cmd_read | cmd_burst_terminate) begin
      data_in_enable <= 1'b0;
    end else begin
      if(burst_length_1==1'b1) begin
        // if(burst_counter>=0) begin
        if(data_in_enable) data_in_enable <= 1'b0;
        // end
      end else if(burst_length_2==1'b1) begin
        if(burst_counter>=1) begin
          data_in_enable <= 1'b0;
        end
      end else if(burst_length_4==1'b1) begin
        if(burst_counter>=2) begin
          data_in_enable <= 1'b0;
        end
      end else if(burst_length_8==1'b1) begin
        if(burst_counter>=7) begin
          data_in_enable <= 1'b0;
        end
      end
    end

    //data_out_enable signal for READ command
    if(cmd_write || (cmd[1]==`BURST_TERMINATE)) begin
      data_out_enable <= 1'b0;
    end else if(cmd[1]==`READ) begin
      data_out_enable <= 1'b1;
      burst_counter <= 0;
      bank <= bank_addr[1];
      col <= col_addr[1];
      case(bank_addr[1])
        2'b00: row <= b0_row_addr;
        2'b01: row <= b1_row_addr;
        2'b10: row <= b2_row_addr;
        2'b11: row <= b4_row_addr;
      endcase
    end else begin
      if(burst_length_1==1'b1) begin
        // if(burst_counter>=0) begin
        if(data_out_enable) data_out_enable <= 1'b0;
        // end
      end else if(burst_length_2==1'b1) begin
        if(burst_counter>=1) begin
          data_out_enable <= 1'b0;
        end
      end else if(burst_length_4==1'b1) begin
        if(burst_counter>=2) begin
          data_out_enable <= 1'b0;
        end
      end else if(burst_length_8==1'b1) begin
        if(burst_counter>=7) begin
          data_out_enable <= 1'b0;
        end
      end
    end
    
    //burst_counter for read/write command
    if(data_in_enable | data_out_enable) begin
      burst_counter <= burst_counter + 1;
      if(burst_length_2==1'b1) begin
        col[0] <= col[0] + 1;
      end else if(burst_length_4==1'b1) begin
        col[1:0] <= col[1:0] + 1;
      end else if(burst_length_8==1'b1) begin
        col[2:0] <= col[2:0] + 1;
      end
    end
  end

  /* verilator lint_off LATCH */
  always @(*) begin
    if(data_out_enable==1'b1) begin
      case(bank)
        2'b00: dq_dqm = bank0[{row, col}];
        2'b01: dq_dqm = bank1[{row, col}];
        2'b10: dq_dqm = bank2[{row, col}];
        2'b11: dq_dqm = bank3[{row, col}];
      endcase
      /* verilator lint_off UNOPTFLAT */
      dq_reg = {dqm_read[0][0]==1'b1 ? 8'bz : dq_dqm[15:8] , dqm_read[0][0]==1'b1 ? 8'bz : dq_dqm[7:0]};
      /* verilator lint_on UNOPTFLAT */
      if(mtrace) begin
        $display("%m: Read from bank %d, row %d, col %d, data %h, mask %b", bank, row, col, dq_reg, dqm_read[0]);
      end
    end else if(data_in_enable==1'b1) begin
      dq_reg = 16'bz;
      case(bank)
        2'b00: dq_dqm = bank0[{row, col}];
        2'b01: dq_dqm = bank1[{row, col}];
        2'b10: dq_dqm = bank2[{row, col}];
        2'b11: dq_dqm = bank3[{row, col}];
      endcase
      if(dqm_write[0] == 1'b0) begin
        dq_dqm[7:0] = dq_write[7:0];
        if(mtrace) $display("%m:dqm[0]==0, dm_dqm[7:0] %h = dq[7:0] %h", dq_dqm[7:0], dq_write[7:0]);
      end
      if(dqm_write[1] == 1'b0) begin
        dq_dqm[15:8] = dq_write[15:8];
        if(mtrace) $display("%m:dqm[1]==0, dm_dqm[15:8] %h = dq[15:8] %h", dq_dqm[15:8], dq_write[15:8]);
      end
    end else dq_reg = 16'bz;

  end
  /* verilator lint_on LATCH */

  always @(posedge sys_clk) begin
    if(data_in_enable==1'b1) begin
      case(bank)
        2'b00: bank0[{row, col}] <= dq_dqm;
        2'b01: bank1[{row, col}] <= dq_dqm;
        2'b10: bank2[{row, col}] <= dq_dqm;
        2'b11: bank3[{row, col}] <= dq_dqm;
      endcase
      if(mtrace) begin
        $display("%m: Write to bank %d, row %d, col %d, dq %h, dq_dqm %h, mask %b", bank, row, col, dq_write, dq_dqm, dqm_write);
      end
    end
  end

  assign dq = data_out_enable==1'b1 ? dq_reg : 16'bz;

endmodule
