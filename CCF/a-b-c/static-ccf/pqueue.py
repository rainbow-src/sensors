# implementation of a priority queue
# by d.a.glynos
# licensed under GPL v3 (see LICENSE file in top dir)

class PQueue:
	def __init__(self, size):
		self.max_size = size
		self.elems = 0
		self.q = []
	
	def full(self):
		return self.elems == self.max_size

	def empty(self):
		return self.elems == 0

	def add(self, item):
		q = self.q
		inserted = False

		if self.full():
			return False

		if self.empty():
			q.append(item)
			self.elems += 1
			return True

		for i in range(self.elems):
			if item.compare(q[i]) < 0:
				self.q = q[:i] + [item] + q[i:]
				self.elems += 1
				return True

		q.append(item)
		self.elems += 1
		return True

	def remove(self):
		if self.empty():
			return None

		self.elems -= 1
		return self.q.pop()
	
	def __str__(self):
		return repr(self.q)

class PQItem:
	def __init__(self, item, prio):
		self.item = item
		self.prio = prio
	
	def compare(self, another):
		return self.prio - another.prio

	def get_item(self):
		return self.item

	def get_prio(self):
		return self.prio

	def __str__(self):
		return "%s %f" % (self.item, self.prio)

	def __repr__(self):
		return str(self)
