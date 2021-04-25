# release by ui-jong Lee
# USING EXAMPLE
# After writing your Verilog HDL code, type this 
# $ make vmodule=${YOUR_VERILOG_MODULE_NAME}

SHELL:=/bin/bash
vmodule?=YOUR_VERILOG_MODULE_NAME
WORK_PATH=$(shell pwd)
OUT_PATH="$(shell pwd)/vlib"
WARNINGS=0
ERRORS=0

ifneq ($(words $(CURDIR)),1)
 $(error Unsupported: GNU Make cannot build in directories containing spaces, build elsewhere: '$(CURDIR)')
endif

vcc=$(shell which verilator)

ifneq ($(words $(vcc)),1)
 $(error Cannot find verilator binary)
endif

# top file search & convert absolute path
top=$(subst ./,$(shell pwd)/,$(shell find -name "${vmodule}.v"))

ifneq ($(words $(top)),1)
 $(error $(words $(top)) file containing your module was found.)
endif

# search all subdirectory & convert absolute path
inc_path=$(sort $(dir $(subst ./,-I$(shell pwd)/,$(wildcard ./RTL/*/))))

vcc_top_prefix_flags=--top-module ${vmodule}

vcc_prefix_flags=--cc			\
    --compiler gcc				\
    --Mdir ${OUT_PATH}			\
    --trace						\
    --trace-max-width 550		\
    --trace-max-array 64		

vcc_suffix_flags=&& cd ${OUT_PATH} && make -f V${vmodule}.mk && cd ${WORK_PATH}

target:	
	@echo " >> Run Verilator << "
	@mkdir -vp ${OUT_PATH}
	${vcc} ${vcc_prefix_flags} ${inc_path} ${vcc_top_prefix_flags} ${top} ${vcc_suffix_flags}
	@ln -fs ${OUT_PATH}/V${vmodule}__ALL.a ${OUT_PATH}/lib${vmodule}.a
	@echo " >> Verilator build finished ${OUT_PATH}/lib${vmodule}.a <<"


clean:
	rm -rf ${OUT_PATH} || true

