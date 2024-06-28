.PHONY: dev
dev:
	cd src/ && ls | entr -r zig run main.zig

test:
	cd src/ && ls | entr -r zig test main.zig

