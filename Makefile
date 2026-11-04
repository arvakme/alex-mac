.PHONY: build verify test guard dmg
build:
	python3 scripts/build.py

test:
	xcrun swift test

guard:
	python3 scripts/guard.py

verify: guard test

dmg:
	python3 scripts/package.py
