`timescale 1ns / 1ns

module opctb();
  reg [7:0] mem [ 4095:0 ];
  reg clk, reset_b;

  wire [11:0] addr;
  wire rnw ;
  wire ceb = 1'b0;
  wire oeb = !rnw;
  wire [7:0]  data = ( !ceb & rnw & !oeb ) ? mem[ addr ] : 8'bz ;

  // OPC CPU instantiation
  opccpu  dut0_u (.address(addr), .data(data), .rnw(rnw), .clk(clk), .reset_b(reset_b));

  initial
    begin
      $dumpvars;
      $readmemh("test.hex", mem); // Problems with readmemb - use readmemh for now
      clk = 0;
      reset_b = 0;
      #10005 reset_b = 1;
      #500000 $finish;
    end

  // Simple negedge synchronous memory to avoid messing with delays initially
  always @ (negedge clk)
    if (!rnw && !ceb && oeb && reset_b)
      mem[addr] <= data;

  always
    #500 clk = !clk;

  // Always stop simulation on encountering the halt pseudo instruction
  always @ (negedge clk)
    if (dut0_u.IR_q==4'h7)
      begin
        $display("Simulation terminated with halt instruction at time", $time);
        $finish;
      end
endmodule