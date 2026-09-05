#!/bin/bash
BASE="$(cd "$(dirname "$0")"&&pwd)"; "$BASE/miners-stop.sh"; "$BASE/proxy-stop.sh"
