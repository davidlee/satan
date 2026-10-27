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
    # The per-call pi delegation server (its own repo) and its form builder.
    # Unpinned: a break should surface.
    quotient = {
      url = "github:davidlee/quotient";
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
          biome

          coreutils # timeout(1) — bounds runaway harness children (SL-011, EX-6)
          luau # noctalia/ plugin tests + lint
        ];
        projectPkgs =
          devToolPkgs
          ++ lib.optionals isLinux [
            jailLib.agentsByName.codex
            jailLib.agentsByName.claude
          ];

        # The project half of every dev jail's and every quotient form's
        # options, over either builder's combinator set (agents README
        # § quotient forms): the local supabase database, over TCP. No
        # container socket: one would let a delegate mount any host path.
        projectOptions = c:
          with c; [
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

        jailEnvOptions = projectOptions jailLib.combinators ++ jailLib.satanMcpOptions ++ corpusJailOptions ++ doctrineJailOptions;
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
        gatewayClientSocket = jailLib.gatewayFacts.clientSocket;
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

        # SL-029's per-call forms (`quotient help form`), one per filesystem
        # capability: quotient's form family through the agents lib, so the
        # form-1 contract (DEC-116) is quotient's and the posture the lib's.
        # The forms serve this host's quotient policy, every root it allows:
        # the project half they carry must suit them all. No persisted home:
        # a form writes only the root, the session directory and its private
        # temp, so the policy's `exposure` is empty.
        quotientFamily = jailLib.quotientFormFamily {
          inherit (inputs) quotient;
          prefix = "quotient";
          packages = projectPkgs;
          options = projectOptions;
        };
        quotientForms = {
          quotient-read = quotientFamily.read;
          quotient-write = quotientFamily.write;
        };

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
              # Its key file is its only secret: no jail carries a provider key.
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
        # no jail, nor is the runtime dir that holds it; sub-paths such as
        # /run/user/1000/satan/mcp are fine.
        # The scan is the agents lib's (nix-config IMP-051): DEC-046's built
        # launchers as text, over every jail in `jailPkgs`.
        runnerSocketUnjailed = jailLib.mkJailScanCheck {
          name = "runner-socket-unjailed";
          launchers = lib.attrValues jailPkgs;
          literals = ["satan-runner"];
          tokens = ["/run/user/[0-9]+/?"];
          controlBind = "--bind /run/user/1000 /run/user/1000";
        };

        # DEC-013 (screwtape SL-001; SPEC-002 NF-004): no jail can run `op` or
        # reach 1Password's sockets, nor bind an ancestor that would expose
        # them. A regression guard for known paths, not proof of NF-004:
        # whole-home binds are ISS-028's, the abstract socket RSK-021's.
        opUnjailed = jailLib.opUnjailed (lib.attrValues jailPkgs);
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
          # quotient's form-1 check over the family's text (SL-029's residue
          # property is its rule (f); DEC-116).
          quotient-forms = inputs.quotient.lib.checkFormFamily {
            inherit pkgs;
            family = quotientFamily;
          };
          runner-socket-unjailed = runnerSocketUnjailed;
          op-unjailed = opUnjailed;
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
