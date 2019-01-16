GCC=g++
SRC=test.cpp

all: $(SRC)
	$(GCC) $< -shared -fPIC -Wl,-soname,libtest.so.217 -o libtest.so
	$(GCC) $< -static -o static.elf
	$(GCC) $< -fPIE -pie -o pie.elf
	$(GCC) $< -no-pie -o nopie.elf
	$(GCC) $< -Wl,--disable-new-dtags -Wl,-rpath=/not_exists:/lib:/pusheen/is/fat -o rpath.elf
	$(GCC) $< -Wl,--enable-new-dtags -Wl,-rpath=/not_exists:/lib:/pusheen/is/fat -o runpath.elf
	$(GCC) $< -fPIE -pie -m32 -o pie32.elf

clean:
	$(RM) *.elf *.so
