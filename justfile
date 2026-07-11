check: lint test

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in satan/*.el; do
        bin/elisp-locate-paren-error "$f"
    done

test:
    #!/usr/bin/env bash
    set -euo pipefail
    emacs --batch -L ./satan -L ./dev \
      -l satan-test --eval "(satan-test-run-batch)"
