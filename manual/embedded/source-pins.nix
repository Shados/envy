{ config, lib, pkgs, ... }:
{
  sourcePins = config.sn.programs.neovim.lib.fillPinsFromDir /directory/of/envy-pins/output/;
}
