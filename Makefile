.PHONY: dev
dev:
	cd src/ && ls | entr -r sh -c 'cd .. && zig build && ./zig-out/bin/ankiterm'

playground:
	zig build && PLAYGROUND=1 ./zig-out/bin/ankiterm init
