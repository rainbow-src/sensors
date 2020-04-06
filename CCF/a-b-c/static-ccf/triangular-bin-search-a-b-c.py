#!/usr/bin/env python
#
# implements a binary search on a triangular 2d shape
# d.a.glynos 3/2/2009
# licensed under GPL v3 (see LICENSE file on top dir)

import sys
import time
from coversets import CoverSetGenerator
from triangle import Triangle, PointTwoD

class TriBinSearch:
	def __init__(self, triangle):
		self.triangle = triangle

	def search(self, func, steps):
		global_best_tr = None
		global_best_val = 0

		triangle = self.triangle
		for i in range(steps):
			print triangle
			triangles = triangle.split(6)
			max = 0
			for tr in triangles:
				val = func(tr.centroid().x, tr.centroid().y)
				if (val >= max):
					max = val
					print max
					triangle = tr
					if (max > global_best_val):
						global_best_val = max
						global_best_tr = tr

		return global_best_tr.centroid(), global_best_val

if __name__ == '__main__':
	if (len(sys.argv) != 6):
		print "usage: %s <steps> <theor_max_script> <script> <w> <input-file>" % (
			sys.argv[0])
		sys.exit(1)
	
	steps = int(sys.argv[1])
	theor_max_script = sys.argv[2]
	script = sys.argv[3]
	w = float(sys.argv[4])
	input = sys.argv[5]

	csg = CoverSetGenerator(theor_max_script, script, w, input)
	max_sets = csg.get_max_sets()
	obj_func = csg.get_obj_func()
	
	tri = Triangle(PointTwoD(1,0), PointTwoD(0,1), PointTwoD(0,0))
	solutions = TriBinSearch(tri)
	start = time.time()
	opt, sets = solutions.search(obj_func, steps)
	finish = time.time()
	print "a=%.2f b=%.2f sets=%i of=%i" % (opt.x, opt.y, sets, max_sets)
	print "time=%.2f secs" % (finish - start)
