# 2D Delaunay for Roblox Lua
Delaunay triangulation

Based on delaunay by iskolbin (https://github.com/iskolbin/delaunay)

**Differences:**

Optimized by ~10x by converting the heavy OOP + metatable implementation to all local functions, and caching some variables

Removed FFI since Roblox uses Luau

**To use:**

call delaunay.triangulate(table) with a table of Vector2s of your points. Returns a table of triangle structs. Loop through them and draw the triangles using the point structs.
