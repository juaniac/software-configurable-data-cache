# Usage
all:
	@echo "Usage: make <module_name>"
	@echo "Example: make ramDmaCi"

define find_deps
  $(shell awk '/^\s*module\s+[a-zA-Z0-9_]+/ {print $$2".v"}' *.v | grep -v "^$(1).v$$" | xargs -I {} find . -name "{}" 2>/dev/null)
endef

%:
	$(eval MODULE := $@)
	$(eval SRC := $(MODULE).v)
	$(eval DEPS := $(call find_deps, $(MODULE)))
	$(eval TB := $(MODULE)_tb.v)
	$(eval OUT_EXE := out)

# Ensure testbench exists
	@if [ ! -f "$(TB)" ]; then echo "Error: Testbench $(TB) not found!"; exit 1; fi

	$(eval TB_MODULE := $(shell grep -m 1 "module" $(TB) | sed -e 's/module\s\+\([a-zA-Z0-9_]\+\).*/\1/'))
	
# Compile with the testbench module specified
	$ iverilog -s $(TB_MODULE) -o $(OUT_EXE) $(DEPS) $(TB)

# Run
	./$(OUT_EXE)

clean:
	rm -f out *.vcd

.PHONY: all clean