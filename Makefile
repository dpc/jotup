.POSIX:

all: jotup docs
	cargo build --workspace

jotup: target/release/jotup
	cp $< $@

target/release/jotup:
	cargo build --release

.PHONY:
docs:
	RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --workspace

.PHONY: lint
lint:
	cargo clippy -- -D warnings
	cargo clippy --no-default-features -- -D warnings
	cargo clippy --all-features -- -D warnings
	cargo check --all
	cargo fmt --all -- --check

.PHONY: check
check:
	cargo test --workspace
	cargo test --workspace --no-default-features

.PHONY: enable-git-hooks
enable-git-hooks:
	git config --local core.hooksPath contrib/

.PHONY: test_html_ut
test_html_ut:
	git submodule update --init modules/djot.js
	for f in $$(find modules/djot.js/test -name '*.test' | xargs basename -a); do \
		ln -fs ../../../modules/djot.js/test/$$f tests/html-ut/ut/djot_js_$$f; \
	done
	cargo test -p test-html-ut
	cargo test -p test-html-ut -- --ignored 2>/dev/null | grep -qE 'test result: .* 0 passed'

.PHONY: test_html_ref
test_html_ref:
	git submodule update --init modules/djot.js
	for f in $$(find modules/djot.js/bench -name '*.dj' | xargs basename -a); do \
		dst=$$(echo $$f | sed 's/-/_/g'); \
		ln -fs ../../modules/djot.js/bench/$$f tests/html-ref/$$dst; \
	done
	cargo test -p test-html-ref
	cargo test -p test-html-ut -- --ignored 2>/dev/null | grep -qE 'test result: .* 0 passed'

.PHONY: bench
bench:
	git submodule update --init modules/djot.js
	for f in $$(find modules/djot.js/bench -name '*.dj' | xargs basename -a); do \
		dst=$$(echo $$f | sed 's/-/_/g'); \
		ln -fs ../../modules/djot.js/bench/$$f bench/input/$$dst; \
	done

clean:
	cargo clean
	git submodule deinit -f --all
	find tests -type l -path 'tests/html-ut/ut/*.test' -print0 | xargs -0 rm -f
	(cd tests/html-ut && make clean)
	rm -f tests/html-ref/*.dj
	(cd tests/html-ref && make clean)
	find bench -type l -path 'bench/*.dj' -print0 | xargs -0 rm -f
	(cd examples/jotup_wasm && make clean)
