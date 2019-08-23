# 3. Packaging Plugins
If you are using any plugins whose source is specified by 'shortname', then you
will need to prefetch those sources, pin the versions, and provide the pinned
source information to the Envy module in order for it to construct Vim plugin
derivations from the sources.

## Pinning Sources
The `envy-pins` tool is provided to do this. It has a myriad of modes of usage
depending on how you are set up, but the easiest way to do things is:

```bash
# If you are using the NixOS module, use -n to have envy-pins source the list
# of 'shortname' # plugins to pin directly from the module
envy-pins -n ./pin/storage/directory/ update-all
# -m for the home-manager module
envy-pins -m ./pin/storage/directory/ update-all
# -s for the home-manager NixOS sub-module
envy-pins -s ./pin/storage/directory/ update-all
```

`envy-pins` will be installed if you enable either the NixOS or home-maanger
Envy modules. Alternatively, you could access just it with a Nix expression
like:
```nix
{ pkgs }:
let
  envy = (builtins.fetchgit { url = https://github.com/Shados/envy; ref = "master"; });
in pkgs.callPackage "${envy}/envy-pins-package.nix" { }
```

In order to limit the installation closure size on systems where it may not
directly be used (but is still pulled in by an Envy module), `envy-pins` makes
use of a `nix-shell`'s shebang functionality, meaning that it uses Nix to
download its dependencies at run-time, rather than at install-time. This also
means that it can be run directly from a checkout of Envy.

## Specifying Pins To Use
The top-level `sourcePins` option maps `pluginRegistry` attribute names to
source information. While the individual source pins can be manually set if
desired, it is easier to make use of the JSON pin files produced by `envy-pins`
and the built-in helpers to read them:
```nix
{{#include ../embedded/source-pins.nix}}
```
or:
```nix
{{#include ../embedded/source-pins-alt.nix}}
```
