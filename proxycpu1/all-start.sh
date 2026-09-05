#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"; "$BASE/proxy-start.sh"; sleep 2; "$BASE/miners-start.sh"
