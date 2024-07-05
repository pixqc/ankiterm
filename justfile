dev:
    cd src/ && ls | entr -r sh -c 'cd .. && zig build && ./zig-out/bin/ankiterm'

sandbox:
    cd src/ && ls | entr -r sh -c 'cd .. && zig build && SANDBOX=1 ./zig-out/bin/ankiterm'
