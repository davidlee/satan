{
  description = "flake for doing emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";

    agents = {
      url = "github:davidlee/nix-config?dir=flakes/agents";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Wrapped Emacs (the manual package list). Own pins, no follows, so
    # every devshell shares one build.
    emacs.url = "github:davidlee/nix-config?dir=flakes/emacs";
    doctrine.url = "github:davidlee/doctrine";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    # The per-call pi delegation server (its own repo).
    quotient = {
      url = "github:davidlee/quotient/v0.1.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    doctrine, # doctrine
    zig-overlay, # for building ghostel
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devshell.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        inherit (pkgs) lib stdenv;
        isLinux = stdenv.hostPlatform.isLinux;
        zigPackage = zig-overlay.packages.${system}."default";

        jailLib =
          if isLinux
          then inputs.agents.lib.${system}.mkJailedAgents {}
          else {};
        # LLM gateway clients (DEC-047): the harness has its own key; the pi
        # jails and jailed-claude share pi's. Lazy, so darwin never forces them.
        piGateway = jailLib.gatewayClient "pi";
        satanGateway = jailLib.gatewayClient "satan";
        doctrine-pkg = doctrine.packages.${system}.default;
        wrappedEmacs = inputs.emacs.packages.${system}.default;
        # The tool set minus the jailed agents: what a SATAN working
        # environment needs, independent of how it is confined. Exported as
        # `packages.dev-tools` for consumers that confine differently — the
        # oubliette microvm capsule puts it in the guest's systemPackages, where
        # the agents come from the capsule and a bwrap jail is meaningless.
        devToolPkgs = with pkgs; [
          zigPackage
          nodejs
          just
          postgresql_18
          supabase-cli
          wrappedEmacs
          emacsclient-commands
          sqlite
          socat
          bun
          jq
          python3 # `just test`: satan/harness unittest
          ripgrep # content_read search scope (and its tests)
          typescript

          coreutils # timeout(1) — bounds runaway harness children (SL-011, EX-6)
          luau # noctalia/ plugin tests + lint
        ];
        projectPkgs =
          devToolPkgs
          ++ lib.optionals isLinux [
            jailLib.agentsByName.codex
            jailLib.agentsByName.claude
          ];

        mcpJailOptions =
          jailLib.satanMcpOptions
          ++ [
            # (allow arbitrary elisp execution):
            (jailLib.combinators.try-readwrite "/run/user/1000/emacs/server")
          ];

        supabaseJailOptions = with jailLib.combinators; [
          (try-fwd-env "DOCKER_HOST")
          (try-readwrite "/run/user/1000/podman/podman.sock")
          (set-env "SATAN_DB_HOST" "127.0.0.1")
          (set-env "PGHOST" "127.0.0.1")
          (set-env "PGPORT" "54322")
          (set-env "PGUSER" "postgres")
          (set-env "PGPASSWORD" "postgres")
        ];

        # SATAN's corpus (~/satan-corpus) for dev agents.  It used to be reachable
        # through the /workspace/notes dep; workspaceDeps mounts by basename and
        # /workspace/satan is this project, so it gets its own name (SL-015 D-2).
        # Since CHR-010 that name is simply the basename: mind and mechanism no
        # longer collide, so the target is an explicit path rather than a
        # workaround.
        corpusJailOptions = with jailLib.combinators; [
          (rw-bind "/home/david/satan-corpus" "/workspace/satan-corpus")
        ];

        doctrineJailOptions = with jailLib.combinators; [
          (set-env "DOCTRINE_RESERVATION_FALLBACK" "1")
        ];

        jailEnvOptions = supabaseJailOptions ++ mcpJailOptions ++ corpusJailOptions ++ doctrineJailOptions;
        # workspaceDeps = [ "/home/david/.emacs.d/" ];
        workspaceDeps = [
          "/home/david/flakes/"
          "/home/david/notes/"
          "/home/david/.local/state/behaviour/"
          "/home/david/dev/satan-attrd/"
          "/home/david/dev/satan-patcher/"
          "/home/david/dev/panopticon/"
        ];

        # SATAN — phase-1 fake harness.  Emits ready, one tool_call, then
        # final with one org_update_owned_block action.  Used by the
        # broker (Emacs side) to validate the JSONL contract end-to-end
        # before swapping in a real model harness.
        satanFakeHarness = pkgs.writers.writePython3Bin "satan-fake-harness" {} ''
          import json
          import os
          import sys
          run_id = os.environ.get("SATAN_RUN_ID", "")
          print(json.dumps({"type": "ready", "run_id": run_id}), flush=True)
          print(json.dumps({
              "type": "tool_call", "id": "c1",
              "name": "org_read_context",
              "args": {"scope": "today"},
          }), flush=True)
          sys.stdin.readline()
          print(json.dumps({
              "type": "final",
              "summary": "fake harness ack",
              "actions": [
                  {"type": "org_update_owned_block",
                   "args": {"target": "today", "block": "satan",
                            "content": "SATAN was here.\n"}}
              ],
          }), flush=True)
        '';

        satanJailOptions = with jailLib.combinators; [
          (unsafe-add-raw-args ''--bind "$HOME/dev/satan" "/workspace/satan"'') ## Migration !!

          (unsafe-add-raw-args ''--ro-bind "$HOME/notes" "/satan/notes"'')
          (unsafe-add-raw-args ''--bind "$HOME/satan-corpus/hippocampus" "/satan/hippocampus"'')
          (unsafe-add-raw-args ''--bind "$SATAN_RUN_DIR" "/satan/run"'')
          (try-fwd-env "SATAN_RUN_ID")
          (set-env "SATAN_NOTES_RO" "/satan/notes")
          (set-env "SATAN_HIPPOCAMPUS" "/satan/hippocampus")
          (set-env "SATAN_RUN_DIR" "/satan/run")
        ];

        # SATAN — phase-2 real harness.  Drives an OpenAI-compatible
        # chat-completions loop against the LLM gateway.  Speaks the
        # SATAN JSONL protocol; terminates on a `satan_final` tool call.
        # Multi-file since phase 3B: protocol / bundle / runloop /
        # providers.  See satan/harness/__main__.py.
        satanGptelHarness = let
          pythonEnv = pkgs.python3.withPackages (ps: [ps.openai]);
        in
          pkgs.stdenv.mkDerivation {
            pname = "satan-gptel-harness";
            version = "0";
            src = lib.cleanSourceWith {
              src = ./satan/harness;
              filter = path: type: let
                base = baseNameOf (toString path);
              in
                type == "directory" || (lib.hasSuffix ".py" base && !(lib.hasPrefix "test_" base));
            };
            nativeBuildInputs = [
              pkgs.makeWrapper
              pkgs.ruff
            ];
            dontConfigure = true;
            dontBuild = true;
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              # Inherit the legacy writePython3Bin ignores that still
              # apply to ruff: long lines (model descriptions) and
              # __future__-first imports.  W503 (line break before binary
              # op) and E704 (def one-liners) are dropped — ruff doesn't
              # implement them; pycodestyle did.
              ruff check --select E,F,W --ignore E501,E402 .
              runHook postCheck
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib/satan-gptel-harness $out/bin
              cp -r ./. $out/lib/satan-gptel-harness/
              makeWrapper ${pythonEnv}/bin/python3 \
                $out/bin/satan-gptel-harness \
                --add-flags "$out/lib/satan-gptel-harness/__main__.py"
              runHook postInstall
            '';
            meta.mainProgram = "satan-gptel-harness";
          };

        # Extra env passed through the bwrap jail for the real harness:
        # SATAN_* only — no provider key forwards (the gateway holds those).
        satanGptelJailOptions =
          satanJailOptions
          ++ (with jailLib.combinators; [
            (try-fwd-env "SATAN_MODEL")
            (try-fwd-env "SATAN_BUDGET_TOKENS")
            (try-fwd-env "SATAN_MAX_BUDGET_TOKENS")
          ]);

        # Malebolge, SATAN's durable session daemon (IMP-037), in the room
        # profile (SL-027 DEC-075): its coding tools run in the room VM over
        # ssh, so the jail is offline and binds no host work tree. Its own
        # code is read-only; store and socket are explicit binds.
        malebolgeRoot = "/home/david/dev/malebolge";
        malebolgeDaemon = pkgs.writeShellScriptBin "malebolge" ''
          exec ${lib.getExe pkgs.nodejs_latest} ${malebolgeRoot}/src/daemon-main.ts "$@"
        '';
        # The daemon reads its gateway key only from a file, never env or argv
        # (SL-023 PHASE-18), so no `gateway`: gatewayClient would hand it
        # LLM_GATEWAY_KEY by env, which it ignores. Bound read-only and named
        # explicitly, since the jail home is not the host's.
        malebolgeKeyFile = "/home/david/.config/llm-gateway/keys/malebolge";
        malebolgeCatalog = "/home/david/.config/malebolge/gateway-models.json";
        # The room's facts for the daemon (flakes:SL-016). The jail binds what
        # the door file names, so the identity and known_hosts paths repeat it
        # here: pure eval cannot read the door file (RV-038 F-4).
        malebolgeDoorFile = "/home/david/.config/malebolge/door.toml";
        malebolgeRoomIdentity = "/home/david/.ssh/malebolge-vm.key";
        # The room's state dir, which holds its known_hosts.
        roomStateDir = "/var/lib/capsule/room/assistant";
        # `%h` is the room name (the daemon's ssh host); socat by store path,
        # so it is in the jail's closure.
        malebolgeSshConfig = pkgs.writeText "malebolge-room-ssh-config" ''
          Host *
            ProxyCommand ${pkgs.socat}/bin/socat - UNIX-CONNECT:/run/capsule-room/%h/ssh.sock
        '';
        # The gateway's client socket; gatewaySocketOptions binds its directory.
        gatewayClientSocket = (import "${inputs.agents}/gateway.nix").clientSocket;
        # The profile's own state and runtime dirs. Besides these the jail can
        # write only its persisted home and /tmp (RV-038 F-3).
        malebolgeStateDir = "/home/david/.local/state/satan/durable/room";
        malebolgeRuntimeDir = "/run/user/1000/satan/durable/room";
        malebolgeRoomJailOptions = with jailLib.combinators;
          jailLib.gatewaySocketOptions
          ++ [
            (try-fwd-env "XDG_RUNTIME_DIR")
            (set-env "MALEBOLGE_PROFILE" "room")
            (set-env "MALEBOLGE_DOOR" malebolgeDoorFile)
            (set-env "MALEBOLGE_SSH_CONFIG" "${malebolgeSshConfig}")
            (set-env "MALEBOLGE_GATEWAY_SOCKET" gatewayClientSocket)
            (set-env "MALEBOLGE_GATEWAY_KEY_FILE" malebolgeKeyFile)
            (set-env "MALEBOLGE_GATEWAY_CATALOG" malebolgeCatalog)
            # Directories, never the files (ISS-042), and the door's root, not
            # its own dir: that is the relay's RuntimeDirectory, removed on
            # every room stop (oubliette DEC-056; RV-038 F-2). Connect only.
            (readonly "/run/capsule-room")
            (readonly roomStateDir)
            (readonly malebolgeRoomIdentity)
            (readonly malebolgeDoorFile)
            # set-env puts no store path in the jail's closure (RV-038 F-1).
            (readonly "${malebolgeSshConfig}")
            # satan-mcp, connect only; the rest of /run/user/1000/satan stays out.
            (readonly "/run/user/1000/satan/mcp")
            (readonly malebolgeRoot)
            (readonly "/home/david/satan-corpus")
            (readonly malebolgeKeyFile)
            (readonly malebolgeCatalog)
            # bwrap binds only existing paths. The socket dir is rw: listen
            # needs it. satan-mcp's dir too: its bind above is strict, and
            # only satan-mcp-start creates it, so on a fresh login bwrap would
            # fail before the daemon could degrade (RV-040 F-2).
            (add-runtime "mkdir -p ${malebolgeStateDir} ${malebolgeRuntimeDir} /run/user/1000/satan/mcp")
            (readwrite malebolgeRuntimeDir)
            (readwrite malebolgeStateDir)
          ];

        # SL-029's per-call launch forms (design sec-3, "Per-call mode"): one
        # per filesystem capability, built on the shared jail generator. The
        # generator's launch-dir mount is off — its own rw `--bind` at
        # `/workspace/<basename>` is the wrong strength for read and the wrong
        # path for both — and the root is bound at its own absolute path, so the
        # server's cwd (the canonical root) keeps its meaning inside the jail.
        #
        # The form consumes exactly one positional, the active session
        # directory, and forwards everything after it as pi's own argv: no
        # executable word and no `--` (design sec-3, "Executable contract").
        # The session directory travels as a run-time variable — the form sets
        # it from `$1` and the launcher's raw args expand it — so the session
        # home and the run directory are never bound. `~/.pi` is the
        # generator's persisted-home bind; a second bind for it would be a
        # second story about the same path.
        # `prefix` names the forms and their baseline, `sessionVar` is the
        # run-time variable the form exports, and `--die-with-parent` (below)
        # keeps the jailed child from outliving its server.
        #
        # `jail` is the one generator call a family's forms share; `extraOptions`
        # is a form's own residue over it. `baseline` is the same call with
        # none: the `<prefix>-forms` check subtracts its binds, so whatever the
        # generator (jail.nix base, network, persisted home, gateway) binds
        # cancels rather than being listed here — a generator bump neither
        # fails nor moves the check. The baseline is the host exposure a
        # per-call policy declares as `child_binds` (design sec-3): what the
        # form adds beyond it is the call's root and session directory, nothing
        # else. Never a package: it exists to be compared against.
        quotientFormFamily = let
          prefix = "quotient";
          sessionVar = "QUOTIENT_ACTIVE_SESSION_DIR";
          jail = name: extraOptions:
            jailLib.makeJailedPi {
              inherit name extraOptions;
              # The tracked profiles name `llm-gateway/deepseek-flash`, so the
              # form carries the same gateway the other pi jails do.
              profile = "specDev";
              gateway = piGateway;
              # The project toolchain (node, just, emacs, …) so a delegate can
              # run the root's tests, as `jailed-pi` can.
              extraPkgs = projectPkgs;
              mountLaunchDir = false;
              workspaceDepsFromEnv = false;
            };
          rawArg = jailLib.combinators.unsafe-add-raw-args;
          # Read-only or writable at the same absolute path: the capability is
          # one word here and nowhere else.
          rootBindOption = capability:
            rawArg (
              if capability == "read"
              then ''--ro-bind "$PWD" "$PWD"''
              else ''--bind "$PWD" "$PWD"''
            );
          mkForm = capability: let
            name = "${prefix}-${capability}";
            formJail = jail name [
              (rootBindOption capability)
              # The active session directory, and only it: rw in both
              # capabilities, because pi writes the conversation there even
              # under a read root (design sec-3).
              (rawArg ("--bind \"$" + sessionVar + "\" \"$" + sessionVar + "\""))
              (rawArg ''--tmpfs /tmp'')
              # After the generator's own --chdir "$HOME": the later wins.
              (rawArg ''--chdir "$PWD"'')
              (rawArg "--die-with-parent")
            ];
          in
            pkgs.writeShellScriptBin name ''
              set -euo pipefail

              if [ "$#" -lt 1 ]; then
                echo "${name}: missing the active session directory (this form's one positional argument)" >&2
                exit 64
              fi
              session_dir=$1
              shift # the form's one positional; pi's own argv follows
              case "$session_dir" in
                /*) ;;
                *)
                  echo "${name}: the active session directory must be an absolute path: $session_dir" >&2
                  exit 64
                  ;;
              esac
              if [ ! -d "$session_dir" ]; then
                echo "${name}: no active session directory at $session_dir" >&2
                exit 64
              fi
              export ${sessionVar}="$session_dir"
              exec ${formJail}/bin/jailed-${name} "$@"
            '';
        in {
          baseline = jail "${prefix}-baseline" [];
          forms = {
            "${prefix}-read" = mkForm "read";
            "${prefix}-write" = mkForm "write";
          };
        };
        quotientForms = quotientFormFamily.forms;

        jailPkgs = lib.optionalAttrs isLinux ({
            jailed-pi = jailLib.makeJailedPi {
              profile = "specDev";
              allowSelfAsSubagent = true;
              maxSubagentDepth = 2;
              subagents = ["pi" "claude"];
              extraPkgs = projectPkgs;
              extraOptions = jailEnvOptions;
              gateway = piGateway;
              inherit workspaceDeps;
            };
            jailed-pi-research = jailLib.makeJailedPi {
              name = "pi-research";
              profile = "research";
              extraPkgs = projectPkgs;
              extraOptions = corpusJailOptions;
              gateway = piGateway;
              inherit workspaceDeps;
            };
            jailed-claude = jailLib.makeJailedClaude {
              profile = "specDev";
              subagents = ["pi" "claude"]; # pi agents run nested on the pi gateway
              maxSubagentDepth = 2;
              extraPkgs = projectPkgs;
              extraOptions = jailEnvOptions;
              gateway = piGateway;
              inherit workspaceDeps;
            };
            # jailed-codex = jailLib.makeJailedCodex {
            #   profile = "specDev";
            #   extraPkgs = projectPkgs;
            #   extraOptions = jailEnvOptions;
            #   inherit workspaceDeps;
            # };
            # jailed-zero = jailLib.makeJailedZerostack {
            #   profile = "specDev";
            #   extraPkgs = projectPkgs;
            #   extraOptions = jailEnvOptions;
            #   inherit workspaceDeps;
            # };
            SATAN-jailed-fake-harness = jailLib.makeJailedAgent {
              name = "satan-fake-harness";
              agent = satanFakeHarness;
              profile = "offline";
              extraOptions = satanJailOptions;
              workspaceDeps = [];
            };
            satan-jailed-gptel-harness = jailLib.makeJailedAgent {
              name = "satan-gptel-harness";
              agent = satanGptelHarness;
              profile = "specDev";
              extraOptions = satanGptelJailOptions;
              gateway = satanGateway;
              workspaceDeps = [];
            };
            jailed-malebolge = jailLib.makeJailedAgent {
              name = "malebolge";
              agent = malebolgeDaemon;
              profile = "offline";
              mountLaunchDir = false;
              extraPkgs = [pkgs.nodejs pkgs.openssh pkgs.socat];
              extraOptions = malebolgeRoomJailOptions;
              # No provider keys, so no 1Password wrapper: the key file is its only secret.
              apiKeys = [];
              useOpEnv = false;
              workspaceDeps = [];
              # The devshell evaluates impure: never merge JAIL_WORKSPACE_DEPS (RV-035 F-1).
              workspaceDepsFromEnv = false;
              # Its own persisted home, shared with no other jail (RV-035 F-6).
              persistedHome = "malebolge";
            };
            jailed-shell = jailLib.makeJailedAgent {
              name = "shell";
              agent = pkgs.zsh;
              profile = "specDev";
              extraPkgs = projectPkgs;
              subagents = ["pi" "claude"];
              extraOptions = jailEnvOptions;
              gateway = piGateway;
            };
            bubblewrap = pkgs.bubblewrap;
          }
          # The per-call forms are `packages` (nix build .#quotient-read) and are
          # swept by runnerSocketUnjailed like every jail.
          // quotientForms);

        # Every probe string of the launcher checks, and no other binding:
        # the I1 closure sweep excludes this one by name. Written literally,
        # never derived from the jails' option lists, so dropping a forward
        # there fails a check instead of moving it.
        formProbes = let
          envPrefix = "QUOTIENT";
        in {
          inherit envPrefix;
          # Unquoted, as the check reads launchers with quotes stripped.
          session = "--bind $" + "${envPrefix}_ACTIVE_SESSION_DIR $" + "${envPrefix}_ACTIVE_SESSION_DIR";
          # The session home (all sessions, not just this call's), the run
          # directory and the policy file are bound into no form.
          absent = [
            "/workspace/"
            "${envPrefix}_SESSION_HOME"
            "${envPrefix}_RUN_DIR"
            "${envPrefix}_POLICY"
          ];
          # At its own absolute path, read-only for the read capability. Each
          # form must not carry the other's.
          read = {
            root = ''--ro-bind "$PWD" "$PWD"'';
            otherRoot = ''--bind "$PWD" "$PWD"'';
          };
          write = {
            root = ''--bind "$PWD" "$PWD"'';
            otherRoot = ''--ro-bind "$PWD" "$PWD"'';
          };
        };
        jailProbes = {
          harness = {
            # The 1Password wrapper execs `"$op" run`, so the literal `op run`
            # alone never matches it; its env file's name does.
            outerAbsent = ["op run" "-api-keys.env"];
            innerPresent = [
              "--args 22 22< <(printf"
              "--setenv LLM_GATEWAY_KEY \"$(<"
              "--setenv LLM_GATEWAY_URL"
              "--setenv SATAN_MODEL \"\${SATAN_MODEL}\""
              "--setenv SATAN_BUDGET_TOKENS \"\${SATAN_BUDGET_TOKENS}\""
              "--setenv SATAN_MAX_BUDGET_TOKENS \"\${SATAN_MAX_BUDGET_TOKENS}\""
            ];
            innerAbsent = ["API_KEY" "SATAN_PROVIDER"];
            # Absent once the `<(printf …)` substitutions are stripped: the
            # key travels over `--args 22`, never on bwrap's argv.
            argvAbsent = ["LLM_GATEWAY_KEY"];
          };
          # The room profile (SL-027 DEC-075, design §6): offline, the room
          # reached over its door socket, the gateway over its client socket,
          # writes only to the profile's own state and runtime dirs.
          malebolge = {
            # Each ends at its separator, so a longer value cannot match.
            present = [
              "--setenv MALEBOLGE_PROFILE room "
              "--setenv MALEBOLGE_DOOR /home/david/.config/malebolge/door.toml "
              "--setenv MALEBOLGE_SSH_CONFIG /nix/store/"
              "--setenv MALEBOLGE_GATEWAY_SOCKET /run/llm-gateway-client/api.sock "
              "--setenv MALEBOLGE_GATEWAY_KEY_FILE /home/david/.config/llm-gateway/keys/malebolge "
              "--setenv MALEBOLGE_GATEWAY_CATALOG /home/david/.config/malebolge/gateway-models.json "
              "--ro-bind /run/capsule-room /run/capsule-room "
              "--ro-bind /var/lib/capsule/room/assistant /var/lib/capsule/room/assistant "
              "--ro-bind /home/david/.ssh/malebolge-vm.key /home/david/.ssh/malebolge-vm.key "
              "--ro-bind /home/david/.config/malebolge/door.toml /home/david/.config/malebolge/door.toml "
              "--ro-bind /run/llm-gateway-client /run/llm-gateway-client "
              "--ro-bind /run/user/1000/satan/mcp /run/user/1000/satan/mcp "
              "--ro-bind /home/david/dev/malebolge /home/david/dev/malebolge "
              "--ro-bind /home/david/satan-corpus /home/david/satan-corpus "
              "--ro-bind /home/david/.config/llm-gateway/keys/malebolge /home/david/.config/llm-gateway/keys/malebolge "
              "--ro-bind /home/david/.config/malebolge/gateway-models.json /home/david/.config/malebolge/gateway-models.json "
              "--bind ~/.local/share/jail.nix/home/malebolge ~ "
              "--bind /run/user/1000/satan/durable/room /run/user/1000/satan/durable/room "
              "--bind /home/david/.local/state/satan/durable/room /home/david/.local/state/satan/durable/room "
              "mkdir -p /home/david/.local/state/satan/durable/room /run/user/1000/satan/durable/room /run/user/1000/satan/mcp"
              "--unshare-net "
              # On PATH; the store hashes force interpolation.
              "${pkgs.openssh}/bin:"
              "${pkgs.socat}/bin:"
            ];
            absent = [
              "/workspace/"
              "--bind /run/user/1000/satan "
              "--bind /run/user/1000/satan/ "
              "goad"
              "MALEBOLGE_SKILLS"
              "durable/host"
              "agent-offline"
              "op run"
              "-api-keys.env"
              "API_KEY"
              "LLM_GATEWAY_KEY"
            ];
            # The rendered ssh_config: the door socket by room name, socat from
            # the store (the oubliette host has none on PATH).
            sshConfigPresent = [
              "ProxyCommand ${pkgs.socat}/bin/socat - UNIX-CONNECT:/run/capsule-room/%h/ssh.sock"
            ];
          };
        };

        # A check over built launchers, as text (DEC-046). Pure: reads store
        # files, launches nothing. `body` asserts with fail / must / must_not;
        # `probe` renders one assertion per probe string.
        probe = helper: file: label:
          lib.concatMapStringsSep "\n"
          (s: "${helper} ${lib.escapeShellArg label} \"${file}\" ${lib.escapeShellArg s}");
        launcherCheck = name: body:
          pkgs.runCommand name {} ''
            # `! cmd` never trips errexit, so every assertion is an `if`.
            fail() {
              echo "${name}: $*" >&2
              exit 1
            }
            # must / must_not <label> <file> <string>
            must() {
              if ! grep -Fq -- "$3" "$2"; then fail "$1 must contain '$3'"; fi
            }
            must_not() {
              if grep -Fq -- "$3" "$2"; then fail "$1 must not contain '$3'"; fi
            }

            ${body}

            touch $out
          '';

        harnessJailProfile = let
          p = jailProbes.harness;
        in
          launcherCheck "harness-jail-profile" ''
            name=satan-gptel-harness
            outer=${jailPkgs.satan-jailed-gptel-harness}/bin/jailed-$name
            test -f "$outer" || fail "no outer launcher at $outer"
            ${probe "must_not" "$outer" "outer launcher" p.outerAbsent}

            # The gateway wrapper execs the bwrap launcher; an empty match
            # would make every must_not below pass, so it fails first.
            inner=$(sed -n "s|^exec \(/nix/store/[^ ]*-jailed-$name/bin/jailed-$name\) .*|\1|p" "$outer")
            if [ -z "$inner" ] || [ ! -f "$inner" ]; then
              fail "outer launcher execs no inner jailed-$name (not a gateway wrapper?)"
            fi
            ${probe "must" "$inner" "inner launcher" p.innerPresent}
            ${probe "must_not" "$inner" "inner launcher" p.innerAbsent}

            # The strip stops at the first `)`, which closes the nested `$(<`
            # after the key's name.
            sed 's/<(printf[^)]*)//g' "$inner" > "$TMPDIR/argv-only"
            ${probe "must_not" "$TMPDIR/argv-only" "inner argv" p.argvAbsent}
          '';

        # No gateway wrapper here: the bwrap launcher is the only one.
        malebolgeJailProfile = let
          p = jailProbes.malebolge;
        in
          launcherCheck "malebolge-jail-profile" ''
            launcher=${jailPkgs.jailed-malebolge}/bin/jailed-malebolge
            test -f "$launcher" || fail "no launcher at $launcher"
            # Absent first: a 1Password wrapper in place of the launcher
            # would otherwise fail as a missing bind.
            ${probe "must_not" "$launcher" "launcher" p.absent}
            ${probe "must" "$launcher" "launcher" p.present}
            ssh_config=$(sed -n 's|.*--setenv MALEBOLGE_SSH_CONFIG \(/nix/store/[^ ]*\).*|\1|p' "$launcher")
            if [ -z "$ssh_config" ] || [ ! -f "$ssh_config" ]; then
              fail "launcher sets no MALEBOLGE_SSH_CONFIG store file"
            fi
            ${probe "must" "$ssh_config" "ssh config" p.sshConfigPresent}
            # set-env alone leaves the file outside the jail: it must be bound,
            # by the runtime closure or explicitly.
            closure=$(sed -n 's|^exec {RUNTIME_CLOSURE_BIND_ARGS_FD}<\(/nix/store/[^ ]*\)$|\1|p' "$launcher")
            test -f "$closure" || fail "launcher names no runtime closure bind args"
            if ! grep -Faq -- "$ssh_config" "$closure" && ! grep -Fq -- "--ro-bind $ssh_config $ssh_config " "$launcher"; then
              fail "ssh config $ssh_config is not bound in the jail"
            fi
          '';

        # I4 (SL-023 REQ-016): the satan-runner control socket is bound into
        # no jail, nor is the runtime dir that holds it. Iterates `jailPkgs`,
        # so a new jail is covered without edits; each launcher is checked
        # with the inner launcher it execs. Strings are written literally.
        runnerSocketUnjailed = let
          # The whole runtime dir as a bind argument (a bare path between
          # spaces); sub-paths such as /run/user/1000/satan/mcp are fine.
          absent = ["satan-runner" " /run/user/1000 "];
        in
          pkgs.runCommand "runner-socket-unjailed" {} ''
            fail() {
              echo "runner-socket-unjailed: $*" >&2
              exit 1
            }
            scanned=0
            for pkg in ${lib.concatStringsSep " " (lib.attrValues jailPkgs)}; do
              for outer in "$pkg"/bin/*; do
                inner=$(sed -n 's|^exec \(/nix/store/[^ ]*/bin/jailed-[^ ]*\) .*|\1|p' "$outer")
                for launcher in "$outer" $inner; do
                  test -f "$launcher" || fail "no launcher at $launcher"
                  scanned=$((scanned + 1))
                  ${lib.concatMapStringsSep "\n" (s: "if grep -Fq -- ${lib.escapeShellArg s} \"$launcher\"; then fail \"$launcher must not contain '${s}'\"; fi") absent}
                done
              done
            done
            test "$scanned" -gt 0 || fail "scanned no launchers"
            touch $out
          '';

        # SL-029 (design sec-3's per-call mode, sec-7's verification): each
        # form's bind set equals its family's generator baseline plus root +
        # active session directory, so a bind the form adds or drops fails
        # here; what the generator binds is its own concern. Also the
        # positional contract and the run-time session path. Text only
        # (DEC-046): nothing is launched. The check is `quotient-forms`.
        quotientFormsCheck = let
          prefix = "quotient";
          p = formProbes;
          family = quotientFormFamily;
          checkName = "${prefix}-forms";
          sessionVar = "${p.envPrefix}_ACTIVE_SESSION_DIR";
          # One capability's half: pkg is the form package, whose exec line
          # names the gateway wrapper, whose exec line names the bwrap launcher
          # that carries the bind args.
          formCheck = capability: pkg: let
            cap = p.${capability};
            label = "(e) ${capability} form";
            execLabel = "(e) ${capability} form exec";
          in ''
            cap=${capability}
            form=${pkg}/bin/${prefix}-${capability}
            test -f "$form" || fail "$cap: no form at $form"

            # (e) The positional contract: exactly one positional is consumed
            # — the active session directory — and the rest is forwarded as
            # pi's own argv, with no executable word and no `--`. The form
            # names no jail flag: the confinement is the generator's.
            must ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "session_dir=$1"}
            must ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "shift"}
            must ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "export ${sessionVar}=\"$session_dir\""}
            must_not ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "$2"}
            must_not ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "--bind"}
            must_not ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "--ro-bind"}
            must_not ${lib.escapeShellArg label} "$form" ${lib.escapeShellArg "--tmpfs"}
            # The three argument guards each exit 64 (EX_USAGE).
            test "$(grep -Fc -- 'exit 64' "$form")" -eq 3 || fail "$cap: the form must carry exactly three 'exit 64' guards"
            sed -n '/^exec /p' "$form" > "$TMPDIR/$cap-form-exec"
            test -s "$TMPDIR/$cap-form-exec" || fail "$cap: the form has no exec line"
            must ${lib.escapeShellArg execLabel} "$TMPDIR/$cap-form-exec" ${lib.escapeShellArg "/bin/jailed-${prefix}-${capability} \"$@\""}
            must_not ${lib.escapeShellArg execLabel} "$TMPDIR/$cap-form-exec" ${lib.escapeShellArg " -- "}
            must_not ${lib.escapeShellArg execLabel} "$TMPDIR/$cap-form-exec" ${lib.escapeShellArg "$1"}

            outer=$(sed -n 's|^exec \(/nix/store/[^ ]*/bin/jailed-[^ ]*\) .*|\1|p' "$form")
            if [ -z "$outer" ] || [ ! -f "$outer" ]; then
              fail "$cap: the form execs no jailed launcher (not the gateway wrapper?)"
            fi
            launcher=$(sed -n 's|^exec \(/nix/store/[^ ]*/bin/jailed-[^ ]*\) .*|\1|p' "$outer")
            if [ -z "$launcher" ] || [ ! -f "$launcher" ]; then
              fail "$cap: the gateway wrapper execs no bwrap launcher"
            fi

            # (b) The root flag is this capability's, and the other one is not.
            must ${lib.escapeShellArg "(b) ${capability} root flag"} "$launcher" ${lib.escapeShellArg cap.root}
            must_not ${lib.escapeShellArg "(b) ${capability} root flag"} "$launcher" ${lib.escapeShellArg cap.otherRoot}
            # (d) The session home, the run directory, the policy file and
            # /workspace/ are bound into no child.
            ${lib.concatMapStringsSep "\n" (s: "must_not ${lib.escapeShellArg "(d) ${capability} launcher"} \"$launcher\" ${lib.escapeShellArg s}") p.absent}
            # (f) G7: the child dies with its parent. jail.nix also emits
            # `--die-with-parent`, so the family's own raw arg is a harmless
            # duplicate that states the guarantee on the form itself.
            if ! grep -Fq -- ${lib.escapeShellArg "--die-with-parent"} "$launcher"; then
              fail "(f) ${capability} launcher must contain '--die-with-parent'"
            fi
            # Quotes stripped once, so a raw arg and a generator-rendered bind
            # are read the same way.
            sed 's/"//g' "$launcher" > "$TMPDIR/$cap-unquoted"

            # (a) The residue over the baseline: every bind word-pair this
            # form adds to the generator's own jail must be root + session
            # directory, and it must drop none. Both residues are printed
            # when they differ.
            bind_words "$TMPDIR/$cap-unquoted" > "$TMPDIR/$cap-actual-set"
            printf '%s\n' ${lib.escapeShellArg cap.root} ${lib.escapeShellArg p.session} |
              sed 's/"//g' > "$TMPDIR/$cap-expected"
            bind_words "$TMPDIR/$cap-expected" > "$TMPDIR/$cap-expected-set"
            comm -13 "$TMPDIR/baseline-set" "$TMPDIR/$cap-actual-set" > "$TMPDIR/$cap-added"
            comm -23 "$TMPDIR/baseline-set" "$TMPDIR/$cap-actual-set" > "$TMPDIR/$cap-dropped"
            if ! cmp -s "$TMPDIR/$cap-expected-set" "$TMPDIR/$cap-added" || [ -s "$TMPDIR/$cap-dropped" ]; then
              {
                echo "${checkName}: $cap: the residue over the generator baseline is not root + active session directory"
                echo "--- expected residue ---"
                cat "$TMPDIR/$cap-expected-set"
                echo "--- added over the baseline ---"
                cat "$TMPDIR/$cap-added"
                echo "--- dropped from the baseline ---"
                cat "$TMPDIR/$cap-dropped"
              } >&2
              fail "(a) $cap: the launcher's bind set is not baseline + root + session directory"
            fi

            # (c) A tmpfs /tmp inside the jail, never the host's /tmp.
            must ${lib.escapeShellArg "(c) ${capability} launcher"} "$TMPDIR/$cap-unquoted" ${lib.escapeShellArg "--tmpfs /tmp"}

          '';
        in
          launcherCheck checkName ''
            # Every bind word-pair in a launcher, one per line, quotes already
            # stripped and store hashes folded: a nixpkgs bump is not drift.
            bind_words() {
              grep -oE -- '--(ro-)?bind(-try)? [^ ]+ [^ ]+' "$1" |
                sed -E 's|/nix/store/[a-z0-9]{32}-|/nix/store/*-|g' |
                sort -u
            }

            # The baseline's bind set, once: same generator call, no extra
            # options. Its gateway wrapper execs the bwrap launcher.
            baseline_outer=${family.baseline}/bin/jailed-${prefix}-baseline
            test -f "$baseline_outer" || fail "no baseline at $baseline_outer"
            baseline=$(sed -n 's|^exec \(/nix/store/[^ ]*/bin/jailed-[^ ]*\) .*|\1|p' "$baseline_outer")
            if [ -z "$baseline" ] || [ ! -f "$baseline" ]; then
              fail "the baseline's gateway wrapper execs no bwrap launcher"
            fi
            sed 's/"//g' "$baseline" > "$TMPDIR/baseline-unquoted"
            bind_words "$TMPDIR/baseline-unquoted" > "$TMPDIR/baseline-set"

            ${formCheck "read" "${jailPkgs."${prefix}-read"}"}
            ${formCheck "write" "${jailPkgs."${prefix}-write"}"}
          '';
      in {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
        };

        packages =
          lib.optionalAttrs isLinux jailPkgs
          // {
            quotient = inputs.quotient.packages.${system}.default;
            # The input's write-denial probe, run from its store source (it
            # resolves its own src/cli.ts relative to the script).
            quotient-hostile-audit = pkgs.writeShellApplication {
              name = "quotient-hostile-audit";
              runtimeInputs = [pkgs.nodejs_22];
              text = ''exec ${inputs.quotient}/scripts/hostile-audit "$@"'';
            };
            # The devshell's tool set as one closure, for out-of-tree consumers
            # that need the same tools without the devshell (the microvm
            # capsule's `toolsPackage`), so the VM and the devshell can't drift.
            # One exception: doctrine. The devshell and jails use the host's
            # cargo install (agents' hostDoctrine); a capsule has no host
            # binary, so it gets this flake's pinned build.
            dev-tools = pkgs.buildEnv {
              name = "satan-dev-tools";
              paths = devToolPkgs ++ [doctrine-pkg];
              ignoreCollisions = true;
            };
          };

        checks = lib.optionalAttrs isLinux {
          harness-jail-profile = harnessJailProfile;
          malebolge-jail-profile = malebolgeJailProfile;
          quotient-forms = quotientFormsCheck;
          runner-socket-unjailed = runnerSocketUnjailed;
        };

        devshells.default = {
          packages = projectPkgs ++ lib.optionals isLinux (lib.attrValues jailPkgs);
          commands = [
            {
              name = "d";
              command = "doctrine $@";
            }
            {
              name = "jpi";
              help = "jailed-pi $@";
              command = "jailed-pi $@";
            }
            {
              name = "jcl";
              help = "jailed-claude (--dangerously-skip-permissions for interactive)";
              command = ''
                case "''${1:-}" in
                  marketplace|update|config|mcp) jailed-claude "$@" ;;
                  *) jailed-claude --dangerously-skip-permissions "$@" ;;
                esac
              '';
            }
            {
              name = "jail-zsh";
              help = "jailed shell (zsh) in pi's context";
              command = "jailed-shell $@";
            }
          ];
        };
      };
    };
}
