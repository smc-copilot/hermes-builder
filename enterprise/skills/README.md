# Enterprise Skills

Place enterprise-managed skills under this directory. During install they are synchronized to:

`%LOCALAPPDATA%\hermes\skills\`

Packages must contain SKILL.md and may be placed directly here or under one
category directory. Directory names are normalized to lowercase kebab-case:
`BaiduSearch` becomes `baidu-search`; `research/BaiduSearch` becomes
`research/baidu-search`. Category paths are preserved; no enterprise prefix is
added. Package files and SKILL.md content are copied unchanged, so declared skill
names and example commands should use the normalized installed path.

Installation merges these packages into the skills root. Unrelated user files
are preserved, but files at the same relative path are enterprise-managed.
