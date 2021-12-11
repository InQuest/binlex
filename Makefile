.PHONY: docs

threads=1

all:
	mkdir -p build/
	cd build/ && \
		cmake -S ../ -B . && \
		make -j ${threads}

docs:
	mkdir -p build/docs/
	(cat Doxyfile; echo "NUM_PROC_THREADS=${threads}") | doxygen -

docs-update:
	rm -rf docs/html/
	cp -r build/docs/html/ docs/

install:
	cp build/binlex /usr/bin/
	cp build/blyara /usr/bin/
	cp build/blhash /usr/bin/

uninstall:
	rm -f /usr/bin/binlex
	rm -f /usr/bin/blyara
	rm -f /usr/bin/blhash

traits: check-parameter-source check-parameter-dest check-parameter-type check-parameter-format check-parameter-arch
	@echo "[-] building traits..."
	@find ${source} -type f | while read i; do \
		mkdir -p ${dest}/${type}/${format}/${arch}/; \
		filename=`basename $${i}`; \
		echo "binlex -m ${format}:${arch} -i $${i} | jq '.[] | .trait' > ${dest}/${type}/${format}/${arch}/$${filename}.traits"; \
	done | parallel -u --progress -j ${threads} {}
	@echo "[*] trait build complete"

traits-combine: check-parameter-source check-parameter-dest check-parameter-type check-parameter-format check-parameter-arch
	@find ${source}/${type}/${format}/${arch}/ -type f -name "*.traits" | while read i; do \
		echo "cat $${i} && rm -f $${i}"; \
	done | parallel --halt 1 -u -j ${threads} {} | sort | uniq > ${dest}/${type}.${format}.${arch}.traits
	@rm -rf dist/${type}/

traits-clean: check-parameter-remove check-parameter-source check-parameter-dest
	awk 'NR==FNR{a[$$0];next} !($$0 in a)' ${remove} ${source} | sort | uniq | grep -Pv '^(\?\?\s?)+$$' > ${dest}

check-parameter-remove:
	@if [ -z ${remove} ]; then \
		echo "[x] missing remove parameter"; \
		exit 1; \
	fi

check-parameter-source:
	@if [ -z ${source} ]; then \
		echo "[x] missing source parameter"; \
		exit 1; \
	fi

check-parameter-dest:
	@if [ -z ${dest} ]; then \
		echo "[x] missing dest parameter"; \
		exit 1; \
	fi

check-parameter-type:
	@if [ -z ${type} ]; then \
		echo "[x] missing type parameter"; \
		exit 1; \
	fi

check-parameter-arch:
	@if [ -z ${arch} ]; then \
		echo "[x] missing arch parameter"; \
		exit 1; \
	fi

check-parameter-format:
	@if [ -z ${format} ]; then \
		echo "[x] missing format parameter"; \
		exit 1; \
	fi

clean: clean-dist
	rm -rf build/

clean-dist:
	rm -rf dist/
