"""Start the development server on loopback; keys stay in the server process."""
from __future__ import annotations

import argparse


def main():
    parser = argparse.ArgumentParser(description="LuxKTC local shared project service")
    parser.add_argument("--port", type=int, default=8740)
    parser.add_argument("--env-file", help="Existing private .env file (read only; never copied)")
    parser.add_argument("--data-dir", help="Local SQLite and private image directory")
    args = parser.parse_args()
    from server.ai import configure_env
    configure_env(args.env_file)
    from server.main import create_app
    import uvicorn
    uvicorn.run(create_app(args.data_dir), host="127.0.0.1", port=args.port, access_log=False)


if __name__ == "__main__":
    main()
