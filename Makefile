REBAR := ./rebar

.PHONY: all doc clean test dialyzer

all: compile doc

compile:
	$(REBAR) get-deps compile

doc:
	$(REBAR) doc skip_deps=true

test:
	$(REBAR) eunit skip_deps=true

dialyzer:
	$(REBAR) analyze

release: all dialyzer test
	$(REBAR) release

clean:
	$(REBAR) clean
