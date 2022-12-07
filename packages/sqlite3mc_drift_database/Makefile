build-all-libs:
	cd ./wasm/assets/sqlite3mc-wasm; \
	mkdir -p build; \
	cd ./build; \
    cmake ../ --toolchain ../toolchain.cmake; \
    make full; \
	@# Help: build amalgamation




help:
	@printf "%-30s %s\n" "Target" "Description"
	@printf "%-30s %s\n" "------" "-----------"
	@make -pqR : 2>/dev/null \
		| awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' \
		| sort \
		| egrep -v -e '^[^[:alnum:]]' -e '^$@$$' \
		| xargs -I _ sh -c 'printf "%-30s " _; make _ -nB | (grep -i "^# Help:" || echo "") | tail -1 | sed "s/^# Help: //g"'



