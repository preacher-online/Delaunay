# Delaunay for Roblox Lua
Delaunay triangulation

Based on delaunay by https://github.com/iskolbin/delaunay

**Differences:**

Optimized by ~10x by converting the heavy OOP + metatable implementation to all local functions, and caching some variables

Removed FFI since Roblox uses Luau
