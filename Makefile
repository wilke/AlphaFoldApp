TOP_DIR = ../..
LIBDIRS = -L$(TOP_DIR)/lib
EXECUTABLE = App-AlphaFold

include $(TOP_DIR)/tools/Makefile.common

# Auto-generated service module
# To build: make
# To test: make test
# To install: make install

.PHONY: test
test:
	@echo "Testing AlphaFold service..."
	@if [ -f "tests/test_case_1/params.json" ]; then \
		echo "Running basic test..."; \
		./App-AlphaFold xx app_specs/AlphaFold.json tests/test_case_1/params.json; \
	else \
		echo "No test cases found"; \
	fi

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make        - Build the service"
	@echo "  make test   - Run test cases"
	@echo "  make install - Install the service"
	@echo "  make clean  - Clean build artifacts"
	@echo ""
	@echo "Usage: App-AlphaFold --help"
