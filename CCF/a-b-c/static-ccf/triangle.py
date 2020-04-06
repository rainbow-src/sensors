# python class file for triangular shapes
# by d.a.glynos
# licensed under the GPL v3 (see LICENSE file in top dir)


import random

class Line:
	def __init__(self, point_a, point_b):
		self.start = point_a
		self.finish = point_b
	
	def middle(self):
		x = (self.start.x + self.finish.x) / 2.0
		y = (self.start.y + self.finish.y) / 2.0
		return PointTwoD(x,y)

class PointTwoD:
	def __init__(self, x, y):
		self.x = x
		self.y = y
	def __str__(self):
		return "(x=%f,y=%f)" % (self.x, self.y)

class Triangle:
	def __init__(self, a, b, c):
		self.a = a
		self.b = b
		self.c = c

	def centroid(self):
		x = (self.a.x + self.b.x + self.c.x)/3.0
		y = (self.a.y + self.b.y + self.c.y)/3.0
		return PointTwoD(x,y)
	
	# if 2nd arg is 2, the triangle is split into 2 (default)
	# ...        is 6, the triangle is split into 2 triangles per corner
	# when split into two, shuffle enables the selection of a random 
	# corner for splitting the triangle
	def split(self, ways=2, shuffle=True):
		a = self.a
		b = self.b
		c = self.c

		result = ()

		if ways == 2:
			if shuffle:
				points = [a, b, c]
				random.shuffle(points)
				a,b,c = points
			
			result = ( Triangle(a, b, Line(b,c).middle()),
			           Triangle(a, c, Line(b,c).middle()) )
		elif ways == 6:
			result = (
			 Triangle(a, b, Line(b,c).middle()),
			 Triangle(a, c, Line(b,c).middle()),
			 Triangle(a, b, Line(a,c).middle()),
			 Triangle(b, c, Line(a,c).middle()),
			 Triangle(a, c, Line(a,b).middle()),
			 Triangle(b, c, Line(a,b).middle()) )

		return result

	def __str__(self):
		a = self.a
		b = self.b
		c = self.c
		return "A(%f,%f), B(%f,%f), C(%f,%f)" % (
			a.x, a.y, b.x, b.y, c.x, c.y)

