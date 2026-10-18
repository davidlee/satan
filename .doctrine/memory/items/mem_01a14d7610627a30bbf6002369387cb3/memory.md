# Host pi-durable harness → oubliette guest: the recipe (EVD-005, SL-023)

## Tools in the guest: pi-env through the relay

- `SshTarget`: `host` = guest address (a slot's is `10.99.0.2`; read it with
  `capsule <slot> ssh 'ip -4 -o addr show scope global'`), `user: "agent"`,
  `configFile` = a file containing
  `Host *` / `ProxyCommand socat - UNIX-CONNECT:/run/capsule/<slot>/ssh.sock`,
  plus pi-env's own `knownHostsFile` and a fixed `hostKeyAlias`.
- pi-env passes `-F` and neutralises only `RemoteCommand`/`LocalCommand`, so
  `ProxyCommand` works unmodified (pienv `src/ssh.ts:90,100-101`).
- The guest home is `/work/home`, not `/home/agent`: use `remote.home` from
  `connectSsh` as `cwd`, or every exec fails `spawn_error`.
- The daemon uploads itself over ssh into `~/.pi/mobile/tools/`; no guest
  egress needed.
- `exec()` returns only `exitCode`; output comes through the `onOutput`
  callback.
- Starting a slot (`capsule <slot> start`) needs sudo — an agent cannot; ask
  the user to run `! capsule <slot> start`.

## Model on the host: pi-ai via the LLM gateway

- Take pi-ai's built-in provider whose model id matches the gateway's name
  (e.g. `deepseek` / `deepseek-flash`), spread it with
  `baseUrl: "http://127.0.0.1:4000/v1"` on the provider *and* on every model
  from `getModels`/`getAllModels`, and set the provider's key env var
  (`DEEPSEEK_API_KEY`) to a gateway key from `~/.config/llm-gateway/keys/<name>`.
- No `models.json` needed; that is pi-coding-agent's config, not pi-ai's.

Related: [[mem.concept.satan.three-roots]].
