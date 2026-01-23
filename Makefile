.PHONY: llscheck luacheck stylua

llscheck:
	llscheck --configpath .luarc.json .

luacheck:
	luacheck lua

stylua:
	stylua --color always --check lua

.PHONY: check
check: llscheck luacheck stylua

.PHONY: clean
clean:
	cargo clean
	rm ./go/libkubectl_go.a
	rm ./go/libkubectl_go.h

.PHONY: build_go
build_go:
	go -C go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o libkubectl_go.a

.PHONY: build_dev
build_dev: build_go
ifeq ($(shell uname -s),Darwin)
	RUSTFLAGS="-C link-arg=-undefined -C link-arg=dynamic_lookup -C link-arg=-Wl,-dead_strip --cfg tokio_unstable" cargo build --features telemetry
else
	RUSTFLAGS="--cfg tokio_unstable" cargo build --features telemetry
endif

.PHONY: build_release
build_release: build_go
	@cargo build --release

.PHONY: build_windows
build_windows: build_go
	cargo build --release --target x86_64-pc-windows-gnu

.PHONY: build
build: build_go
	cargo build --release
