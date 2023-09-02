
globals = {
  "serpent"
}

read_globals = {
  "data",
  defines = {
    other_fields = true,
  },
  "game",
  global = {
    fields = {
      mod = {
        read_only=false,
        other_fields = true,
      }
    }
  },
  "script",
  "settings",
  table = {
    fields = {
      deepcopy = {}
    }
  }
}

ignore = {
  -- ignore "Unused argument" (callback functions)
  "212",
  -- ignore "Line is too long"
  "631"
}
