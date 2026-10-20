Calling the `codemode` tool in this environment fails before any nested call runs:

    Script sandbox failed: Cannot find module
    "/\$bunfs/root/src/extensions/codemode/worker.js"

Use `bash` (python3/tomllib for structured extraction) rather than codemode to batch
tool calls here.