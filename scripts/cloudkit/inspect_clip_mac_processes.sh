#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
/usr/bin/swift scripts/cloudkit/inspect_clip_mac_processes.swift
