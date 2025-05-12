.PHONY: llscheck luacheck stylua

llscheck:
	llscheck --configpath .luarc.json .

luacheck:
	luacheck lua

stylua:
	stylua lua

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
	cargo build --features telemetry

.PHONY: build
build: build_go
	cargo build --release
