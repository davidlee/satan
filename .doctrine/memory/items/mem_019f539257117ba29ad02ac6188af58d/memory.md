# Stale .elc masks source edits in batch runs

Manual batch-byte-compile leaves .elc that require loads over edited .el, masking source fixes; rm before re-running
