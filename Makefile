# Moon.js Makefile

compile:
	./node_modules/iced-coffee-script/bin/coffee -b -o ./lib -c ./src

MOCHA_TESTS := $(shell find test/ -name '*.mocha.coffee')
MOCHA := ./node_modules/mocha/bin/mocha --require should --require iced-coffee-script
OUT_FILE = "test-output.tmp"

g = "."

test-mocha:
	@NODE_ENV=testing $(MOCHA) \
		--grep "$(g)" \
		$(MOCHA_TESTS) | tee $(OUT_FILE)

test: test-mocha

.PHONY: test