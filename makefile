make:
	rgbasm -o pong.o pong.asm
	rgblink -n pong.sym -o pong.gb pong.o
	rgbfix -v -p 0xFF pong.gb

run:
	open pong.gb

clean:
	rm pong.gb pong.o pong.sym