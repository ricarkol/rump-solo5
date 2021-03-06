default: build

all: build

.PHONY: submodules
submodules:
	git submodule update --init

build: build/ukvm-bin build/nginx.ukvm

SOLO5_OBJ=solo5/kernel/ukvm/solo5.o

solo5: $(SOLO5_OBJ) solo5/ukvm/ukvm-bin

$(SOLO5_OBJ):
	UKVM_STATIC=yes make -C solo5 ukvm

solo5/ukvm/ukvm-bin:
	UKVM_STATIC=yes make -C solo5/ukvm

RUMP_SOLO5_X86_64=rumprun/rumprun-solo5/rumprun-x86_64
RUMP_SOLO5_UKVM=$(RUMP_SOLO5_X86_64)/lib/rumprun-solo5/libsolo5_ukvm.a
RUMP_LIBC=$(RUMP_SOLO5_X86_64)/lib/libc.a

rumprun: $(RUMP_SOLO5_UKVM) $(RUMP_LIBC)

$(RUMP_LIBC):
	cd rumprun && git submodule update --init
	make -C rumprun build

$(RUMP_SOLO5_UKVM): $(SOLO5_OBJ)
	install -m 664 -D $(SOLO5_OBJ) $@

rumprun-packages/config.mk:
	install -m 664 -D rumprun-packages/config.mk.dist $@

SHELL := /bin/bash

rumprun-packages/nginx/bin/nginx.ukvm: $(RUMP_SOLO5_UKVM) $(RUMP_LIBC) rumprun-packages/config.mk
	source rumprun/obj/config-PATH.sh && make -C rumprun-packages/nginx all
	source rumprun/obj/config-PATH.sh && make -C rumprun-packages/nginx bin/nginx.ukvm

build/nginx.ukvm: rumprun-packages/nginx/bin/nginx.ukvm
	install -m 775 -D $< $@

build/ukvm-bin: solo5/ukvm/ukvm-bin
	install -m 775 -D solo5/ukvm/ukvm-bin $@

tap:
	sudo ip tuntap add tap100 mode tap || true
	sudo ip addr add 10.0.0.1/24 dev tap100 || true
	sudo ip link set dev tap100 up || true

test_nginx: tap
	genisoimage -l -r -o data.iso rumprun-packages/nginx/data
	./build/ukvm-bin --disk=data.iso --net=tap100 build/nginx.ukvm '{"cmdline":"bin/nginx.seccomp -c /data/conf/nginx.conf","net":{"if":"ukvmif0","cloner":"True","type":"inet","method":"static","addr":"10.0.0.2","mask":"16"},"blk":{"source":"etfs","path":"/dev/ld0a","fstype":"blk","mountpoint":"/data"}}'

.PHONY: clean distclean clean_solo5 clean_rump
clean:
	rm -rf build/

distclean: clean_solo5 clean_rump
	make clean -C rumprun-packages/nginx

clean_solo5:
	make clean -C solo5

clean_rump:
	rm -f $(RUMP_SOLO5_UKVM) $(RUMP_LIBC)
	make clean -C rumprun
