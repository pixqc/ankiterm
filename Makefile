.PHONY: dev
dev:
	cd src/ && ls | entr -r zig run main.zig

