# Scripts catalog

The `scripts/` directory is organized by lifecycle so you can quickly find the right helper. Commands generally expect `sudo`/root unless noted.

## Install (`scripts/install/`)
| Script | Run as | Purpose | Key env vars |
| --- | --- | --- | --- |
| `install_dependencies.sh` | root/sudo | Installs Node.js, OBS Studio, FFmpeg, Xvfb, and creates the `streamer` service user with OBS directories. | `APP_DIR`, `STREAM_USER`, `OBS_HOME`, `NODE_MAJOR` |
| `bootstrap_react_app.sh` | root/sudo | Creates the sample React app in `/opt/youtube-stream/webapp` and replaces the default UI with a lightweight preview. | `APP_DIR`, `STREAM_USER` |

## Config (`scripts/config/`)
| Script | Run as | Purpose | Key env vars |
| --- | --- | --- | --- |
| `configure_obs.sh` | root/sudo | Generates the OBS profile, scene collection, and service config that streams the React app to YouTube; installs the preflight guard. | `STREAM_USER`, `STREAM_GROUP`, `OBS_HOME`, `APP_DIR`, `APP_URL`, `STREAM_URL`, `ENV_FILE`, `VIDEO_BASE_WIDTH`, `VIDEO_BASE_HEIGHT`, `ENABLE_BROWSER_SOURCE_HW_ACCEL`, `LIBGL_ALWAYS_SOFTWARE`, `YOUTUBE_STREAM_KEY` |
| `run_default_config.sh` | root/sudo | Calls `configure_obs.sh` with a placeholder stream key for local testing. Replace the key before production. | `STREAM_USER`, `OBS_HOME`, `YOUTUBE_STREAM_KEY` |
| `configure_obs.sh.bak` | root/sudo | Legacy backup of the OBS configuration script. Prefer `configure_obs.sh`. | (same as `configure_obs.sh`) |
| `config.json` | n/a | Default scene/source template consumed by `configure_obs.sh`. | n/a |

## Services (`scripts/services/`)
| Script | Run as | Purpose | Key env vars |
| --- | --- | --- | --- |
| `setup_services.sh` | root/sudo | Builds the React app and creates/enables `react-web.service` and `obs-headless.service`. | `STREAM_USER`, `APP_DIR`, `OBS_HOME`, `ENV_FILE`, `COLLECTION_NAME`, `VIDEO_BASE_WIDTH`, `VIDEO_BASE_HEIGHT`, `LIBGL_ALWAYS_SOFTWARE` |
| `prepare_streamer.sh` | root/sudo | Ensures the `streamer` account exists with the expected home, password, and permissions. | `STREAM_USER`, `OBS_HOME`, `PASSWORD` |
| `streamer_clone_repo.sh` | root/sudo | Clones this repository into the service user’s home to keep ownership consistent. | `STREAM_USER`, `OBS_HOME`, `REPO_URL`, `TARGET_DIR` |
| `obs_headless_preflight.sh` | root/sudo | Preflight guard for `obs-headless.service`; validates the OBS profile/scene and injects the stream key if missing. | `STREAM_USER`, `OBS_HOME`, `COLLECTION_NAME`, `YOUTUBE_STREAM_KEY` |

## Operations (`scripts/ops/`)
| Script | Run as | Purpose | Key env vars / flags |
| --- | --- | --- | --- |
| `container-entrypoint.sh` | container runtime | Builds/serves the React app and launches OBS in Xvfb when running the Docker image. | `YOUTUBE_STREAM_KEY` (required), `APP_URL`, `APP_DIR`, `STREAM_USER`, `STREAM_GROUP`, `OBS_HOME`, `STREAM_URL`, `VIDEO_BASE_WIDTH`, `VIDEO_BASE_HEIGHT`, `ENABLE_BROWSER_SOURCE_HW_ACCEL`, `LIBGL_ALWAYS_SOFTWARE` |
| `run-services.sh` | root/sudo | Lightweight supervisor for non-systemd hosts; starts the React dev server or build plus headless OBS and exits if either dies. | `APP_DIR`, `STREAM_USER`, `OBS_HOME`, `APP_URL`, `YOUTUBE_STREAM_KEY`, `VIDEO_BASE_WIDTH`, `VIDEO_BASE_HEIGHT`, `ENABLE_BROWSER_SOURCE_HW_ACCEL`, `LIBGL_ALWAYS_SOFTWARE`, `DISPLAY` |
| `diagnostics.sh` | root/sudo (recommended) | Checks dependencies, OBS config, stream key presence, network reachability, and systemd units to pinpoint failures. | `APP_DIR`, `STREAM_USER`, `OBS_HOME`, `ENV_FILE`, `APP_URL`, `STREAM_URL`, `COLLECTION_NAME`, `SCENE_NAME`; flags: `--skip-systemd`, `--skip-network`, `--check-build` |
| `fix_permissions.sh` | root/sudo | Repairs ownership and permissions for generated app, OBS config, env files, and systemd units. | `APP_DIR`, `STREAM_USER`, `OBS_HOME`, `ENV_FILE` |

## Cleanup (`scripts/cleanup/`)
| Script | Run as | Purpose | Key env vars |
| --- | --- | --- | --- |
| `reset_environment.sh` | root/sudo | Stops services, removes generated assets, purges packages, and cleans config so you can reinstall from scratch. | `STREAM_USER`, `APP_DIR`, `OBS_HOME`, `ENV_DIR` |
| `backup.sh` | root/sudo | Creates a timestamped tarball of key paths (scripts, app, OBS configs, env, systemd units) in `/tmp` for recovery. | `BACKUP_DIR` (default `/tmp`) |

## Common workflows
- **Fresh install (systemd host):** run `scripts/install/install_dependencies.sh` → `scripts/install/bootstrap_react_app.sh` → `scripts/config/configure_obs.sh` → `scripts/services/setup_services.sh`, then start the systemd units.
- **Container usage:** build the image with `docker build -t youtube-stream .` and run with `docker run --rm -it -e YOUTUBE_STREAM_KEY="..." -p 3000:3000 youtube-stream` (entrypoint wires up OBS and the app automatically).
- **Maintenance/repair:** use `scripts/ops/diagnostics.sh` to spot issues, `scripts/ops/fix_permissions.sh` to correct ownership, and `scripts/cleanup/reset_environment.sh` when you need to wipe and reinstall.
