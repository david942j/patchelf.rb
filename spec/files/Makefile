all: test.cpp
	g++ -shared -fPIC -Wl,-soname,libtest.so.217 -o libtest.so test.cpp
	g++ -static -o static.elf test.cpp
	g++ -fPIE -pie -o pie.elf test.cpp
	g++ -no-pie -o nopie.elf test.cpp

clean:
	$(RM) *.elf *.so
