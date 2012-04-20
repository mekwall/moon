compile:
	./node_modules/iced-coffee-script/bin/coffee -bw -o ./lib -c ./src

MOCHA_TESTS := $(shell find test/ -name '*.mocha.coffee')
MOCHA := ./node_modules/mocha/bin/mocha
OUT_FILE = "test-output.tmp"

g = "."

test-mocha:
	@NODE_ENV=test $(MOCHA) \
		--grep "$(g)" \
		$(MOCHA_TESTS) | tee $(OUT_FILE)

test: test-mocha