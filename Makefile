# 18-341 Project 4
# Fall 2014

# ========================================================
#
#    ADD YOUR FILES HERE
#
#    For example:
#      STUDENT_FILES=top.sv assertions.sv inputs.sv
#
# ========================================================

STUDENT_FILES=top.sv

# ========================================================
#
#    DON'T CHANGE ANYTHING BELOW HERE
#
# ========================================================

VCSFLAGS=-sverilog -debug
COVFLAGS=-sverilog -ntb_opts dtm

golden: $(STUDENT_FILES) TA_calc_golden.svp
		vcs $(VCSFLAGS) $^

fgolden: $(STUDENT_FILES) TA_calc_golden.svp
		 vcs $(COVFLAGS) $^

broken: $(STUDENT_FILES) TA_calc_broken.svp
		vcs $(VCSFLAGS) $^

fbroken: $(STUDENT_FILES) TA_calc_broken.svp
		 vcs $(COVFLAGS) $^
