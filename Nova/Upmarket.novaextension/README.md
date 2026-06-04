# Upmarket for Nova

This Nova extension wraps the `upmarket` command line tool. It does not perform
conversion itself.

## Commands

- `Upmarket: Convert Current File to Markdown`
- `Upmarket: Convert File to Markdown...`
- `Upmarket: Insert Converted Markdown...`
- `Upmarket: Copy Converted Markdown...`

## Setup

Install the Upmarket command line tool from the app, then set the command path
in the extension settings if it is not `/usr/local/bin/upmarket`.

The extension asks Nova for process, clipboard, and file read/write entitlements
so it can run `upmarket`, copy results, and read temporary output files.
