# INSTALLATION (todo: have installer handle it)
#
# in your project justfile, add:
# mod doctrine '.doctrine'
#
# you might want to install a few things
# glow
# fd
# tree
# fzf

# ensure paths relative to project root
set working-directory := '..'

#
# Conveniences
#
preview := "'CLICOLOR_FORCE=1 COLORTERM=truecolor glow --style=dark --width=80 {}'"

md:
  glow $(ls .doctrine/*.md | fzf)

#
# Slice
#

@fuzzy root query='':
  @glow $(fd -e md . {{root}} | fzf -q "{{query}}" --preview {{preview}})

@fuzzy-slice query='': (fuzzy ".doctrine/slice" query)

# fuzzy design viewer
@design id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy-slice "design.md$ "
  else
    glow .doctrine/slice/{{id}}/design.md
  fi

# fuzzy plan viewer
@plan id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy-slice "plan.md$ "
  else
    glow .doctrine/slice/{{id}}/plan.md
  fi

#
# Governance
#
@adr id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy ".doctrine/adr" ""
  else
    glow `doctrine adr paths {{id}} -m`
  fi

@policy id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy ".doctrine/policy" ""
  else
    glow `doctrine policy paths {{id}} -m`
  fi

@standard id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy ".doctrine/standard" ""
  else
    glow `doctrine standard paths {{id}} -m`
  fi

#
# Other
#

@rfc id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy ".doctrine/rfc" ""
  else
    glow `doctrine rfc paths {{id}} -m`
  fi

@spec id='':
  #!/usr/bin/env zsh
  if [ -z "{{id}}" ]; then
    just doctrine fuzzy ".doctrine/spec" ""
  else
    glow `doctrine spec paths {{id}} -m`
  fi

@boot:
  doctrine boot --emit | glow

## DOCTRINE CHECKS:
##
## doctrine check <type>
##

quick: fmt lint validate

# Fast inner-loop gate — root package only.
check: fmt lint validate test build

# Full gate for end-of-phase / CI — includes the cordage workspace crate.
gate: fmt lint validate test-all build

## Sanity Check
##

validate:
  doctrine prompt check
  doctrine doctor

validate-full: validate

# format rust code
fmt:
  cargo fmt

# assert rust formatting is clean without mutating (the non-mutating twin of `fmt`)
fmt-check:
  cargo fmt --check

# lint rust (aggressive)
lint:
  cargo clippy

# test rust
test:
  cargo test

# full CI tests
test-all: test

# cargo build
build:
  cargo build

## GIT
##

# lazy .doctrine commit to clear the decks
commit:# readme-index
  git reset && git add .doctrine/ && git ci -m doctrine

# integrate main into edge
integrate:
  git merge main
  git fetch . edge:main

promote:
  git fetch . edge:main

# integrate edge into main
push-main:
  git push . edge:main

# Push local edge and main to origin — works from any branch
push-upstream:
  git push origin edge:refs/heads/edge main:refs/heads/main

