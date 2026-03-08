# Lattice

> A native, local-first app for networked thinking

## Why?

In 2019, I fell in love with [Roam Research](https://roamresearch.com). Its "everything is a block" approach made note-taking click for me for the first time. Roam is a magical app, but the experience has always been a bit clunky, and hasn't improved much over the years.

Since then, many apps have taken some of the concepts introduced by Roam and improved on them, most notably [Obsidian](https://obsidian.md/). However, they seem to have mostly dropped the block approach in favor of Markdown files.

Lattice is my attempt at having it all:

- It's **block based**, with its database schema heavily inspired by Roam's
- It's **local first**. Every page and block live in your device and are fully accessible offline. There is no server.
- It **syncs with iCloud**. Within seconds of editing something, it shows up on all your devices.
- It's **fully native**. Lattice is custom-built for iOS, iPad and macOS using Swift.

## Nerd Details

Lattice is primarily built with SwiftUI, dipping down to UIKit/AppKit in places where more control is needed (mostly text editing). It uses [GRDB](https://github.com/groue/GRDB.swift) to interact with SQLite, and a custom fork of [SQLiteData](https://github.com/pointfreeco/sqlite-data) to sync it with CloudKit.

The database schema (mostly) consists of a single `blocks` table. Both pages and blocks are stored in this table, [emulating Roam's design](https://excalidraw-obsidian.online/blog/Deep+Dive+Into+Roam_s+Data+Structure+-+Why+Roam+is). This is the only table synced on iCloud. There are other "helper tables" (full-text search index, references/ancestors lookup tables, link metadata cache) that get rebuilt on each device using SQLite triggers.

The app adapts to each device's capabilities. On iPad, certain UI elements change between their iOS/macOS counterparts when you connect a keyboard or trackpad. The iPad + magic keyboard combo provides the ultimate Lattice experience imo.

## License

Lattice is open-source software licensed under the MIT license. See the [License file](LICENSE) for more information.
