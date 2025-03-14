.PHONY: llscheck luacheck stylua

llscheck:
	llscheck --configpath .luarc.json .

luacheck:
	luacheck lua

stylua:
	stylua lua

.PHONY: build
build:
	go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o libkubedescribe.a
	cargo build --release
