extends BoardCell
class_name BigCell

# Everything (dragging, click-to-place, animation, eviction-on-replace,
# locking, accept/solve rules) is inherited from BoardCell unchanged -- the
# only difference a BigCell has is which piece size it expects.
func expects_big() -> bool:
	return true
