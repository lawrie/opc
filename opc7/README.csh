#!/bin/tcsh -f
# Remove non primary data files
pushd tests
rm -rf *~ *sim *trace *vcd *dump `ls -1 | egrep -v '(\.v$|\.csh|\.ucf|\.py|\.s$|spartan|xc95|opc7system|opc7copro|Make*|stdin)'`

if ( $#argv > 0 ) then
    if ( $argv[1] == "clean" ) exit
endif

#Check for pypy3
pypy3 --version > /dev/null
if ( $status) then
    set pyexec = python3
else
    set pyexec = pypy3
endif

set assembler = ../opc7asm.py
#set assembler = ../opc7byteasm.py

set testlist = ( string testpsr )
set testlist = ( bigsieve  davefib davefib_int e-spigot-rev  fib hello math32  nqueens pi-spigot-rev  robfib sieve )
set testlist = ( pi-spigot-rev )

set numtests = 0
set fails = 0
foreach test ( $testlist )
    @ numtests ++ 
    echo ""
    echo "Running Test $test"
    # Assemble the test
    python3 ${assembler} ${test}.s ${test}.hex >  ${test}.lst
    
    ${pyexec} ../opc7emu.py ${test}.hex ${test}.dump  | tee  ${test}.trace | python3 ../../utils/show_stdout.py -7 | tee ${test}.emu.stdout
    # Test bench expects the hex file to be called 'test.hex'
    cp ${test}.hex test.hex
    # Run icarus verilog to compile the testbench only if there is no stdin file
    echo "Simulating Test $test"    
    iverilog -D_simulation=1   -D_dumpvcd=1 ../opc7tb.v ../opc7cpu.v
    # -D_dumpvcd=1        
    ./a.out > ${test}.sim
    # Save the results
    if ( -e dump.vcd) then
        mv dump.vcd ${test}.vcd
    endif            
    mv test.vdump ${test}.vdump
    python3 ../../utils/show_stdout.py -7 -f ${test}.sim >  ${test}.sim.stdout
    diff -s ${test}.*.stdout
    if ( $status != 0 ) then
        echo "FAIL - simulation doesn't match emulation result"
        @ fails++
    endif

    gzip *sim *trace &
end
wait

if ( $fails == 0 ) then
    echo "P A S S  - all " $numtests " test matched between simulation and emulation"
else
    echo "F A I L - " $fails " tests out of " $numtests " had mismatches between simulation and emulation"
endif
