# Testbench
A System Verilog testbench used to find faults in a black box calculator design.

Makefile - contains make commands to compile and run the tests in top.sv on the calculator design
top.sv - System Verilog testbench for the calculator design
TA_calc_golden.svp - reference calculator with no faults (encrypted)
TA_calc_broken.svp - calculator with faults
faults.txt - list of found faults
