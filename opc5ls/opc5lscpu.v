module opc5lscpu( input[15:0] din, output[15:0] dout, output[15:0] address, output rnw, input clk, input reset_b, input int_b );
    parameter MOV=4'h0,AND=4'h1,OR=4'h2,XOR=4'h3,ADD=4'h4,ADC=4'h5,STO=4'h6,LD=4'h7,ROR=4'h8,NOT=4'h9,SUB=4'hA,SBC=4'hB,CMP=4'hC,CMPC=4'hD,BSWP=4'hE,PSR=4'hF,RTI=17'h100FF;
    parameter FETCH0=3'h0, FETCH1=3'h1, EA_ED=3'h2, RDMEM=3'h3, EXEC=3'h4, WRMEM=3'h5, INT=3'h6 ;
    parameter P0=15, P1=14, P2=13, IRLEN=12, IRLD=16, IRSTO=17, IRGETPSR=18, IRPUTPSR=19, IRCMP=20, INT_VECTOR=16'h0002;
    reg [15:0] OR_q, PC_q, PCI_q, result;
    reg [20:0] IR_q; (* RAM_STYLE="DISTRIBUTED" *)
    reg [15:0] dprf_q[15:0];
    reg [2:0]  FSM_q, PSRI_q; // Only need to store S,C,Z because SWI will be cleared and I must have been 1 on interrupt
    reg        SWI_q, I_q, C_q, Z_q, S_q, zero, carry, sign, swi, isrv_q, enable_int;
    wire predicate = IR_q[P2] ^ (IR_q[P1] ? (IR_q[P0] ? S_q : Z_q) : (IR_q[P0] ? C_q : 1));
    wire predicate_din = din[P2] ^ (din[P1] ? (din[P0] ? S_q : Z_q) : (din[P0] ? C_q : 1));
    wire [15:0] dprf_dout_p2= (IR_q[7:4]==4'hF) ? PC_q: {16{(IR_q[7:4]!=4'h0)}} & dprf_q[IR_q[7:4]];// Port 2 always reads source reg
    wire [15:0] dprf_dout= (IR_q[3:0]==4'hF) ? PC_q: {16{(IR_q[3:0]!=4'h0)}} & dprf_q[IR_q[3:0]];   // Port 1 always reads dest reg
    wire [15:0] operand = (IR_q[IRLEN]||IR_q[IRLD]) ? OR_q : dprf_dout_p2;                         // For one word instructions operand comes from dprf
    assign     {rnw, dout, address} = { !(FSM_q==WRMEM), dprf_dout, ( FSM_q==WRMEM || FSM_q == RDMEM)? OR_q : PC_q };
    always @( * )
        begin
            case (IR_q[11:8])     // no real need for STO entry but include it so all instructions are covered, no need for default
            LD, MOV, PSR, STO   : {carry, result} = {C_q, (IR_q[IRGETPSR])? {13'b0, S_q, C_q, Z_q}: operand} ;
            AND, OR             : {carry, result} = {C_q, (IR_q[8])? (dprf_dout & operand) : (dprf_dout | operand)};
            ADD, ADC            : {carry, result} = dprf_dout + operand + (IR_q[8] & C_q);
            SUB, SBC, CMP, CMPC : {carry, result} = dprf_dout + (~operand & 16'hFFFF) + ((IR_q[8])? C_q: 1);
            XOR, BSWP           : {carry, result} = {C_q, (!IR_q[11])? (dprf_dout ^ operand): {operand[7:0], operand[15:8]}};
            NOT, ROR            : {result, carry} = (IR_q[8]) ? {~operand, C_q} : {C_q, operand} ;
            endcase // case ( IR_q )
            {swi,enable_int,sign,carry,zero} = (IR_q[IRPUTPSR])? operand[4:0]: (IR_q[3:0]!=4'hF)? {SWI_q,I_q, result[15], carry,!(|result)}: {SWI_q,I_q,S_q,C_q,Z_q} ; // don't update flags PC dest operations
        end
    always @(posedge clk or negedge reset_b )
        if (!reset_b)
            FSM_q <= FETCH0;
        else
            case (FSM_q)
            FETCH0 : FSM_q <= (din[IRLEN]) ? FETCH1 : (!predicate_din) ? FETCH0 : ((din[11:8]==LD) || (din[11:8]==STO)) ? EA_ED : EXEC;
            FETCH1 : FSM_q <= (!predicate )? FETCH0: ((IR_q[3:0]!=0) || (IR_q[IRLD]) || IR_q[IRSTO]) ? EA_ED : EXEC;
            EA_ED  : FSM_q <= (!predicate )? FETCH0: (IR_q[IRLD]) ? RDMEM : (IR_q[IRSTO]) ? WRMEM : EXEC;
            RDMEM  : FSM_q <= EXEC;
            EXEC   : FSM_q <= ((!int_b || SWI_q) & I_q & !isrv_q ) ? INT : (IR_q[3:0]==4'hF)? FETCH0: (din[IRLEN]) ? FETCH1 : // go to fetch0 if PC or PSR affected by exec
                            ((din[11:8]==LD) || (din[11:8]==STO) ) ? EA_ED :                                       // load/store have to go via EA_ED
                            (din[P2] ^ (din[P1] ? (din[P0] ? sign : zero): (din[P0] ? carry : 1))) ? EXEC : EA_ED; // short cut to exec on all predicates
                            //(din[15:13]==3'b000)? EXEC : EA_ED;                                                  // or short cut on always only
            WRMEM  : FSM_q <= ((!int_b || SWI_q) & I_q & !isrv_q ) ? INT : FETCH0;
            default: FSM_q <= FETCH0;
            endcase // case (FSM_q)
    always @(posedge clk)
        OR_q <= (FSM_q == FETCH0 || FSM_q==EXEC)? 16'b0 : (FSM_q==EA_ED) ? dprf_dout_p2 + OR_q : din;
    always @(posedge clk or negedge reset_b)
        if ( !reset_b)
            { PC_q, PCI_q, isrv_q, PSRI_q, I_q, SWI_q, S_q, C_q, Z_q} <= 41'b0;
        else if ( FSM_q == INT )
            { PC_q, PCI_q, isrv_q, PSRI_q } <= { INT_VECTOR, PC_q, 1'b1, S_q, C_q, Z_q} ;
        else if ( FSM_q == FETCH0 || FSM_q == FETCH1 )
            PC_q <= PC_q + 1;
        else if ( FSM_q == EXEC )
            begin
                PC_q <= ( {isrv_q,IR_q[15:0]}==RTI)? PCI_q : (IR_q[3:0]==4'hF) ? result : ((!int_b || SWI_q) & I_q & !isrv_q )? PC_q: PC_q + 1 ; //Dont incr PC if taking interrupt
                {isrv_q, SWI_q, I_q, S_q, C_q, Z_q} <= ({isrv_q,IR_q[15:0]} ==RTI)? {3'b001,PSRI_q}: {isrv_q, swi, enable_int, sign, carry, zero};
            end
    always @ (posedge clk)
        if ( FSM_q == EXEC )
            dprf_q[(IR_q[IRCMP])?4'b0:IR_q[3:0]] <= result ;
    always @ (posedge clk)
        if ( FSM_q == FETCH0 || FSM_q == EXEC)
            IR_q <= { ((din[11:8]==CMP)||(din[11:8]==CMPC)), {2{(din[11:8]==PSR)}} & {(din[3:0]==4'h0),(din[7:4]==4'b0)}, (din[11:8]==STO),(din[11:8]==LD), din};
endmodule
