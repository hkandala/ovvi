SHELL := /bin/bash -eo pipefail
.PHONY: setup format lint web build build-tests test e2e vm-e2e run app dmg install icons

DERIVED_DATA ?= .build/DerivedData
XCODEBUILD := xcodebuild -project Ovvi.xcodeproj -scheme Ovvi -derivedDataPath $(DERIVED_DATA)
MAC := -destination 'platform=macOS,arch=$(shell uname -m)'
comma := ,
# `git rebase -x` in a worktree exports GIT_DIR: the tests' own git repos would write to this one.
unexport GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# Swift's warnings-as-errors leaves some concurrency warnings as warnings: any warning in our own sources fails. Matched
# by the path in the repo, since the compiler prints a symlinked path (/tmp) where CURDIR is the real one; the warned
# files are touched so the next build compiles them again and fails again (Xcode does not replay warnings).
NOWARN := | awk '{ print } /(^|\/)(Ovvi|OvviUITests|Packages)\/[^:]*:[0-9]+:[0-9]+: warning: / { w = 1; \
	split($$0, at, ":"); warned[at[1]] } END { for (f in warned) system("touch -c \"" f "\""); exit w }'
BEAUTIFY := $(if $(shell command -v xcbeautify),| xcbeautify $(if $(CI),--renderer github-actions))

setup:
	brew bundle
	git config core.hooksPath .githooks

# Needs Pillow, which setup does not install.
icons:
	python3 scripts/app-icon.py

format:
	swiftlint lint --fix --quiet
	swiftformat .

lint:
	swiftformat --lint .
	swiftlint lint --strict --quiet
	@if git grep -nwE 'p[k]ill|kill[a]ll' -- . ':!docs' ':!playbook' ':!resources'; then \
		echo 'No pattern kills: kill the exact pids you started'; exit 1; fi

PLUGINS := explorer git template
web: web/node_modules/.package-lock.json $(PLUGINS:%=plugins/%/node_modules/.package-lock.json)
	rm -rf .build/web
	mkdir -p plugins/node_modules/@ovvi && ln -sfn ../../../web/ovvi plugins/node_modules/@ovvi/plugin-api
	for id in $(PLUGINS); do npm --prefix plugins/$$id run --silent check && npm --prefix plugins/$$id run --silent build \
		|| exit 1; done
	mkdir -p .build/web/defaults .build/web/plugin-api
	rsync -a --exclude node_modules --exclude dist plugins/explorer plugins/git .build/web/defaults/
	rsync -a --exclude node_modules --exclude dist plugins/template .build/web/
	web/node_modules/.bin/tsc -p web/ovvi
	web/node_modules/.bin/esbuild web/ovvi/runtime.ts --bundle --format=esm --minify --target=safari18 \
		--log-level=warning --outfile=.build/web/ovvi.js
	cp web/ovvi/card.css .build/web/
	cp web/ovvi/ovvi.d.ts web/ovvi/package.json .build/web/plugin-api/

plugins/%/node_modules/.package-lock.json: plugins/%/package-lock.json
	npm ci --prefix plugins/$* --no-audit --no-fund

web/node_modules/.package-lock.json: web/package-lock.json
	npm ci --prefix web --no-audit --no-fund

build: web
	$(XCODEBUILD) $(MAC) build $(NOWARN) $(BEAUTIFY)

build-tests: web
	$(XCODEBUILD) $(MAC) build-for-testing $(NOWARN) $(BEAUTIFY)

test:
	swift test --package-path Packages/HerdrKit --scratch-path $(DERIVED_DATA)/HerdrKit
	python3 -c 'import pathlib, sys; texts = pathlib.Path("Ovvi/Acknowledgements.txt").read_text(); \
		sys.exit([f"{f} is not in Ovvi/Acknowledgements.txt" for f in pathlib.Path("resources/icons/licenses").iterdir() \
			if f.read_text().strip() not in texts] or None)'
	python3 scripts/check-settings.py
	python3 -c 'import pathlib, sys; sys.exit("```sh\n" + pathlib.Path("Ovvi/Agent/ovvi.sh").read_text() + "```" not in \
		pathlib.Path("docs/content/docs/agent-control/cli.mdx").read_text() and "cli.mdx: The script differs from Ovvi/Agent/ovvi.sh")'

# ONLY=OvviUITests/OvviUITests/testA,OvviUITests/OvviUITests/testB runs just those.
# SHARD=i/n runs shard i (0-based) of n, split by the tests' measured times (scripts/shard.py, scripts/test-times.tsv).
# Without ONLY, the ON_DEMAND tests (minutes in all) are left out; ON_DEMAND_ONLY=1 runs only them.
ON_DEMAND := testHundredsOfPanesStayQuick testOverviewOfManyTabsStaysBounded testMemoryAndCPUOverManyTabs \
	testOverviewCostsAndLetsGoAfter testSessionSwipeIntoManyTabsDrawsThemWithTheSidebar \
	testATabComesIntoViewWithoutAFlicker testACardNeverShowsTheOverviewsSmallSnapshot \
	testScenesGlassDark testScenesGlassLight testScenesClassicDark testScenesClassicLight \
	testKeptCardsCost testManyKeptCardsCost testSettingsScenes testStateScenes testNewWindowScenes testEmptySessionScenes testSplitsKeepTheDisplayRate testSplitsMoveEachCardOnceToItsPlace \
	testHundredsOfSpacesKeepTheSidebarQuick testWebCardsDrawAgainAfterTheGPUProcessHangs testWelcomeFilm
ifdef ON_DEMAND_ONLY
SHARD ?= 0/1
endif
ifdef SHARD
ONLY := $(shell scripts/shard.py $(SHARD) $(if $(ON_DEMAND_ONLY),--on-demand) $(ON_DEMAND))
# An empty list would run every test.
$(if $(ONLY),,$(error no tests for SHARD=$(SHARD)))
endif
# PREBUILT=1 runs the tests of an earlier make build-tests (CI's build job) without building them again.
E2E = $(if $(PREBUILT),xcodebuild test-without-building -xctestrun $(firstword $(wildcard $(DERIVED_DATA)/Build/Products/*.xctestrun)),$(XCODEBUILD) test)
TESTS = -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
	$(if $(ONLY),$(addprefix -only-testing:,$(subst $(comma), ,$(ONLY))),$(addprefix -skip-testing:OvviUITests/OvviUITests/,$(ON_DEMAND)))
e2e: web
	rm -rf $(DERIVED_DATA)/e2e.xcresult
	scripts/e2e.sh $(E2E) $(MAC) $(TESTS) -resultBundlePath $(DERIVED_DATA)/e2e.xcresult $(BEAUTIFY)

# The same tests in the Tart VM, off this Mac's screen (playbook/workflow.md, UI tests run in the VM). The result is vm.xcresult.
vm-e2e: build-tests
	$(if $(ONLY),,$(error vm-e2e runs chosen tests: ONLY=…; a full run goes to CI))
	scripts/vm-test.sh $(DERIVED_DATA) $(TESTS) $(BEAUTIFY)

run: build
	open "$(DERIVED_DATA)/Build/Products/Debug/Ovvi Dev.app" $(if $(SESSION),--args -session $(SESSION))

# Ad-hoc signed: fine on this Mac; another Mac needs right-click > Open once, and notifications need a real signing
# identity. Only install and dmg get the installed app's bundle id: macOS keys saved windows and defaults by it.
BUNDLE_ID ?= dev.ovvi.app.release
URL_SCHEME ?= ovvi-release
install dmg: BUNDLE_ID = dev.ovvi.app
install dmg: URL_SCHEME = ovvi
app: web
	$(XCODEBUILD) $(MAC) -configuration Release PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) OVVI_URL_SCHEME=$(URL_SCHEME) \
		build $(NOWARN) $(BEAUTIFY)
	@echo "$(DERIVED_DATA)/Build/Products/Release/Ovvi.app"

# ~/.agents/skills: pi and Codex; ~/.claude/skills: Claude Code. -f replaces a dangling link, for which -e is false.
install: app
	rm -rf ~/Applications/Ovvi.app
	cp -R $(DERIVED_DATA)/Build/Products/Release/Ovvi.app ~/Applications/
	for d in ~/.agents/skills ~/.claude/skills; do mkdir -p $$d; [ -e $$d/ovvi ] || ln -sfn $(CURDIR)/skills/ovvi $$d/ovvi; done

dmg: app
	rm -f .build/Ovvi.dmg
	hdiutil create -volname Ovvi -srcfolder $(DERIVED_DATA)/Build/Products/Release/Ovvi.app -ov -format UDZO .build/Ovvi.dmg

