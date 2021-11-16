--[[
Based on Delaunay triangulation library by Yonaba (roland.yonaba@gmail.com)
url: https://github.com/Yonaba/delaunay
git: git@github.com:Yonaba/delaunay.git
Original LICENSE file contents:
The MIT License (MIT)
Copyright (c) 2013 Roland Y.
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

-- Coded by Ilya Kolbin (iskolbin@gmail.com).
--
-- Deviations from original library:
--
-- 1. Triangulation function takes array instead of tuple;
-- 2. Use LuaJIT FFI if possible( turnable off ).
-- 
-- Using FFI increases performance roughly x2.
--
-- Using FFI reduces memory usage approx. on 40-50%. It's possible to futher
-- decrese memory use by setting _G.DELAUNAY_FFI_TYPE = 'float' -- in this
-- case memory usage drops on 60-70%. Note that you must set it before the library
-- is loaded and shouldn't change it later.


--Edited by psyoper for Roblox Lua
--
--optimized to be ~10x faster by: removing metatables & oop (slight boost), 
--localizing funcs (slight boost), caching triangle circumCircles (huge boost),
--replacing asserts with if statements (slight boost)
--
--removed FFI because roblox doesnt have luaJIT support.
--
--more improvements could be made with more caching, pasting func contents into
--where theyre called, and converting the dicts to tables but then itd be unreadable


local tostring = tostring
local max, sqrt = math.max, math.sqrt
local insert, remove = table.insert, table.remove
local convexMultiplier = 1e3


local delaunay = {}


local function quatCross(a, b, c)
	local p = (a + b + c) * (a + b - c) * (a - b + c) * (-a + b + c)
	return sqrt( p )
end


local function crossProduct(p1, p2, p3) -- Cross product (p1-p2, p2-p3)
	local x1, x2 = p2.x - p1.x, p3.x - p2.x
	local y1, y2 = p2.y - p1.y, p3.y - p2.y
	return x1 * y2 - y1 * x2
end


------------------------------------------------------------POINT------------------------------------------------------------


local function newPoint(x, y)
	return {
		["x"] = x,
		["y"] = y,
		["id"] = 0
	}
end
delaunay.newPoint = newPoint


local function pointsEqual(p1, p2)   
	return p1.x == p2.x and p1.y == p2.y
end


local function pointsDistance2(p1, p2)
	local dx, dy = (p1.x - p2.x), (p1.y - p2.y)
	return dx * dx + dy * dy
end


local function pointsDistance(p1, p2)
	return sqrt(pointsDistance2(p1, p2))
end


local function isPointInCircle(p, cx, cy, r)
	local dx = (cx - p.x)
	local dy = (cy - p.y)
	return ((dx * dx + dy * dy) <= (r * r))
end


------------------------------------------------------------EDGE------------------------------------------------------------


local function newEdge( p1, p2 )
	return {
		["p1"] = p1;
		["p2"] = p2;
	}
end


local function edgesEqual(e1, e2)
	return pointsEqual(e1.p1, e2.p1) and pointsEqual(e1.p2, e2.p2)
end


local function sameEdges(e1, e2)
	return ((e1.p1 == e2.p1) and (e1.p2 == e2.p2))
		or ((e1.p1 == e2.p2) and (e1.p2 == e2.p1))
end


local function edgeLength(e)
	return pointsDistance(e.p1, e.p2)
end


local function getEdgeMidpoint(e)
	local p1 = e.p1
	local p2 = e.p2
	local x = p1.x + (p2.x - p1.x) / 2
	local y = p1.y + (p2.y - p1.y) / 2
	return x, y
end


------------------------------------------------------------TRI------------------------------------------------------------


local function newTri(p1, p2, p3)
	if crossProduct(p1, p2, p3) == 0 then error("flat tri: "..tostring(p1)..tostring(p2)..tostring(p3)) end
	
	local t = {
		["p1"] = p1;
		["p2"] = p2;
		["p3"] = p3;
		["e1"] = newEdge(p1, p2);
		["e2"] = newEdge(p2, p3);
		["e3"] = newEdge(p3, p1);
	}
	local x, y, r = getTriCircumCircle(t)
	
	t.ccx = x
	t.ccy = y
	t.ccr = r
	
	return t
end


local function isTriCW(t) --Checks if the triangle is defined clockwise (sequence p1-p2-p3)
	return (crossProduct(t.p1, t.p2, t.p3) < 0)
end


local function isTriCCW(t) --Checks if the triangle is defined counter-clockwise (sequence p1-p2-p3)
	return (crossProduct(t.p1, t.p2, t.p3) > 0)
end


local function getTriSidesLength(t) --Returns the length of the edges
	return edgeLength(t.e1), edgeLength(t.e2), edgeLength(t.e3)
end


local function getTriCenter(t) --Returns the coordinates of the center
	local p1, p2, p3 = t.p1, t.p2, t.p3
	local x = (p1.x + p2.x + p3.x) / 3
	local y = (p1.y + p2.y + p3.y) / 3
	return x, y
end


local function getTriCircumCenter(t) --Returns the coordinates of the circumcircle center
	local p1, p2, p3 = t.p1, t.p2, t.p3
	local D =  ( p1.x * (p2.y - p3.y) +
		p2.x * (p3.y - p1.y) +
		p3.x * (p1.y - p2.y)) * 2
	local x = (( p1.x * p1.x + p1.y * p1.y) * (p2.y - p3.y) +
		( p2.x * p2.x + p2.y * p2.y) * (p3.y - p1.y) +
		( p3.x * p3.x + p3.y * p3.y) * (p1.y - p2.y))
	local y = (( p1.x * p1.x + p1.y * p1.y) * (p3.x - p2.x) +
		( p2.x * p2.x + p2.y * p2.y) * (p1.x - p3.x) +
		( p3.x * p3.x + p3.y * p3.y) * (p2.x - p1.x))
	return (x / D), (y / D)
end


local function getTriCircumRadius(t) --Returns the radius of the circumcircle
	local a, b, c = getTriSidesLength(t)
	return ((a * b * c) / quatCross(a, b, c))
end


local function getTriArea() --Returns the area
	local a, b, c = getTriSidesLength()
	return (quatCross(a, b, c) / 4)
end


function getTriCircumCircle(t) --Returns the coordinates of the circumcircle center and its radius
	local x, y = getTriCircumCenter(t)
	local r = getTriCircumRadius(t)
	return x, y, r
end


local function isPointInTriCircumCircle(t, p) --Checks if a given point lies into the triangle circumcircle
	return isPointInCircle(p, t.ccx, t.ccy, t.ccr)
end


------------------------------------------------------------DEL------------------------------------------------------------


function delaunay.triangulateVec2s(v2s)
	local points = {}
	
	for _,v2 in pairs(v2s) do
		insert(points, newPoint(v2.x, v2.y))
	end
	
	return delaunay.triangulatePoints(points)
end


function delaunay.triangulatePoints(vertices)
	local nvertices = #vertices
	
	if not (nvertices > 2) then error("Cannot triangulate, needs more than 3 vertices") end
	if nvertices == 3 then
		return {newTri(vertices[1], vertices[2], vertices[3])}
	end

	local trmax = nvertices * 4
	local minX, minY = vertices[1].x, vertices[1].y
	local maxX, maxY = minX, minY

	for i = 1, #vertices do
		local vertex = vertices[i]
		vertex.id = i
		if vertex.x < minX then minX = vertex.x end
		if vertex.y < minY then minY = vertex.y end
		if vertex.x > maxX then maxX = vertex.x end
		if vertex.y > maxY then maxY = vertex.y end
	end

	local convex_mult = convexMultiplier
	local dx, dy = (maxX - minX) * convex_mult, (maxY - minY) * convex_mult
	local deltaMax = max(dx, dy)
	local midx, midy = (minX + maxX) * 0.5, (minY + maxY) * 0.5
	local p1 = newPoint(midx - 2 * deltaMax, midy - deltaMax)
	local p2 = newPoint(midx, midy + 2 * deltaMax)
	local p3 = newPoint(midx + 2 * deltaMax, midy - deltaMax)

	p1.id, p2.id, p3.id = nvertices + 1, nvertices + 2, nvertices + 3
	vertices[p1.id], vertices[p2.id], vertices[p3.id] = p1, p2, p3

	local triangles = {newTri(vertices[nvertices + 1], vertices[nvertices + 2], vertices[nvertices + 3])}
	
	for i = 1, nvertices do
		local edges = {}
		local ntriangles = #triangles
		
		for j = #triangles, 1, -1 do
			local curTriangle = triangles[j]
			if isPointInCircle(vertices[i], curTriangle.ccx, curTriangle.ccy, curTriangle.ccr) then
				local numEdges = #edges
				edges[numEdges + 1] = curTriangle.e1
				edges[numEdges + 2] = curTriangle.e2
				edges[numEdges + 3] = curTriangle.e3
				remove(triangles, j)
			end
		end

		for j = #edges - 1, 1, -1 do
			for k = #edges, j + 1, -1 do
				if edges[j] and edges[k] and sameEdges(edges[j], edges[k]) then
					remove(edges, j)
					remove(edges, k - 1)
				end
			end
		end

		for j = 1, #edges do
			local n = #triangles
			if not (n <= trmax) then error("Generated more than needed triangles") end
			triangles[n + 1] = newTri(edges[j].p1, edges[j].p2, vertices[i])
		end
	end
	
	for i = #triangles, 1, -1 do
		local triangle = triangles[i]
		if triangle.p1.id > nvertices or triangle.p2.id > nvertices or triangle.p3.id > nvertices then
			remove(triangles, i)
		end
	end

	for _ = 1,3 do 
		remove(vertices) 
	end

	return triangles
end


return delaunay
