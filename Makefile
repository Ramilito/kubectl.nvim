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
	rm ./go/libkubedescribe.a
	rm ./go/libkubedescribe.h

.PHONY: build
build:
	go -C go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o libkubedescribe.a
	cargo build --release
