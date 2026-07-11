{
  description = "flake for doing emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    emacs-overlay.url = "https://github.com/nix-community/emacs-overlay/archive/master.tar.gz";

    pub = {
      url = "path:/home/david/flakes/pub";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.emacs-overlay.follows = "emacs-overlay";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
    doctrine.url = "github:davidlee/doctrine";
    zig-overlay.url = "github:mitchellh/zig-overlay";
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
        isLinux = stdenv.isLinux;
        zigPackage = zig-overlay.packages.${system}."default";

        jailLib =
          if isLinux
          then inputs.pub.lib.${system}.mkJailedAgents {inherit (inputs) llm-agents;}
          else {};
        doctrine-pkg = doctrine.packages.${system}.default;
        wrappedEmacs = inputs.pub.packages.${system}.emacs;
        projectPkgs = with pkgs;
          [
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
            codex
          ]
          ++ [doctrine-pkg];

        mcpJailOptions = with jailLib.combinators; [
          # expose SATAN MCP
          (try-readwrite "/run/user/1000/satan/mcp/mcp.sock")
          (try-fwd-env "XDG_RUNTIME_DIR")
          (try-fwd-env "SATAN_MCP_SOCKET")
          # (allow arbitrary elisp execution):
          (try-readwrite "/run/user/1000/emacs/server")
        ];

        apiKeyJailOptions = with jailLib.combinators; [
          (try-fwd-env "OPENROUTER_API_KEY")
          (ro-bind "/usr/bin/env" "/usr/bin/env")
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

        jailEnvOptions = apiKeyJailOptions ++ supabaseJailOptions ++ mcpJailOptions;
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
          (unsafe-add-raw-args ''--bind "$HOME/notes/satan/hippocampus" "/satan/hippocampus"'')
          (unsafe-add-raw-args ''--bind "$SATAN_RUN_DIR" "/satan/run"'')
          (try-fwd-env "SATAN_RUN_ID")
          (set-env "SATAN_NOTES_RO" "/satan/notes")
          (set-env "SATAN_HIPPOCAMPUS" "/satan/hippocampus")
          (set-env "SATAN_RUN_DIR" "/satan/run")
        ];

        # SATAN — phase-2 real harness.  Drives an OpenAI-compatible
        # chat-completions loop (OpenRouter v1 by default).  Speaks the
        # SATAN JSONL protocol; terminates on a `satan_final` tool call.
        # Multi-file since phase 3B: protocol / bundle / runloop /
        # providers.  See ~/.emacs.d/satan/harness/__main__.py.
        # satanGptelHarness = let
        #   pythonEnv = pkgs.python3.withPackages (ps: [ps.openai]);
        # in
        #   pkgs.stdenv.mkDerivation {
        #     pname = "satan-gptel-harness";
        #     version = "0";
        #     src = lib.cleanSourceWith {
        #       src = ./satan/harness;
        #       filter = path: type: let
        #         base = baseNameOf (toString path);
        #       in
        #         type == "directory" || (lib.hasSuffix ".py" base && !(lib.hasPrefix "test_" base));
        #     };
        #     nativeBuildInputs = [
        #       pkgs.makeWrapper
        #       pkgs.ruff
        #     ];
        #     dontConfigure = true;
        #     dontBuild = true;
        #     doCheck = true;
        #     checkPhase = ''
        #       runHook preCheck
        #       # Inherit the legacy writePython3Bin ignores that still
        #       # apply to ruff: long lines (model descriptions) and
        #       # __future__-first imports.  W503 (line break before binary
        #       # op) and E704 (def one-liners) are dropped — ruff doesn't
        #       # implement them; pycodestyle did.
        #       ruff check --select E,F,W --ignore E501,E402 .
        #       runHook postCheck
        #     '';
        #     installPhase = ''
        #       runHook preInstall
        #       mkdir -p $out/lib/satan-gptel-harness $out/bin
        #       cp -r ./. $out/lib/satan-gptel-harness/
        #       makeWrapper ${pythonEnv}/bin/python3 \
        #         $out/bin/satan-gptel-harness \
        #         --add-flags "$out/lib/satan-gptel-harness/__main__.py"
        #       runHook postInstall
        #     '';
        #     meta.mainProgram = "satan-gptel-harness";
        #   };

        # Extra env passed through the bwrap jail for the real harness:
        # provider selection + cumulative token budget + per-provider keys.
        # satanGptelJailOptions =
        #   satanJailOptions
        #   ++ (with jailLib.combinators; [
        #     (try-fwd-env "SATAN_PROVIDER")
        #     (try-fwd-env "SATAN_MODEL")
        #     (try-fwd-env "SATAN_BUDGET_TOKENS")
        #     (try-fwd-env "OPENROUTER_API_KEY")
        #     (try-fwd-env "ANTHROPIC_API_KEY")
        #     (try-fwd-env "OPENAI_API_KEY")
        #     (try-fwd-env "DEEPSEEK_API_KEY")
        #   ]);

        jailPkgs = lib.optionalAttrs isLinux {
          jailed-pi = jailLib.makeJailedPi {
            profile = "specDev";
            allowSelfAsSubagent = true;
            maxSubagentDepth = 2;
            extraPkgs = projectPkgs;
            extraOptions = jailEnvOptions;
            inherit workspaceDeps;
            # Patch-agent adapter pre-resolves op:// refs via
            # `my/op-read-env' (Emacs session cache) and exports the
            # plaintext into `process-environment' before spawning, so
            # skip the outer `op run' wrapper that would prompt
            # biometric per launch.  `passApiKeysFromEnv = true' keeps
            # the bwrap `--setenv VAR "$VAR"' forwarding so the
            # caller-side env still flows into the jail.  Same path
            # `satan-jailed-gptel-harness' uses.
            useOpEnv = false;
            passApiKeysFromEnv = true;
          };
          jailed-pi-research = jailLib.makeJailedPi {
            name = "pi-research";
            profile = "research";
            extraPkgs = projectPkgs;
            extraOptions = apiKeyJailOptions;
            inherit workspaceDeps;
          };
          jailed-opencode = jailLib.makeJailedOpencode {
            profile = "specDev";
            extraPkgs = projectPkgs;
            extraOptions = jailEnvOptions;
            inherit workspaceDeps;
          };
          jailed-claude = jailLib.makeJailedClaude {
            profile = "specDev";
            extraPkgs = projectPkgs;
            extraOptions = jailEnvOptions;
            inherit workspaceDeps;
          };
          jailed-dirge = jailLib.makeJailedDirge {
            profile = "specDev";
            extraPkgs = projectPkgs;
            extraOptions = apiKeyJailOptions;
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
          # satan-jailed-gptel-harness = jailLib.makeJailedAgent {
          #   name = "satan-gptel-harness";
          #   agent = satanGptelHarness;
          #   profile = "specDev";
          #   extraOptions = satanGptelJailOptions;
          #   workspaceDeps = [];
          #   # Emacs broker pre-resolves op:// refs via `my/op-read-env'
          #   # and caches in `my/op--cache' for the Emacs session, so the
          #   # outer `op run' wrapper would prompt 1Password biometric on
          #   # every tick. Disable it; keep `passApiKeysFromEnv' so the
          #   # broker's plaintext env still flows into the jail.
          #   useOpEnv = false;
          #   passApiKeysFromEnv = true;
          # };
          jailed-shell = jailLib.makeJailedAgent {
            name = "shell";
            agent = pkgs.zsh;
            profile = "specDev";
            extraPkgs = projectPkgs;
            subagents = ["pi" "dirge" "claude"];
            extraOptions = jailEnvOptions;
          };
          bubblewrap = pkgs.bubblewrap;
        };
      in {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
        };

        packages = lib.optionalAttrs isLinux jailPkgs;

        devshells.default = {
          packages = projectPkgs ++ lib.optionals isLinux (lib.attrValues jailPkgs);
          commands = [
            {
              name = "d";
              command = "doctrine $@";
            }
            {
              name = "sdr";
              help = "spec-driver";
              command = "spec-driver $@";
            }

            {
              name = "jpi";
              help = "op run -- jailed-pi $@";
              command = "op run -- jailed-pi $@";
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
