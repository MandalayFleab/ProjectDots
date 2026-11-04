extends RefCounted
class_name Difficulty

# A difficulty level: the general parameters both modes share, plus the ones
# of the mode it's for. Every level is one row below -- tune them here.

enum Level { EASY, MEDIUM, HARD }
const LEVEL_NAMES := ["Easy", "Medium", "Hard"]

const MEMORY_LEVELS := {
	Level.EASY: {"shapes": [3, 4], "empty_cells": [0, 2], "compound_colors": [0, 1], "help_uses": 1, "mistakes_allowed": 5, "reveal_seconds": 3.0, "indicator_off_time_reduction": 5.0},
	Level.MEDIUM: {"shapes": [4, 6], "empty_cells": [0, 4], "compound_colors": [1, 3], "help_uses": 2, "mistakes_allowed": 8, "reveal_seconds": 4.0, "indicator_off_time_reduction": 7.0},
	Level.HARD: {"shapes": [6, 9], "empty_cells": [2, 5], "compound_colors": [2, 5], "help_uses": 3, "mistakes_allowed": 12, "reveal_seconds": 5.0, "indicator_off_time_reduction": 10.0},
}

const PUZZLE_LEVELS := {
	Level.EASY: {"shapes": [8, 12], "empty_cells": [2, 3], "compound_colors": [2, 4], "solve_seconds": 60.0, "move_margin": PuzzleParameters.NO_MOVE_LIMIT},
	Level.MEDIUM: {"shapes": [12, 18], "empty_cells": [4, 6], "compound_colors": [4, 6], "solve_seconds": 90.0, "move_margin": 10},
	Level.HARD: {"shapes": [15, 20], "empty_cells": [4, 6], "compound_colors": [5, 8], "solve_seconds": 90.0, "move_margin": 8},
}

var level: Level
var general: GeneralParameters
# Exactly one of these is set, depending on the mode the level is for.
var memory: MemoryParameters = null
var puzzle: PuzzleParameters = null

static func for_memory(p_level: Level) -> Difficulty:
	var difficulty := _make(p_level, MEMORY_LEVELS[p_level])
	difficulty.memory = MemoryParameters.from_dict(MEMORY_LEVELS[p_level])
	return difficulty

static func for_puzzle(p_level: Level) -> Difficulty:
	var difficulty := _make(p_level, PUZZLE_LEVELS[p_level])
	difficulty.puzzle = PuzzleParameters.from_dict(PUZZLE_LEVELS[p_level])
	return difficulty

static func _make(p_level: Level, values: Dictionary) -> Difficulty:
	var difficulty := Difficulty.new()
	difficulty.level = p_level
	difficulty.general = GeneralParameters.from_dict(values)
	return difficulty
