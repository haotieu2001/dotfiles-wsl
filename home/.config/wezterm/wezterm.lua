local wezterm = require("wezterm")

-- The one line to change if your distro differs.
-- Must match a name from `wsl -l -q` exactly (PowerShell, not inside WSL).
local WSL_DISTRO = "Ubuntu-26.04"

local config = wezterm.config_builder()

-- On macOS, WezTerm just runs the local shell. On Windows it would open
-- PowerShell by default, so point it at the WSL distro instead. Declaring
-- wsl_domains replaces WezTerm's auto-discovered list, which also lets us
-- force the starting directory to $HOME rather than /mnt/c/Users/<you>
-- (anything under /mnt is a slow 9p mount).
config.wsl_domains = {
  {
    name = "WSL:" .. WSL_DISTRO,
    distribution = WSL_DISTRO,
    default_cwd = "~",
  },
}
config.default_domain = "WSL:" .. WSL_DISTRO

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
-- 15.0 in the video, but that is a macOS Retina value. 12.0 reads about the
-- same physical size on a typical 1080p/1440p Windows display.
config.font_size = 12.0
config.window_background_opacity = 0.9

-- macos_window_background_blur has no effect on Windows. The Windows
-- equivalent is a system backdrop: "Acrylic" is the frosted blur,
-- "Mica" tints from the desktop wallpaper. Needs opacity < 1.0 to show.
config.win32_system_backdrop = "Acrylic"

config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

return config
