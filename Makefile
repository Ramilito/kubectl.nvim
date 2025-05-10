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

.PHONY: build
build:
	go -C go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o libkubectl_go.a
	cargo build --release
